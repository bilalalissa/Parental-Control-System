import CryptoKit
import Foundation
import Testing

@testable import HubCore

@Suite("Stage 02 protocol security")
struct ProtocolSecurityTests {
  @Test("signed envelopes round-trip and verify")
  func roundTrip() throws {
    let identity = try Ed25519Identity(keyID: "mock-key")
    let envelope = try identity.sign(
      deviceID: "mock-device",
      sequence: 1,
      type: .snapshotResponse,
      payload: ["status": .string("online")]
    )
    let encoded = try ProtocolCodec.encode(envelope)
    let object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["sentAt"] is String)
    #expect(object["expiresAt"] is String)
    let decoded = try ProtocolCodec.decode(encoded)
    try ReplayProtector().verify(decoded, publicKey: identity.publicKeyData)
  }

  @Test("message ID and sequence replays fail closed")
  func replayRejection() throws {
    let identity = try Ed25519Identity(keyID: "mock-key")
    let protector = ReplayProtector()
    let first = try identity.sign(
      deviceID: "mock-device", sequence: 1, type: .snapshotResponse, payload: [:])
    try protector.verify(first, publicKey: identity.publicKeyData)
    #expect(throws: ProtocolSecurityError.replayedMessage) {
      try protector.verify(first, publicKey: identity.publicKeyData)
    }

    let reusedSequence = try identity.sign(
      deviceID: "mock-device", sequence: 1, type: .snapshotResponse, payload: [:])
    #expect(throws: ProtocolSecurityError.replayedSequence) {
      try protector.verify(reusedSequence, publicKey: identity.publicKeyData)
    }
  }

  @Test("expired and future messages fail closed")
  func timeRejection() throws {
    let identity = try Ed25519Identity(keyID: "mock-key")
    let now = Date()
    let expired = try identity.sign(
      deviceID: "mock-device",
      sequence: 1,
      type: .snapshotResponse,
      payload: [:],
      now: now.addingTimeInterval(-300),
      lifetime: 10
    )
    #expect(throws: ProtocolSecurityError.timestampOutsideWindow) {
      try ReplayProtector().verify(expired, publicKey: identity.publicKeyData, now: now)
    }

    let future = try identity.sign(
      deviceID: "mock-device",
      sequence: 2,
      type: .snapshotResponse,
      payload: [:],
      now: now.addingTimeInterval(300)
    )
    #expect(throws: ProtocolSecurityError.timestampOutsideWindow) {
      try ReplayProtector().verify(future, publicKey: identity.publicKeyData, now: now)
    }
  }

  @Test("tampering invalidates the Ed25519 signature")
  func tamperRejection() throws {
    let identity = try Ed25519Identity(keyID: "mock-key")
    let original = try identity.sign(
      deviceID: "mock-device",
      sequence: 1,
      type: .snapshotResponse,
      payload: ["status": .string("online")]
    )
    let tampered = ProtocolEnvelope(
      id: original.id,
      deviceID: original.deviceID,
      sentAt: original.sentAt,
      expiresAt: original.expiresAt,
      sequence: original.sequence,
      type: original.type,
      payload: ["status": .string("changed")],
      auth: original.auth
    )
    #expect(throws: ProtocolSecurityError.invalidSignature) {
      try ReplayProtector().verify(tampered, publicKey: identity.publicKeyData)
    }
  }
}
