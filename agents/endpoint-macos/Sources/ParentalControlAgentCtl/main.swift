import EndpointCore
import Foundation

enum ControlError: Error, CustomStringConvertible {
  case usage
  case administratorRequired
  var description: String {
    self == .administratorRequired
      ? "Pairing requires administrator privileges."
      : "usage: parental-control-agentctl status | [--root PATH] pair --invitation BASE64"
  }
}

do {
  let arguments = CommandLine.arguments
  func value(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }
  if arguments.contains("status") {
    let signal = DispatchSemaphore(value: 0)
    let box = StatusResultBox()
    let client = EndpointXPCClient()
    client.fetchStatus { result in
      box.set(result)
      signal.signal()
    }
    guard signal.wait(timeout: .now() + 5) == .success else {
      throw EndpointXPCError.remote("endpoint service timed out")
    }
    let status = try box.get().get()
    let payload = try JSONEncoder.endpoint.encode(status)
    print(String(decoding: payload, as: UTF8.self))
  } else {
    guard arguments.contains("pair"), let token = value("--invitation") else {
      throw ControlError.usage
    }
    let root =
      value("--root").map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? ProtectedConfigurationStore.systemRoot
    if value("--root") == nil, geteuid() != 0 { throw ControlError.administratorRequired }
    try ProtectedConfigurationStore(root: root).installPairingToken(token)
    print(
      "Pairing invitation installed. Restart com.bilalalissa.ParentalControlAgent.daemon to connect."
    )
  }
} catch {
  FileHandle.standardError.write(Data("agentctl: \(error)\n".utf8))
  exit(2)
}

private final class StatusResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Result<EndpointStatus, Error>?
  func set(_ result: Result<EndpointStatus, Error>) {
    lock.lock()
    value = result
    lock.unlock()
  }
  func get() throws -> Result<EndpointStatus, Error> {
    lock.lock()
    defer { lock.unlock() }
    guard let value else { throw EndpointXPCError.malformed }
    return value
  }
}
