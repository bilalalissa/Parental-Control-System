import Darwin
import EndpointCore
import Foundation
import Security

private enum HostError: Error {
  case unauthorized
  case malformed
  case oversized
  case unavailable
}

private struct BrowserParentInspector {
  static func expectedBrowser(origin: String) -> String? {
    let parentPID = getppid()
    var dynamicCode: SecCode?
    guard
      SecCodeCopyGuestWithAttributes(
        nil, [kSecGuestAttributePid as String: NSNumber(value: parentPID)] as CFDictionary, [],
        &dynamicCode) == errSecSuccess,
      let dynamicCode
    else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess, let staticCode
    else { return nil }
    let valid =
      SecStaticCodeCheckValidity(
        staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
    var path: CFURL?
    var information: CFDictionary?
    guard SecCodeCopyPath(staticCode, [], &path) == errSecSuccess,
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let executablePath = (path as URL?)?.path,
      let signing = information as? [CFString: Any],
      let identifier = signing[kSecCodeInfoIdentifier] as? String,
      let teamIdentifier = signing[kSecCodeInfoTeamIdentifier] as? String
    else { return nil }
    return BrowserCallerAuthorization.expectedBrowser(
      origin: origin, executablePath: executablePath, signingIdentifier: identifier,
      teamIdentifier: teamIdentifier, signatureValid: valid)
  }
}

private func readExactly(_ count: Int) throws -> Data? {
  var result = Data()
  while result.count < count {
    let chunk = try FileHandle.standardInput.read(upToCount: count - result.count) ?? Data()
    if chunk.isEmpty {
      if result.isEmpty { return nil }
      throw HostError.malformed
    }
    result.append(chunk)
  }
  return result
}

private func readMessage() throws -> Data? {
  guard let header = try readExactly(4) else { return nil }
  let length = header.withUnsafeBytes { bytes in
    bytes.loadUnaligned(as: UInt32.self).littleEndian
  }
  guard length > 0, length <= BrowserNativeMessaging.maximumMessageBytes else {
    throw HostError.oversized
  }
  guard let payload = try readExactly(Int(length)), payload.count == Int(length) else {
    throw HostError.malformed
  }
  return payload
}

private func writeMessage<T: Encodable>(_ value: T) throws {
  let payload = try JSONEncoder.endpoint.encode(value)
  guard payload.count <= BrowserNativeMessaging.maximumMessageBytes else {
    throw HostError.oversized
  }
  var length = UInt32(payload.count).littleEndian
  let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
  try FileHandle.standardOutput.write(contentsOf: header)
  try FileHandle.standardOutput.write(contentsOf: payload)
}

private func awaitResult<T>(
  _ start: (@escaping @Sendable (Result<T, Error>) -> Void) -> Void
) throws -> T {
  let semaphore = DispatchSemaphore(value: 0)
  let lock = NSLock()
  nonisolated(unsafe) var result: Result<T, Error>?
  start { value in
    lock.lock()
    result = value
    lock.unlock()
    semaphore.signal()
  }
  guard semaphore.wait(timeout: .now() + 5) == .success else { throw HostError.unavailable }
  lock.lock()
  defer { lock.unlock() }
  return try result?.get() ?? { throw HostError.unavailable }()
}

private func run() throws {
  guard CommandLine.arguments.count >= 2,
    let browser = BrowserParentInspector.expectedBrowser(origin: CommandLine.arguments[1])
  else { throw HostError.unauthorized }
  let client = EndpointXPCClient()
  while let data = try readMessage() {
    do {
      let request = try JSONDecoder.endpoint.decode(BrowserNativeRequest.self, from: data)
      let configuration = try awaitResult { client.fetchBrowserConfiguration(completion: $0) }
      if request.type == "configuration.query" {
        try writeMessage(
          BrowserNativeResponse(
            accepted: true, enabled: configuration.enabled, browser: browser))
        continue
      }
      guard configuration.enabled else {
        try writeMessage(
          BrowserNativeResponse(accepted: false, enabled: false, browser: browser))
        continue
      }
      guard let update = request.validatedUpdate(expectedBrowser: browser) else {
        throw HostError.malformed
      }
      try awaitResult { client.updateBrowser(update, completion: $0) }
      try writeMessage(
        BrowserNativeResponse(
          accepted: true, enabled: true, acceptedTabs: update.tabs.count, browser: browser))
    } catch {
      try writeMessage(
        BrowserNativeResponse(
          accepted: false, enabled: false, error: "Browser metadata was rejected"))
    }
  }
}

do {
  try run()
} catch {
  FileHandle.standardError.write(Data("browser host rejected the connection\n".utf8))
  exit(2)
}
