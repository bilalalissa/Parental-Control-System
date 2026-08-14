import EndpointCore
import Foundation

enum ControlError: Error, CustomStringConvertible {
  case usage
  case administratorRequired
  var description: String {
    self == .administratorRequired
      ? "Pairing requires administrator privileges."
      : "usage: ParentalControlAgentCtl [--root PATH] pair --invitation BASE64"
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
  guard arguments.contains("pair"), let token = value("--invitation") else {
    throw ControlError.usage
  }
  let root =
    value("--root").map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? ProtectedConfigurationStore.systemRoot
  if value("--root") == nil, geteuid() != 0 { throw ControlError.administratorRequired }
  try ProtectedConfigurationStore(root: root).installPairingToken(token)
  print(
    "Pairing invitation installed. Restart com.bilalalissa.ParentalControlAgent.daemon to connect.")
} catch {
  FileHandle.standardError.write(Data("agentctl: \(error)\n".utf8))
  exit(2)
}
