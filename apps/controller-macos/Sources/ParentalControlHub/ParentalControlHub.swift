import Foundation
import HubCore

@main
enum ParentalControlHubMain {
  static func main() {
    do {
      try run()
    } catch {
      FileHandle.standardError.write(Data("hub error: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func run() throws {
    let arguments = HubArguments(CommandLine.arguments)
    if arguments.resetLocalTLSIdentity {
      TLSCertificateIdentity.delete(
        label: "com.bilalalissa.ParentalControlController.stage02.tls")
      print("Reset the project-owned local TLS identity.")
      return
    }
    if let command = arguments.command {
      try runControl(command: command, arguments: arguments)
      return
    }
    let database =
      try arguments.databasePath.map(HubDatabase.init(path:)) ?? HubDatabase.applicationSupport()
    let keychain = KeychainStore()
    let ipcKey: Data
    if arguments.readIPCKeyFromStandardInput {
      guard
        let line = readLine(),
        let suppliedKey = Data(base64Encoded: line),
        suppliedKey.count == 32
      else { throw AuthenticatedIPCError.invalidAuthentication }
      ipcKey = suppliedKey
    } else {
      ipcKey = try keychain.loadOrCreateRandom(account: "ui-hub-ipc", byteCount: 32)
    }
    let hub = try LocalHub(
      database: database,
      keychain: keychain,
      heartbeat: AdaptiveHeartbeat(
        activeInterval: arguments.activeHeartbeat,
        idleInterval: arguments.idleHeartbeat,
        offlineAfter: arguments.offlineAfter))
    let state = HubProcessState(hub: hub, runtimeURL: arguments.runtimeURL)
    let ipc = try AuthenticatedIPCServer(key: ipcKey) { request in
      switch request.command {
      case .status: break
      case .createPairing: _ = try hub.createPairingInvitation()
      case .revoke:
        try hub.revoke(deviceID: try requiredDeviceID(request))
      case .unpair:
        try hub.unpair(deviceID: try requiredDeviceID(request))
      case .sendChat:
        guard let text = request.payload["text"]?.stringValue,
          let audienceText = request.payload["audience"]?.stringValue,
          let audience = ChatAudience(rawValue: audienceText)
        else { throw AuthenticatedIPCError.remote("Chat payload is incomplete") }
        let threadID =
          request.payload["threadId"]?.stringValue.flatMap(UUID.init(uuidString:))
          ?? UUID()
        try hub.sendChat(
          deviceID: try requiredDeviceID(request), text: text, audience: audience,
          threadID: threadID)
      case .editChat:
        guard let messageText = request.payload["messageId"]?.stringValue,
          let messageID = UUID(uuidString: messageText),
          let text = request.payload["text"]?.stringValue
        else { throw AuthenticatedIPCError.remote("Chat edit payload is incomplete") }
        try hub.editParentChatMessage(id: messageID, text: text)
      case .deleteChat:
        guard let messageText = request.payload["messageId"]?.stringValue,
          let messageID = UUID(uuidString: messageText)
        else { throw AuthenticatedIPCError.remote("Chat delete payload is incomplete") }
        try hub.deleteParentChatMessage(id: messageID)
      case .configureActivity:
        guard let enabled = request.payload["enabled"]?.boolValue else {
          throw AuthenticatedIPCError.remote("Activity configuration is incomplete")
        }
        let retention = Int(request.payload["retentionDays"]?.integerValue ?? 7)
        try hub.configureActivity(
          ActivityConfiguration(
            deviceID: try requiredDeviceID(request), enabled: enabled,
            retentionDays: retention))
      case .configureBrowser:
        guard let enabled = request.payload["enabled"]?.boolValue else {
          throw AuthenticatedIPCError.remote("Browser configuration is incomplete")
        }
        let retention = Int(request.payload["retentionDays"]?.integerValue ?? 7)
        let policy = try request.payload["websitePolicy"]?.stringValue.map {
          try JSONDecoder().decode(BrowserWebsitePolicy.self, from: Data($0.utf8)).validated()
        }
        try hub.configureBrowser(
          BrowserConfiguration(
            deviceID: try requiredDeviceID(request), enabled: enabled,
            retentionDays: retention, websitePolicy: policy))
      case .markChatRead:
        guard let audienceText = request.payload["audience"]?.stringValue,
          let audience = ChatAudience(rawValue: audienceText)
        else { throw AuthenticatedIPCError.remote("Chat receipt payload is incomplete") }
        try hub.markChatRead(deviceID: try requiredDeviceID(request), audience: audience)
      case .acknowledgeTimeRequest:
        guard let requestText = request.payload["requestId"]?.stringValue,
          let requestID = UUID(uuidString: requestText)
        else { throw AuthenticatedIPCError.remote("Time request identifier is incomplete") }
        try hub.acknowledgeTimeRequest(
          id: requestID, deviceID: try requiredDeviceID(request))
      case .resolveTimeRequest:
        guard let requestText = request.payload["requestId"]?.stringValue,
          let requestID = UUID(uuidString: requestText),
          let decisionText = request.payload["decision"]?.stringValue,
          let decision = MoreTimeRequestState(rawValue: decisionText),
          decision == .approved || decision == .rejected
        else { throw AuthenticatedIPCError.remote("Time request resolution is incomplete") }
        try hub.resolveTimeRequest(
          id: requestID, deviceID: try requiredDeviceID(request), decision: decision)
      case .applyPolicy:
        guard let value = request.payload["policy"]?.stringValue,
          let data = Data(base64Encoded: value),
          let policy = try? PolicyCodec.decoder().decode(ParentalControlPolicy.self, from: data)
        else { throw AuthenticatedIPCError.remote("Policy payload is incomplete") }
        _ = try hub.applyPolicy(policy)
      case .sendAction:
        guard let rawAction = request.payload["action"]?.stringValue,
          let action = PolicyAction(rawValue: rawAction),
          let confirmed = request.payload["confirmed"]?.boolValue
        else { throw AuthenticatedIPCError.remote("Action payload is incomplete") }
        _ = try hub.sendImmediateAction(
          deviceID: try requiredDeviceID(request), action: action, confirmed: confirmed)
      case .rotateAdultVerifier:
        guard let salt = request.payload["salt"]?.stringValue,
          let digest = request.payload["digest"]?.stringValue
        else { throw AuthenticatedIPCError.remote("Adult verifier payload is incomplete") }
        try hub.rotateAdultVerifier(
          deviceID: try requiredDeviceID(request), salt: salt, digest: digest)
      case .shutdown:
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { state.requestShutdown() }
      }
      return try hub.status()
    }
    state.ipc = ipc
    hub.onStatusChange = { status in state.updateHubStatus(status) }
    hub.onError = { error in
      FileHandle.standardError.write(Data("hub warning: \(error)\n".utf8))
    }
    ipc.onReady = { port in state.updateIPCPort(port) }
    ipc.onFailure = { error in
      FileHandle.standardError.write(Data("ipc error: \(error)\n".utf8))
      state.requestShutdown()
    }

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let signalQueue = DispatchQueue(label: "parental-control.hub.signals")
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
    interrupt.setEventHandler { state.requestShutdown() }
    terminate.setEventHandler { state.requestShutdown() }
    interrupt.resume()
    terminate.resume()

    let parentWatchdog: DispatchSourceTimer?
    if let parentPID = arguments.parentProcessID {
      let watchdog = DispatchSource.makeTimerSource(queue: signalQueue)
      watchdog.schedule(deadline: .now() + 1, repeating: 1)
      watchdog.setEventHandler {
        if getppid() != parentPID || kill(parentPID, 0) != 0 { state.requestShutdown() }
      }
      watchdog.resume()
      parentWatchdog = watchdog
    } else {
      parentWatchdog = nil
    }

    ipc.start()
    try hub.start(advertiseBonjour: !arguments.noBonjour)
    state.wait()
    parentWatchdog?.cancel()
    hub.stop()
    ipc.cancel()
    state.removeRuntimeFile()
  }

  private static func runControl(command: IPCCommand, arguments: HubArguments) throws {
    let runtimeData = try Data(contentsOf: arguments.runtimeURL)
    let runtime = try IPCCodec.decoder().decode(HubRuntimeInfo.self, from: runtimeData)
    guard let key = try KeychainStore().data(account: "ui-hub-ipc") else {
      throw AuthenticatedIPCError.invalidAuthentication
    }
    let status = try AuthenticatedIPCClient.send(
      command: command,
      deviceID: arguments.deviceID,
      payload: [:],
      port: runtime.ipcPort,
      key: key)
    let output = HubControlOutput(
      status: status,
      invitationBase64: try status?.invitation.map {
        try IPCCodec.encoder().encode($0).base64EncodedString()
      })
    let encoder = IPCCodec.encoder()
    encoder.outputFormatting.insert(.prettyPrinted)
    FileHandle.standardOutput.write(try encoder.encode(output))
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func requiredDeviceID(_ request: IPCRequest) throws -> String {
    guard let id = request.deviceID, !id.isEmpty else {
      throw AuthenticatedIPCError.remote("A device ID is required")
    }
    return id
  }
}

private struct HubControlOutput: Codable {
  let status: LocalHubStatus?
  let invitationBase64: String?
}

private final class HubProcessState: @unchecked Sendable {
  let hub: LocalHub
  let runtimeURL: URL
  var ipc: AuthenticatedIPCServer?
  private let lock = NSLock()
  private let stop = DispatchSemaphore(value: 0)
  private var ipcPort: UInt16 = 0
  private var hubStatus: LocalHubStatus?
  private var stopped = false
  private var announcedReady = false
  private let startedAt = Date()

  init(hub: LocalHub, runtimeURL: URL) {
    self.hub = hub
    self.runtimeURL = runtimeURL
  }

  func updateIPCPort(_ port: UInt16) {
    lock.lock()
    ipcPort = port
    writeRuntimeIfReady()
    lock.unlock()
  }

  func updateHubStatus(_ status: LocalHubStatus) {
    lock.lock()
    hubStatus = status
    writeRuntimeIfReady()
    lock.unlock()
  }

  func requestShutdown() {
    lock.lock()
    let shouldSignal = !stopped
    stopped = true
    lock.unlock()
    if shouldSignal { stop.signal() }
  }

  func wait() { stop.wait() }

  func removeRuntimeFile() {
    try? FileManager.default.removeItem(at: runtimeURL)
  }

  private func writeRuntimeIfReady() {
    guard ipcPort != 0, let hubStatus, hubStatus.port != 0 else { return }
    do {
      let directory = runtimeURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let info = HubRuntimeInfo(
        processID: getpid(),
        ipcPort: ipcPort,
        hubPort: hubStatus.port,
        certificateFingerprint: hubStatus.certificateFingerprint,
        startedAt: startedAt)
      let data = try IPCCodec.encoder().encode(info)
      try data.write(to: runtimeURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: runtimeURL.path)
      if !announcedReady {
        announcedReady = true
        print("READY ipc=\(ipcPort) websocket=\(hubStatus.port)")
        fflush(stdout)
      }
    } catch {
      FileHandle.standardError.write(Data("runtime file error: \(error)\n".utf8))
      DispatchQueue.global().async { [weak self] in self?.requestShutdown() }
    }
  }
}

private struct HubArguments {
  var databasePath: String?
  var runtimeURL: URL
  var noBonjour = false
  var activeHeartbeat: TimeInterval = 15
  var idleHeartbeat: TimeInterval = 60
  var offlineAfter: TimeInterval = 75
  var command: IPCCommand?
  var deviceID: String?
  var readIPCKeyFromStandardInput = false
  var parentProcessID: pid_t?
  var resetLocalTLSIdentity = false

  init(_ arguments: [String]) {
    runtimeURL = HubRuntime.defaultURL()
    var index = 1
    while index < arguments.count {
      switch arguments[index] {
      case "--database" where index + 1 < arguments.count:
        index += 1
        databasePath = arguments[index]
      case "--runtime" where index + 1 < arguments.count:
        index += 1
        runtimeURL = URL(fileURLWithPath: arguments[index])
      case "--no-bonjour": noBonjour = true
      case "--heartbeat-active" where index + 1 < arguments.count:
        index += 1
        activeHeartbeat = max(0.25, Double(arguments[index]) ?? 15)
      case "--heartbeat-idle" where index + 1 < arguments.count:
        index += 1
        idleHeartbeat = max(activeHeartbeat, Double(arguments[index]) ?? 60)
      case "--offline-after" where index + 1 < arguments.count:
        index += 1
        offlineAfter = max(activeHeartbeat * 2, Double(arguments[index]) ?? 75)
      case "--command" where index + 1 < arguments.count:
        index += 1
        command = IPCCommand(rawValue: arguments[index])
      case "--device" where index + 1 < arguments.count:
        index += 1
        deviceID = arguments[index]
      case "--ipc-key-stdin": readIPCKeyFromStandardInput = true
      case "--parent-pid" where index + 1 < arguments.count:
        index += 1
        parentProcessID = pid_t(arguments[index])
      case "--reset-local-tls-identity": resetLocalTLSIdentity = true
      default: break
      }
      index += 1
    }
  }
}
