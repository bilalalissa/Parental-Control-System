import Foundation
import Testing

@testable import HubCore

@Suite("Authenticated UI-hub IPC", .serialized)
struct AuthenticatedIPCTests {
  @Test("HMAC requests reject tampering, expiry, and replay")
  func authenticationFailures() throws {
    let authenticator = IPCAuthenticator(key: Data(repeating: 7, count: 32))
    let request = try authenticator.request(command: .status)
    try authenticator.verify(request)
    #expect(throws: AuthenticatedIPCError.replay) { try authenticator.verify(request) }

    let expired = try authenticator.request(
      command: .status, now: Date().addingTimeInterval(-60))
    #expect(throws: AuthenticatedIPCError.expired) { try authenticator.verify(expired) }

    let tampered = IPCRequest(
      id: request.id,
      sentAt: Date(),
      nonce: UUID().uuidString,
      command: .shutdown,
      authentication: request.authentication)
    #expect(throws: AuthenticatedIPCError.invalidAuthentication) {
      try authenticator.verify(tampered)
    }
  }

  @Test("controller and hub exchange an authenticated loopback status")
  func loopbackIPC() throws {
    let key = Data(repeating: 0x2C, count: 32)
    let expected = LocalHubStatus(
      port: 4567,
      certificateFingerprint: String(repeating: "A", count: 64),
      devices: [],
      invitation: nil)
    let ready = DispatchSemaphore(value: 0)
    let port = IPCPortBox()
    let server = try AuthenticatedIPCServer(key: key) { _ in expected }
    defer { server.cancel() }
    server.onReady = {
      port.set($0)
      ready.signal()
    }
    server.start()
    #expect(ready.wait(timeout: .now() + 5) == .success)
    let actual = try AuthenticatedIPCClient.send(
      command: .status, port: try #require(port.value), key: key)
    #expect(actual == expected)
  }
}

private final class IPCPortBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: UInt16?
  var value: UInt16? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
  func set(_ value: UInt16) {
    lock.lock()
    stored = value
    lock.unlock()
  }
}
