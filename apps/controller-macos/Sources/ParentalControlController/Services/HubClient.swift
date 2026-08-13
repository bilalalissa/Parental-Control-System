import Foundation
import HubCore
import Security

enum HubClientError: Error, CustomStringConvertible {
  case helperMissing
  case keyUnavailable

  var description: String {
    switch self {
    case .helperMissing: "The local hub helper is not included in this build"
    case .keyUnavailable: "The local hub IPC key is unavailable"
    }
  }
}

@MainActor
final class HubClient {
  private var helperProcess: Process?
  private var ipcKey: Data?

  func ensureRunning() async throws {
    if helperProcess?.isRunning == true, ipcKey != nil, (try? HubRuntime.read()) != nil { return }
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
    for _ in 0..<30 {
      if (try? HubRuntime.read()) != nil { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw AuthenticatedIPCError.timeout
  }

  func status() async throws -> LocalHubStatus? {
    try await request(.status)
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

  func stop() {
    guard let runtime = try? HubRuntime.read(), let key = ipcKey else { return }
    _ = try? AuthenticatedIPCClient.send(
      command: .shutdown, port: runtime.ipcPort, key: key, timeout: 1)
    helperProcess = nil
    ipcKey = nil
  }

  private func request(_ command: IPCCommand, deviceID: String? = nil) async throws
    -> LocalHubStatus?
  {
    try await ensureRunning()
    let runtime = try HubRuntime.read()
    guard let key = ipcKey else { throw HubClientError.keyUnavailable }
    return try await Task.detached {
      try AuthenticatedIPCClient.send(
        command: command, deviceID: deviceID, port: runtime.ipcPort, key: key)
    }.value
  }
}
