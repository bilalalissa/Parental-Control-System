import Foundation
import HubCore
import Network

@main
enum ParentalControlMockAgentMain {
  static func main() {
    do {
      try run()
    } catch {
      FileHandle.standardError.write(Data("mock-agent error: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func run() throws {
    let arguments = try MockArguments(CommandLine.arguments)
    let keychain = KeychainStore(
      service: "com.bilalalissa.ParentalControlController.stage02.mock")
    let privateKey = try keychain.loadOrCreateRandom(
      account: "device-\(arguments.id)", byteCount: 32)
    let identity = try Ed25519Identity(
      keyID: "device-\(arguments.id)", rawPrivateKey: privateKey)
    let state = try MockAgentState(arguments: arguments, identity: identity)
    let peer = try SecureWebSocketClient.connect(
      host: arguments.invitation.host,
      port: arguments.invitation.port,
      certificateFingerprint: arguments.invitation.certificateFingerprint)
    state.peer = peer
    peer.onState = { connectionState in state.connectionChanged(connectionState) }
    peer.onMessage = { data in state.receive(data) }

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let signalQueue = DispatchQueue(label: "parental-control.mock.signals")
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
    interrupt.setEventHandler { state.stop() }
    terminate.setEventHandler { state.stop() }
    interrupt.resume()
    terminate.resume()

    peer.start()
    if arguments.runSeconds > 0 {
      DispatchQueue.global().asyncAfter(deadline: .now() + arguments.runSeconds) { state.stop() }
    }
    state.wait()
    state.shutdown()
    guard state.didPair else { throw MockAgentError.pairingFailed }
  }
}

private enum MockAgentError: Error, CustomStringConvertible {
  case missingArgument(String)
  case invalidInvitation
  case pairingFailed
  case connection(String)

  var description: String {
    switch self {
    case .missingArgument(let name): "Missing required argument \(name)"
    case .invalidInvitation: "The pairing invitation is invalid"
    case .pairingFailed: "The mock did not complete pairing"
    case .connection(let detail): detail
    }
  }
}

private struct PersistedMockState: Codable {
  var sequence: UInt64
}

private final class MockAgentState: @unchecked Sendable {
  let arguments: MockArguments
  let identity: Ed25519Identity
  let replay = ReplayProtector()
  let delta = DeltaSnapshotTracker()
  let lock = NSLock()
  let stopped = DispatchSemaphore(value: 0)
  let timerQueue = DispatchQueue(label: "parental-control.mock.heartbeat")
  var peer: SecureWebSocketPeer?
  var timer: DispatchSourceTimer?
  var sequence: UInt64
  var pairingMessageID: UUID?
  var didPair = false
  var didStop = false
  var heartbeatCount = 0
  var activeHeartbeat: TimeInterval
  var idleHeartbeat: TimeInterval

  init(arguments: MockArguments, identity: Ed25519Identity) throws {
    self.arguments = arguments
    self.identity = identity
    activeHeartbeat = arguments.heartbeat
    idleHeartbeat = max(arguments.heartbeat, arguments.heartbeat * 4)
    if let data = try? Data(contentsOf: arguments.stateURL),
      let state = try? JSONDecoder().decode(PersistedMockState.self, from: data)
    {
      sequence = state.sequence
    } else {
      sequence = 0
    }
  }

  func connectionChanged(_ state: NWConnection.State) {
    switch state {
    case .ready:
      do { try announce() } catch { fail(error) }
    case .failed(let error): fail(MockAgentError.connection(error.localizedDescription))
    default: break
    }
  }

  func receive(_ data: Data) {
    do {
      let envelope = try ProtocolCodec.decode(data)
      try replay.verify(envelope, publicKey: arguments.invitation.controllerPublicKey)
      switch envelope.type {
      case .receipt:
        if let active = envelope.payload["heartbeatActiveSeconds"]?.integerValue {
          activeHeartbeat = max(0.25, TimeInterval(active))
        }
        if let idle = envelope.payload["heartbeatIdleSeconds"]?.integerValue {
          idleHeartbeat = max(activeHeartbeat, TimeInterval(idle))
        }
        if envelope.payload["originalMessageId"]?.stringValue == pairingMessageID?.uuidString {
          lock.lock()
          didPair = true
          lock.unlock()
          emit("paired", detail: arguments.id)
          try sendSnapshot(reason: "paired")
          startHeartbeat(recentActivity: true)
        }
      case .snapshotRequest:
        try sendSnapshot(reason: "request")
        startHeartbeat(recentActivity: true)
      default: break
      }
    } catch { fail(error) }
  }

  func stop() {
    lock.lock()
    let shouldSignal = !didStop
    didStop = true
    lock.unlock()
    if shouldSignal { stopped.signal() }
  }

  func wait() { stopped.wait() }

  func shutdown() {
    timer?.cancel()
    peer?.cancel()
    emit("stopped", detail: arguments.id)
  }

  private func announce() throws {
    let envelope = try identity.sign(
      deviceID: arguments.id,
      sequence: nextSequence(),
      type: .capabilityAnnounce,
      payload: [
        "pairingCode": .string(arguments.invitation.code),
        "name": .string(arguments.name),
        "platform": .string("mock-macOS"),
        "publicKey": .string(identity.publicKeyData.base64EncodedString()),
        "capabilities": .array([
          .string("presence"), .string("delta-snapshot"), .string("receipt"),
        ]),
      ])
    pairingMessageID = envelope.id
    peer?.send(try ProtocolCodec.encode(envelope)) { [weak self] error in
      if let error { self?.fail(error) }
    }
    emit("announcement-sent", detail: arguments.id)
  }

  private func sendSnapshot(reason: String) throws {
    heartbeatCount += 1
    let snapshot: [String: JSONValue] = [
      "state": .string("online")
    ]
    let update = delta.delta(for: snapshot)
    let envelope = try identity.sign(
      deviceID: arguments.id,
      sequence: nextSequence(),
      type: .snapshotResponse,
      payload: [
        "snapshotVersion": .integer(Int64(clamping: update.version)),
        "changed": .object(update.changed),
        "reason": .string(reason),
      ])
    peer?.send(try ProtocolCodec.encode(envelope)) { [weak self] error in
      if let error { self?.fail(error) }
    }
  }

  private func startHeartbeat(recentActivity: Bool) {
    let interval = recentActivity ? activeHeartbeat : idleHeartbeat
    if let timer {
      timer.schedule(deadline: .now() + interval, repeating: interval)
      return
    }
    let created = DispatchSource.makeTimerSource(queue: timerQueue)
    created.schedule(deadline: .now() + interval, repeating: interval)
    created.setEventHandler { [weak self] in
      guard let self else { return }
      do {
        try sendSnapshot(reason: "adaptive-heartbeat")
        if heartbeatCount >= 3 { startHeartbeat(recentActivity: false) }
      } catch { fail(error) }
    }
    timer = created
    created.resume()
  }

  private func nextSequence() -> UInt64 {
    lock.lock()
    sequence += 1
    let current = sequence
    lock.unlock()
    let state = PersistedMockState(sequence: current)
    if let data = try? JSONEncoder().encode(state) {
      try? FileManager.default.createDirectory(
        at: arguments.stateURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try? data.write(to: arguments.stateURL, options: .atomic)
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: arguments.stateURL.path)
    }
    return current
  }

  private func fail(_ error: Error) {
    FileHandle.standardError.write(Data("mock-agent warning: \(error)\n".utf8))
    stop()
  }

  private func emit(_ event: String, detail: String) {
    let line = "{\"event\":\"\(event)\",\"deviceId\":\"\(detail)\"}\n"
    FileHandle.standardOutput.write(Data(line.utf8))
  }
}

private struct MockArguments: Sendable {
  let invitation: PairingInvitation
  let id: String
  let name: String
  let heartbeat: TimeInterval
  let runSeconds: TimeInterval
  let stateURL: URL

  init(_ arguments: [String]) throws {
    func value(_ name: String) -> String? {
      guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }
    guard
      let invitationText = value("--invitation"),
      let invitationData = Data(base64Encoded: invitationText),
      let invitation = try? IPCCodec.decoder().decode(PairingInvitation.self, from: invitationData),
      !invitation.controllerPublicKey.isEmpty
    else { throw MockAgentError.invalidInvitation }
    guard let id = value("--id"), !id.isEmpty else {
      throw MockAgentError.missingArgument("--id")
    }
    self.invitation = invitation
    self.id = String(id.prefix(80))
    name = String((value("--name") ?? id).prefix(80))
    heartbeat = max(0.25, Double(value("--heartbeat") ?? "15") ?? 15)
    runSeconds = max(0, Double(value("--run-seconds") ?? "0") ?? 0)
    if let statePath = value("--state") {
      stateURL = URL(fileURLWithPath: statePath)
    } else {
      let base = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first!.appendingPathComponent("ParentalControlMockAgent", isDirectory: true)
      stateURL = base.appendingPathComponent("\(self.id).json")
    }
  }
}
