import Foundation
import HubCore
import Security

enum HubClientError: Error, CustomStringConvertible {
  case helperMissing
  case helperNotRunning
  case keyUnavailable

  var description: String {
    switch self {
    case .helperMissing: "The local hub helper is not included in this build"
    case .helperNotRunning: "The local hub stopped; use an explicit action to restart it"
    case .keyUnavailable: "The local hub IPC key is unavailable"
    }
  }
}

@MainActor
final class HubClient {
  // A first launch after a signing change can block in SecurityAgent while the adult reads and
  // answers a Keychain prompt. Keep the UI asynchronous, but do not kill that helper on the old
  // three-second machine-only readiness deadline.
  static let helperStartupPollMilliseconds = 100
  static let helperStartupPollCount = 900

  private var helperProcess: Process?
  private var ipcKey: Data?
  private let startupCoordinator = HubStartupCoordinator()

  func ensureRunning() async throws {
    if let process = helperProcess,
      process.isRunning,
      ipcKey != nil,
      let runtime = try? HubRuntime.read(),
      runtime.processID == process.processIdentifier
    {
      return
    }
    try await startupCoordinator.run { [weak self] in
      guard let self else { throw AuthenticatedIPCError.timeout }
      try await self.launchHelper()
    }
  }

  private func launchHelper() async throws {
    if let existing = helperProcess {
      if existing.isRunning { existing.terminate() }
      helperProcess = nil
      ipcKey = nil
    }
    let candidates = [
      Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ParentalControlHub"),
      Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(
        "ParentalControlHub"),
    ].compactMap { $0 }
    guard
      let helper = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }
      )
    else { throw HubClientError.helperMissing }
    let process = Process()
    process.executableURL = helper
    process.arguments = [
      "--ipc-key-stdin", "--parent-pid", "\(ProcessInfo.processInfo.processIdentifier)",
    ]
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    var bytes = Data(count: 32)
    guard
      bytes.withUnsafeMutableBytes({
        SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
      }) == errSecSuccess
    else { throw HubClientError.keyUnavailable }
    try? FileManager.default.removeItem(at: HubRuntime.defaultURL())
    try process.run()
    input.fileHandleForWriting.write(Data((bytes.base64EncodedString() + "\n").utf8))
    try input.fileHandleForWriting.close()
    helperProcess = process
    ipcKey = bytes
    for _ in 0..<Self.helperStartupPollCount {
      if let runtime = try? HubRuntime.read(), runtime.processID == process.processIdentifier {
        return
      }
      if !process.isRunning { break }
      try await Task.sleep(for: .milliseconds(Self.helperStartupPollMilliseconds))
    }
    if process.isRunning { process.terminate() }
    if let runtime = try? HubRuntime.read(), runtime.processID == process.processIdentifier {
      try? FileManager.default.removeItem(at: HubRuntime.defaultURL())
    }
    if helperProcess === process {
      helperProcess = nil
      ipcKey = nil
    }
    throw AuthenticatedIPCError.timeout
  }

  func status() async throws -> LocalHubStatus? {
    try await request(.status)
  }

  func statusIfRunning() async throws -> LocalHubStatus? {
    let (runtime, key) = try currentSession()
    return try await send(.status, runtime: runtime, key: key)
  }

  func createPairing() async throws -> LocalHubStatus? {
    try await request(.createPairing)
  }

  func revoke(deviceID: String) async throws -> LocalHubStatus? {
    try await request(.revoke, deviceID: deviceID)
  }

  func unpair(deviceID: String) async throws -> LocalHubStatus? {
    try await request(.unpair, deviceID: deviceID)
  }

  func sendChat(
    deviceID: String, text: String, audience: ChatAudience, threadID: UUID
  ) async throws -> LocalHubStatus? {
    try await request(
      .sendChat, deviceID: deviceID,
      payload: [
        "text": .string(text), "audience": .string(audience.rawValue),
        "threadId": .string(threadID.uuidString),
      ])
  }

  func editChat(messageID: UUID, text: String) async throws -> LocalHubStatus? {
    try await request(
      .editChat,
      payload: ["messageId": .string(messageID.uuidString), "text": .string(text)])
  }

  func deleteChat(messageID: UUID) async throws -> LocalHubStatus? {
    try await request(
      .deleteChat, payload: ["messageId": .string(messageID.uuidString)])
  }

  func configureActivity(
    deviceID: String, enabled: Bool, retentionDays: Int
  ) async throws -> LocalHubStatus? {
    try await request(
      .configureActivity, deviceID: deviceID,
      payload: [
        "enabled": .bool(enabled), "retentionDays": .integer(Int64(retentionDays)),
      ])
  }

  func configureBrowser(
    deviceID: String, enabled: Bool, retentionDays: Int
  ) async throws -> LocalHubStatus? {
    try await request(
      .configureBrowser, deviceID: deviceID,
      payload: [
        "enabled": .bool(enabled), "retentionDays": .integer(Int64(retentionDays)),
      ])
  }

  func markChatRead(deviceID: String, audience: ChatAudience) async throws -> LocalHubStatus? {
    try await request(
      .markChatRead, deviceID: deviceID,
      payload: ["audience": .string(audience.rawValue)])
  }

  func applyPolicy(_ policy: ParentalControlPolicy) async throws -> LocalHubStatus? {
    let data = try PolicyCodec.encoder().encode(policy)
    return try await request(
      .applyPolicy, deviceID: policy.deviceID,
      payload: ["policy": .string(data.base64EncodedString())])
  }

  func sendAction(
    deviceID: String, action: PolicyAction, confirmed: Bool
  ) async throws -> LocalHubStatus? {
    try await request(
      .sendAction, deviceID: deviceID,
      payload: ["action": .string(action.rawValue), "confirmed": .bool(confirmed)])
  }

  func rotateAdultVerifier(
    deviceID: String, salt: String, digest: String
  ) async throws -> LocalHubStatus? {
    try await request(
      .rotateAdultVerifier, deviceID: deviceID,
      payload: ["salt": .string(salt), "digest": .string(digest)])
  }

  func stop() {
    guard let runtime = try? HubRuntime.read(), let key = ipcKey else { return }
    _ = try? AuthenticatedIPCClient.send(
      command: .shutdown, port: runtime.ipcPort, key: key, timeout: 1)
    helperProcess = nil
    ipcKey = nil
  }

  private func request(
    _ command: IPCCommand, deviceID: String? = nil,
    payload: [String: JSONValue] = [:]
  ) async throws
    -> LocalHubStatus?
  {
    try await ensureRunning()
    let (runtime, key) = try currentSession()
    return try await send(
      command, deviceID: deviceID, payload: payload, runtime: runtime, key: key)
  }

  private func currentSession() throws -> (HubRuntimeInfo, Data) {
    guard let process = helperProcess, process.isRunning,
      let runtime = try? HubRuntime.read(),
      runtime.processID == process.processIdentifier
    else { throw HubClientError.helperNotRunning }
    guard let key = ipcKey else { throw HubClientError.keyUnavailable }
    return (runtime, key)
  }

  private func send(
    _ command: IPCCommand,
    deviceID: String? = nil,
    payload: [String: JSONValue] = [:],
    runtime: HubRuntimeInfo,
    key: Data
  ) async throws -> LocalHubStatus? {
    return try await Task.detached {
      try AuthenticatedIPCClient.send(
        command: command, deviceID: deviceID, payload: payload,
        port: runtime.ipcPort, key: key)
    }.value
  }
}

@MainActor
final class HubStartupCoordinator {
  private var startupTask: Task<Void, Error>?

  func run(
    _ operation: @escaping @MainActor @Sendable () async throws -> Void
  ) async throws {
    if let startupTask {
      return try await startupTask.value
    }
    let task = Task { @MainActor in try await operation() }
    startupTask = task
    do {
      try await task.value
      startupTask = nil
    } catch {
      startupTask = nil
      throw error
    }
  }
}
