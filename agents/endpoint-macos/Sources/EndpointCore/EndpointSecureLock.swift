import Foundation

public enum EndpointSecureLockVerifier {
  public static let executable = "/usr/sbin/sysadminctl"
  public static let arguments = ["-screenLock", "status"]
  public static let refreshInterval: TimeInterval = 60

  public static func parse(statusText: String, terminationStatus: Int32)
    -> EndpointSecureLockReadiness
  {
    guard terminationStatus == 0 else { return .verificationUnavailable }
    let normalized = statusText.lowercased()
      .replacingOccurrences(of: "\n", with: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    let delayPrefix = "screenlock delay is "
    if normalized.contains(delayPrefix + "immediate") { return .ready }
    if let range = normalized.range(of: delayPrefix) {
      let value = normalized[range.upperBound...].split(separator: " ").first.flatMap {
        Double($0)
      }
      if value == 0 { return .ready }
    }
    if normalized.contains("screenlock is off")
      || normalized.contains("screenlock delay is off")
      || normalized.contains("screenlock delay is never")
    {
      return .passwordNotRequired
    }
    if normalized.contains("screenlock delay is") { return .passwordDelayed }
    return .verificationUnavailable
  }

  public static func shouldRefresh(lastCheckedAt: Date?, now: Date) -> Bool {
    guard let lastCheckedAt else { return true }
    let age = now.timeIntervalSince(lastCheckedAt)
    return age < 0 || age >= refreshInterval
  }

  /// Uses one fixed, read-only macOS command. No shell, credentials, or mutable arguments are
  /// involved, and output is retained only long enough to classify the password-delay setting.
  public static func current() -> EndpointSecureLockReadiness {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let text = String(decoding: data.prefix(2_048), as: UTF8.self)
      return parse(statusText: text, terminationStatus: process.terminationStatus)
    } catch {
      return .verificationUnavailable
    }
  }
}
