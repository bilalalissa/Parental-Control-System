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
    let policyRuntime = EndpointPolicyRuntime(
      root: root, deviceID: configuration.deviceID,
      controllerPublicKey: configuration.pairedController?.controllerPublicKey
        ?? configuration.invitation?.controllerPublicKey)
    let policyScheduler = EndpointPolicyScheduler(
      runtime: policyRuntime, repository: repository, log: log)
    let service =
      arguments.noXPC
      ? nil
      : EndpointXPCService(repository: repository, policyRuntime: policyRuntime) { detail in
        log.write(event: "xpc.rejected", detail: detail)
      }
    service?.resume()
    log.write(event: "daemon.started", detail: "Visible parental control endpoint started")

    let retry = EndpointDaemonRetryLoop(
      store: store, repository: repository, log: log,
      policyRuntime: policyRuntime, keychainService: arguments.keychainService)
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
  private let keychainService: String
  private let queue = DispatchQueue(label: "parental-control.endpoint.retry")
  private let timer: DispatchSourceTimer
  private var policy = EndpointReconnectPolicy()
  private var agent: EndpointAgent?
  private var running = false

  init(
    store: ProtectedConfigurationStore, repository: EndpointStatusRepository, log: BoundedLog,
    policyRuntime: EndpointPolicyRuntime,
    keychainService: String
  ) {
    self.store = store
    self.repository = repository
    self.log = log
    self.policyRuntime = policyRuntime
    self.keychainService = keychainService
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
    switch policy.timerFired(connectionState: repository.status().connectionState) {
    case .connect(let retryAfter):
      connect()
      schedule(after: retryAfter)
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
        keychain: KeychainStore(service: keychainService),
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
    let events = runtime.tick(sessionActive: current.sessionState == .active)
    let snapshot = runtime.snapshot()
    repository.update {
      $0.policyVersion = snapshot.0?.version
      $0.policyDecision = snapshot.2?.decision
      $0.policyAction = snapshot.2?.action
      $0.policyReason = snapshot.2?.reason
      $0.policyLastEvaluatedAt = Date()
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
      }
    }
    if !events.isEmpty { EndpointPolicyWake.post() }
  }
}

private struct Arguments {
  var root: URL?
  var noXPC = false
  var runSeconds: TimeInterval?
  var keychainService = "com.bilalalissa.ParentalControlAgent.device"
  init(_ values: [String]) {
    func value(_ flag: String) -> String? {
      guard let index = values.firstIndex(of: flag), index + 1 < values.count else { return nil }
      return values[index + 1]
    }
    if let path = value("--root") { root = URL(fileURLWithPath: path, isDirectory: true) }
    noXPC = values.contains("--no-xpc")
    runSeconds = value("--run-seconds").flatMap(Double.init)
    if let service = value("--keychain-service") { keychainService = String(service.prefix(200)) }
  }
}

do { try DaemonMain.run() } catch {
  FileHandle.standardError.write(Data("agent-daemon error: \(error)\n".utf8))
  exit(1)
}
