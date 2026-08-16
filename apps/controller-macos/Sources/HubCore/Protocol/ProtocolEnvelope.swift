import CryptoKit
import Foundation

public enum ProtocolMessageType: String, Codable, CaseIterable, Sendable {
  case capabilityAnnounce = "capability.announce"
  case snapshotRequest = "snapshot.request"
  case snapshotResponse = "snapshot.response"
  case activityUpdate = "activity.update"
  case activityConfiguration = "activity.configuration"
  case browserUpdate = "browser.update"
  case browserConfiguration = "browser.configuration"
  case chatMessage = "chat.message"
  case chatMutation = "chat.mutation"
  case requestMoreTime = "time.request"
  case receipt
}

public struct ProtocolAuthentication: Codable, Equatable, Sendable {
  public let algorithm: String
  public let keyID: String
  public let signature: String

  public init(algorithm: String = "Ed25519", keyID: String, signature: String) {
    self.algorithm = algorithm
    self.keyID = keyID
    self.signature = signature
  }

  enum CodingKeys: String, CodingKey {
    case algorithm
    case keyID = "keyId"
    case signature
  }
}

public struct ProtocolEnvelope: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let protocolVersion: String
  public let deviceID: String
  public let sentAt: Date
  public let expiresAt: Date?
  public let sequence: UInt64
  public let type: ProtocolMessageType
  public let payload: [String: JSONValue]
  public let auth: ProtocolAuthentication

  public init(
    id: UUID = UUID(),
    protocolVersion: String = "1.0",
    deviceID: String,
    sentAt: Date,
    expiresAt: Date?,
    sequence: UInt64,
    type: ProtocolMessageType,
    payload: [String: JSONValue],
    auth: ProtocolAuthentication
  ) {
    self.id = id
    self.protocolVersion = protocolVersion
    self.deviceID = deviceID
    self.sentAt = sentAt
    self.expiresAt = expiresAt
    self.sequence = sequence
    self.type = type
    self.payload = payload
    self.auth = auth
  }

  enum CodingKeys: String, CodingKey {
    case id
    case protocolVersion
    case deviceID = "deviceId"
    case sentAt
    case expiresAt
    case sequence
    case type
    case payload
    case auth
  }
}

private struct SigningEnvelope: Codable {
  let id: UUID
  let protocolVersion: String
  let deviceID: String
  let sentAt: Date
  let expiresAt: Date?
  let sequence: UInt64
  let type: ProtocolMessageType
  let payload: [String: JSONValue]
  let algorithm: String
  let keyID: String

  enum CodingKeys: String, CodingKey {
    case id
    case protocolVersion
    case deviceID = "deviceId"
    case sentAt
    case expiresAt
    case sequence
    case type
    case payload
    case algorithm
    case keyID = "keyId"
  }
}

public enum ProtocolCodec {
  public static let maximumMessageBytes = 64 * 1024

  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  public static func signingData(for envelope: ProtocolEnvelope) throws -> Data {
    try encoder().encode(
      SigningEnvelope(
        id: envelope.id,
        protocolVersion: envelope.protocolVersion,
        deviceID: envelope.deviceID,
        sentAt: envelope.sentAt,
        expiresAt: envelope.expiresAt,
        sequence: envelope.sequence,
        type: envelope.type,
        payload: envelope.payload,
        algorithm: envelope.auth.algorithm,
        keyID: envelope.auth.keyID
      ))
  }

  public static func encode(_ envelope: ProtocolEnvelope) throws -> Data {
    let data = try encoder().encode(envelope)
    guard data.count <= maximumMessageBytes else { throw ProtocolSecurityError.messageTooLarge }
    return data
  }

  public static func decode(_ data: Data) throws -> ProtocolEnvelope {
    guard data.count <= maximumMessageBytes else { throw ProtocolSecurityError.messageTooLarge }
    return try decoder().decode(ProtocolEnvelope.self, from: data)
  }
}

public struct Ed25519Identity: Sendable {
  public let keyID: String
  private let privateKey: Curve25519.Signing.PrivateKey

