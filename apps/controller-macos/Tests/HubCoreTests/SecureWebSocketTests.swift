import Foundation
import Network
import Testing

@testable import HubCore

@Suite("TLS 1.3 WebSocket transport", .serialized)
struct SecureWebSocketTests {
  @Test("a certificate-pinned client exchanges a bounded WebSocket message")
  func loopbackRoundTrip() throws {
    let identityLabel = "com.bilalalissa.ParentalControlController.test.\(UUID().uuidString)"
    let identity = try TLSCertificateIdentity.loadOrCreate(label: identityLabel)
    defer { TLSCertificateIdentity.delete(label: identityLabel) }
    let reloadedIdentity = try TLSCertificateIdentity.loadOrCreate(label: identityLabel)
    #expect(reloadedIdentity.fingerprint == identity.fingerprint)
    let portBox = LockedBox<UInt16>()
    let receivedBox = LockedBox<Data>()
    let serverReady = DispatchSemaphore(value: 0)
    let clientReady = DispatchSemaphore(value: 0)
    let messageReceived = DispatchSemaphore(value: 0)

    let server = try SecureWebSocketServer(
      identity: identity,
      advertiseBonjour: false
    )
    defer { server.cancel() }
    server.onReady = { port in
      portBox.set(port)
      serverReady.signal()
    }
    server.onPeer = { peer in
      peer.onMessage = { data in
        receivedBox.set(data)
        messageReceived.signal()
      }
    }
    server.start()

    #expect(serverReady.wait(timeout: .now() + 5) == .success)
    let port = try #require(portBox.value)
    let client = try SecureWebSocketClient.connect(
      host: "127.0.0.1",
      port: port,
      certificateFingerprint: identity.fingerprint
    )
    defer { client.cancel() }
    client.onState = { state in
      if case .ready = state { clientReady.signal() }
    }
    client.start()
    #expect(clientReady.wait(timeout: .now() + 5) == .success)
    client.send(Data("authenticated websocket".utf8))
    #expect(messageReceived.wait(timeout: .now() + 5) == .success)
    #expect(receivedBox.value == Data("authenticated websocket".utf8))
  }
}

private final class LockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value?

  var value: Value? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func set(_ value: Value) {
    lock.lock()
    stored = value
    lock.unlock()
  }
}
