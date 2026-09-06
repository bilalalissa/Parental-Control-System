import EndpointCore
import Foundation
import HubCore

enum DaemonMain {
  static func run() throws {
    let arguments = Arguments(CommandLine.arguments)
    let root = arguments.root ?? ProtectedConfigurationStore.systemRoot
    let store = ProtectedConfigurationStore(root: root)
    let configuration = try store.load()
    let repository = EndpointStatusRepository(
      initial: DeviceSnapshotCollector.collect(deviceID: configuration.deviceID),
      persistenceURL: root.appendingPathComponent("runtime-queue.json"))
    let log = BoundedLog(directory: root.appendingPathComponent("Logs", isDirectory: true))
    let identityData = try EndpointIdentityFileStore(
      root: root, expectedOwnerID: arguments.root == nil ? 0 : nil
    ).loadOrCreateRandom()
    let identity = try Ed25519Identity(
      keyID: "device-\(configuration.deviceID)", rawPrivateKey: identityData)
    let policyRuntime = EndpointPolicyRuntime(
      root: root, deviceID: configuration.deviceID,
      controllerPublicKey: configuration.pairedController?.controllerPublicKey
        ?? configuration.invitation?.controllerPublicKey)
    if let maintenanceUntil = EndpointInstallerMaintenanceMarker.consume(
      root: root, expectedOwnerID: arguments.root == nil ? 0 : nil)
    {
      try policyRuntime.beginInstallerMaintenance(until: maintenanceUntil)
      log.write(
        event: "installer.maintenance",
        detail: "Administrator-authorized recovery window activated with hard expiry")
    }
    let policyScheduler = EndpointPolicyScheduler(
      runtime: policyRuntime, repository: repository, log: log)
    let service: EndpointXPCService?
    if arguments.noXPC {
      service = nil
    } else {
      service = try EndpointXPCService(
        repository: repository,
        policyRuntime: policyRuntime,
        clientManifestURL: root.appendingPathComponent(EndpointXPCClientManifest.fileName),
        requireRootProtection: arguments.root == nil
      ) { detail in
        log.write(event: "xpc.rejected", detail: detail)
      }
    }
    service?.resume()
    log.write(event: "daemon.started", detail: "Visible parental control endpoint started")

    let retry = EndpointDaemonRetryLoop(
      store: store, repository: repository, log: log,
      policyRuntime: policyRuntime, identity: identity)
    retry.start()
    policyScheduler.start()

    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let semaphore = DispatchSemaphore(value: 0)
    let signals = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler { semaphore.signal() }
      source.resume()
      return source
    }
    if let seconds = arguments.runSeconds {
      DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { semaphore.signal() }
    }
    semaphore.wait()
    _ = signals
    retry.stop()
    policyScheduler.stop()
    service?.invalidate()
    log.write(event: "daemon.stopped", detail: "Normal shutdown")
  }
}

private final class EndpointDaemonRetryLoop: @unchecked Sendable {
  private let store: ProtectedConfigurationStore
  private let repository: EndpointStatusRepository
  private let log: BoundedLog
  private let policyRuntime: EndpointPolicyRuntime
  private let identity: Ed25519Identity
  private let queue = DispatchQueue(label: "parental-control.endpoint.retry")
  private let timer: DispatchSourceTimer
  private var policy = EndpointReconnectPolicy()
  private var agent: EndpointAgent?
  private var running = false

  init(
    store: ProtectedConfigurationStore, repository: EndpointStatusRepository, log: BoundedLog,
    policyRuntime: EndpointPolicyRuntime, identity: Ed25519Identity
  ) {
    self.store = store
    self.repository = repository
    self.log = log
    self.policyRuntime = policyRuntime
    self.identity = identity
    timer = DispatchSource.makeTimerSource(queue: queue)
  }

  func start() {
    queue.sync {
      guard !running else { return }
      running = true
      timer.setEventHandler { [weak self] in self?.timerFired() }
      timer.schedule(deadline: .now())
      timer.resume()
    }
  }

  func stop() {
    queue.sync {
      guard running else { return }
      running = false
      timer.setEventHandler {}
      timer.cancel()
      agent?.stop()
      agent = nil
    }
  }

  private func timerFired() {
    guard running else { return }
    let status = repository.status()
    switch policy.timerFired(
      connectionState: status.connectionState,
      lastControllerContact: status.lastControllerContact)
    {
    case .connect(let retryAfter):
      connect()
      schedule(after: retryAfter)
    case .reconnect:
      log.write(
        event: "connection.stale",
        detail: "Controller contact exceeded the bounded heartbeat window; reconnecting")
      agent?.stop()
      agent = nil
      repository.update { if $0.connectionState != .unpaired { $0.connectionState = .offline } }
      connect()
      schedule(after: policy.shortDelay)
    case .wait(let delay):
      schedule(after: delay)
    }
  }