  public init(keyID: String, rawPrivateKey: Data? = nil) throws {
    self.keyID = keyID
    if let rawPrivateKey {
      privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivateKey)
    } else {
      privateKey = Curve25519.Signing.PrivateKey()
    }
  }

  public var publicKeyData: Data { privateKey.publicKey.rawRepresentation }

  public func sign(
    deviceID: String,
    sequence: UInt64,
    type: ProtocolMessageType,
    payload: [String: JSONValue],
    now: Date = Date(),
    lifetime: TimeInterval = 120,
    id: UUID = UUID()
  ) throws -> ProtocolEnvelope {
    let unsigned = ProtocolEnvelope(
      id: id,
      deviceID: deviceID,
      sentAt: now,
      expiresAt: now.addingTimeInterval(lifetime),
      sequence: sequence,
      type: type,
      payload: payload,
      auth: ProtocolAuthentication(keyID: keyID, signature: "")
    )
    let signature = try privateKey.signature(for: ProtocolCodec.signingData(for: unsigned))
    return ProtocolEnvelope(
      id: unsigned.id,
      deviceID: unsigned.deviceID,
      sentAt: unsigned.sentAt,
      expiresAt: unsigned.expiresAt,
      sequence: unsigned.sequence,
      type: unsigned.type,
      payload: unsigned.payload,
      auth: ProtocolAuthentication(keyID: keyID, signature: signature.base64EncodedString())
    )
  }
}

public enum ProtocolSecurityError: Error, Equatable, CustomStringConvertible {
  case unsupportedVersion
  case unsupportedAlgorithm
  case invalidSignature
  case invalidKey
  case expired
  case timestampOutsideWindow
  case replayedMessage
  case replayedSequence
  case messageTooLarge
  case tooManyPayloadFields

  public var description: String {
    switch self {
    case .unsupportedVersion: "Unsupported protocol version"
    case .unsupportedAlgorithm: "Unsupported authentication algorithm"
    case .invalidSignature: "Invalid message signature"
    case .invalidKey: "Invalid signing key"
    case .expired: "Message expired"
    case .timestampOutsideWindow: "Message timestamp is outside the accepted window"
    case .replayedMessage: "Message ID was replayed"
    case .replayedSequence: "Message sequence was replayed"
    case .messageTooLarge: "Message exceeds the 64 KiB limit"
    case .tooManyPayloadFields: "Payload exceeds the 64-field limit"
    }
  }
}

public final class ReplayProtector: @unchecked Sendable {
  public static let maximumRememberedMessageIDs = 1_024

  private let lock = NSLock()
  private var messageOrder: [UUID] = []
  private var messageIDs: Set<UUID> = []
  private var sequences: [String: UInt64] = [:]
  private let acceptedClockSkew: TimeInterval

  public init(acceptedClockSkew: TimeInterval = 120) {
    self.acceptedClockSkew = acceptedClockSkew
  }

  public func seed(deviceID: String, sequence: UInt64) {
    lock.lock()
    sequences[deviceID] = max(sequences[deviceID] ?? 0, sequence)
    lock.unlock()
  }

  public func verify(
    _ envelope: ProtocolEnvelope,
    publicKey: Data,
    now: Date = Date()
  ) throws {
    guard envelope.protocolVersion == "1.0" else { throw ProtocolSecurityError.unsupportedVersion }
    guard envelope.auth.algorithm == "Ed25519" else {
      throw ProtocolSecurityError.unsupportedAlgorithm
    }
    guard envelope.payload.count <= 64 else { throw ProtocolSecurityError.tooManyPayloadFields }
    guard envelope.sentAt.timeIntervalSince(now) <= acceptedClockSkew else {
      throw ProtocolSecurityError.timestampOutsideWindow
    }
    if let expiresAt = envelope.expiresAt {
      if expiresAt < now { throw ProtocolSecurityError.expired }
    } else if now.timeIntervalSince(envelope.sentAt) > acceptedClockSkew {
      throw ProtocolSecurityError.timestampOutsideWindow
    }
    let signingData = try ProtocolCodec.signingData(for: envelope)
    guard
      let signature = Data(base64Encoded: envelope.auth.signature),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      key.isValidSignature(signature, for: signingData)
    else { throw ProtocolSecurityError.invalidSignature }

    lock.lock()
    defer { lock.unlock() }
    guard !messageIDs.contains(envelope.id) else { throw ProtocolSecurityError.replayedMessage }
    guard envelope.sequence > (sequences[envelope.deviceID] ?? 0) else {
      throw ProtocolSecurityError.replayedSequence
    }
    messageIDs.insert(envelope.id)
    messageOrder.append(envelope.id)
    sequences[envelope.deviceID] = envelope.sequence
    if messageOrder.count > Self.maximumRememberedMessageIDs {
      let removalCount = messageOrder.count - Self.maximumRememberedMessageIDs
      let removed = messageOrder.prefix(removalCount)
      messageIDs.subtract(removed)
      messageOrder.removeFirst(removalCount)
    }
  }
}
