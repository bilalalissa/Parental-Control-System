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

  @Test("oversized hub history is compacted without losing a pairing invitation")
  func oversizedStatusCompaction() throws {
    let key = Data(repeating: 0x3D, count: 32)
    // Use whole-second precision because the authenticated wire codec intentionally stores
    // dates as milliseconds and Swift Foundation versions differ in sub-millisecond equality.
    let now = Date(timeIntervalSince1970: 1_788_000_000)
    let invitation = PairingInvitation(
      code: "482913",
      expiresAt: now.addingTimeInterval(300),
      host: "family-controller.local",
      port: 49_321,
      certificateFingerprint: String(repeating: "B", count: 64),
      controllerPublicKey: Data(repeating: 0x44, count: 32))
    let messages = (0..<500).map { index in
      HubChatMessage(
        deviceID: "child-1",
        sentAt: now.addingTimeInterval(Double(index)),
        sender: "Parent",
        text: "message-\(index)-" + String(repeating: "x", count: 1_980),
        state: .read,
        audience: .direct,
        isFromParent: true)
    }
    let oversized = LocalHubStatus(
      port: 49_321,
      certificateFingerprint: String(repeating: "B", count: 64),
      devices: [],
      invitation: invitation,
      chatMessages: messages,
      storage: HubStorageSummary(
        activityRecords: 0, chatMessages: messages.count, queuedEnvelopes: 0))
    #expect(try IPCCodec.encoder().encode(oversized).count > ProtocolCodec.maximumMessageBytes)

    let ready = DispatchSemaphore(value: 0)
    let port = IPCPortBox()
    let server = try AuthenticatedIPCServer(key: key) { _ in oversized }
    defer { server.cancel() }
    server.onReady = {
      port.set($0)
      ready.signal()
    }
    server.start()
    #expect(ready.wait(timeout: .now() + 5) == .success)

    let readyPort = try #require(port.value)
    let response = try AuthenticatedIPCClient.send(
      command: .createPairing, port: readyPort, key: key)
    let received = try #require(response)
    #expect(received.invitation == invitation)
    #expect(received.storage.chatMessages == messages.count)
    #expect(received.chatMessages.count < messages.count)
    #expect(received.chatMessages.last?.text == messages.last?.text)
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