  private func connect() {
    guard repository.status().connectionState != .online else { return }
    agent?.stop()
    guard let current = try? store.load(),
      current.invitation != nil || current.pairedController != nil
    else {
      repository.update { $0.connectionState = .unpaired }
      return
    }
    do {
      let next = try EndpointAgent(
        store: store, repository: repository, log: log,
        suppliedIdentity: identity,
        policyRuntime: policyRuntime,
        onEstablishedConnectionLoss: { [weak self] in self?.connectionLost() })
      agent = next
      try next.start()
    } catch {
      agent = nil
      repository.update {
        $0.connectionState =
          current.invitation == nil && current.pairedController == nil ? .unpaired : .offline
      }
      log.write(event: "connection.retry", detail: String(describing: error))
    }
  }

  private func connectionLost() {
    queue.async { [weak self] in
      guard let self, running else { return }
      schedule(after: policy.establishedConnectionLost())
    }
  }

  private func schedule(after delay: TimeInterval) {
    timer.schedule(deadline: .now() + delay)
  }
}

private final class EndpointPolicyScheduler: @unchecked Sendable {
  private let runtime: EndpointPolicyRuntime
  private let repository: EndpointStatusRepository
  private let log: BoundedLog
  private let queue = DispatchQueue(label: "parental-control.endpoint.policy")
  private let timer = DispatchSource.makeTimerSource()
  private var running = false

  init(
    runtime: EndpointPolicyRuntime, repository: EndpointStatusRepository, log: BoundedLog
  ) {
    self.runtime = runtime
    self.repository = repository
    self.log = log
  }

  func start() {
    guard !running else { return }
    running = true
    timer.setEventHandler { [weak self] in self?.evaluate() }
    timer.schedule(deadline: .now(), repeating: 15)
    timer.activate()
  }

  func stop() {
    guard running else { return }
    running = false
    timer.setEventHandler {}
    timer.cancel()
  }

  private func evaluate() {
    let current = repository.status()
    let now = Date()
    let sessionActive = current.sessionState == .active
    let events = runtime.tick(now: now, sessionActive: sessionActive)
    let snapshot = runtime.snapshot()
    let nextRestriction = runtime.projectedRestrictionDate(
      now: now, sessionActive: sessionActive)
    let nextAllowance = runtime.projectedAllowanceDate(now: now)
    let allowanceSummary = runtime.allowanceSummary(
      now: now, sessionActive: sessionActive, nextRestrictionAt: nextRestriction)
    repository.update {
      $0.policyVersion = snapshot.0?.version
      $0.policyDecision = snapshot.2?.decision
      $0.policyAction = snapshot.2?.action
      $0.policyReason = snapshot.2?.reason
      $0.policyLastEvaluatedAt = now
      $0.policyNextRestrictionAt = nextRestriction
      $0.policyNextAllowanceAt = nextAllowance
      $0.policyAllowanceSummary = allowanceSummary
      $0.policyClockTrusted = snapshot.1.clockTrusted
      $0.adultOverrideUntil = snapshot.1.adultOverrideUntil
    }
    for event in events {
      switch event {
      case .warning(let minutes, let action, _):
        log.write(
          event: "policy.warning", detail: "Warning \(minutes) minutes before \(action.rawValue)")
      case .enforce(let action, _):
        log.write(
          event: "policy.enforce", detail: "Requested allowlisted action \(action.rawValue)")
      case .clockChangeDetected:
        log.write(event: "policy.clock-change", detail: "Wall clock continuity check failed")
      case .bonusGranted:
        log.write(event: "policy.bonus", detail: "Parent-approved bonus time installed")
      case .timeRequestRejected(let minutes):
        log.write(
          event: "time.request.rejected",
          detail: "Parent rejected a bounded \(minutes)-minute request")
      }
    }
    if !events.isEmpty { EndpointPolicyWake.post() }
  }
}

private struct Arguments {
  var root: URL?
  var noXPC = false
  var runSeconds: TimeInterval?
  init(_ values: [String]) {
    func value(_ flag: String) -> String? {
      guard let index = values.firstIndex(of: flag), index + 1 < values.count else { return nil }
      return values[index + 1]
    }
    if let path = value("--root") { root = URL(fileURLWithPath: path, isDirectory: true) }
    noXPC = values.contains("--no-xpc")
    runSeconds = value("--run-seconds").flatMap(Double.init)
  }
}

do { try DaemonMain.run() } catch {
  FileHandle.standardError.write(Data("agent-daemon error: \(error)\n".utf8))
  exit(1)
}
