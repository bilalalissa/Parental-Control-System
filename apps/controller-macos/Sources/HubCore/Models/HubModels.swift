import Foundation

public enum HubDeviceState: String, Codable, Sendable {
  case online
  case offline
  case revoked
}

public struct HubDeviceRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let platform: String
  public let keyID: String
  public let publicKey: Data
  public let capabilities: [String]
  public let pairedAt: Date
  public let lastSeen: Date
  public let lastSequence: UInt64
  public let snapshotVersion: UInt64
  public let isRevoked: Bool

  public init(
    id: String,
    name: String,
    platform: String,
    keyID: String,
    publicKey: Data,
    capabilities: [String],
    pairedAt: Date,
    lastSeen: Date,
    lastSequence: UInt64 = 0,
    snapshotVersion: UInt64 = 0,
    isRevoked: Bool = false
  ) {
    self.id = id
    self.name = name
    self.platform = platform
    self.keyID = keyID
    self.publicKey = publicKey
    self.capabilities = capabilities
    self.pairedAt = pairedAt
    self.lastSeen = lastSeen
    self.lastSequence = lastSequence
    self.snapshotVersion = snapshotVersion
    self.isRevoked = isRevoked
  }

  public func state(now: Date = Date(), offlineAfter: TimeInterval = 75) -> HubDeviceState {
    if isRevoked { return .revoked }
    return now.timeIntervalSince(lastSeen) <= offlineAfter ? .online : .offline
  }
}

public struct HubAuditRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let timestamp: Date
  public let event: String
  public let deviceID: String?
  public let detail: String

  public init(
    id: UUID = UUID(), timestamp: Date = Date(), event: String, deviceID: String?, detail: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.event = event
    self.deviceID = deviceID
    self.detail = detail
  }
}

public struct QueuedEnvelope: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let deviceID: String
  public let createdAt: Date
  public let expiresAt: Date
  public let envelope: Data

  public init(
    id: UUID = UUID(),
    deviceID: String,
    createdAt: Date = Date(),
    expiresAt: Date,
    envelope: Data
  ) {
    self.id = id
    self.deviceID = deviceID
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.envelope = envelope
  }
}

public struct ReceiptRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let deviceID: String
  public let originalMessageID: UUID
  public let state: String
  public let timestamp: Date

  public init(
    id: UUID = UUID(),
    deviceID: String,
    originalMessageID: UUID,
    state: String,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.deviceID = deviceID
    self.originalMessageID = originalMessageID
    self.state = state
    self.timestamp = timestamp
  }
}

public struct PairingInvitation: Codable, Equatable, Sendable {
  public let code: String
  public let expiresAt: Date
  public let host: String
  public let port: UInt16
  public let certificateFingerprint: String
  public let controllerPublicKey: Data

  public init(
    code: String,
    expiresAt: Date,
    host: String,
    port: UInt16,
    certificateFingerprint: String,
    controllerPublicKey: Data = Data()
  ) {
    self.code = code
    self.expiresAt = expiresAt
    self.host = host
    self.port = port
    self.certificateFingerprint = certificateFingerprint
    self.controllerPublicKey = controllerPublicKey
  }
}
