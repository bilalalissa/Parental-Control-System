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

public enum ChatDeliveryState: String, Codable, Sendable {
  case queued
  case sent
  case delivered
  case read
  case failed

  public func advanced(to candidate: ChatDeliveryState) -> ChatDeliveryState {
    if self == .read { return self }
    if candidate == .failed {
      return self == .queued || self == .sent ? .failed : self
    }
    if self == .failed {
      return candidate == .delivered || candidate == .read ? candidate : self
    }
    let progress: [ChatDeliveryState: Int] = [.queued: 0, .sent: 1, .delivered: 2, .read: 3]
    return (progress[candidate] ?? -1) >= (progress[self] ?? -1) ? candidate : self
  }
}

public enum ChatAudience: String, Codable, Sendable {
  case direct
  case familyGroup = "family-group"
  case announcement
}

public struct HubChatMessage: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let deviceID: String
  public let threadID: UUID
  public let sentAt: Date
  public let sender: String
  public let text: String
  public let editedAt: Date?
  public let deletedAt: Date?
  public let state: ChatDeliveryState
  public let audience: ChatAudience
  public let isFromParent: Bool

  public var isUnreadForParent: Bool { !isFromParent && state != .read }
  public var displayText: String { deletedAt == nil ? text : "Message deleted" }

  public init(
    id: UUID = UUID(), deviceID: String, threadID: UUID = UUID(), sentAt: Date = Date(),
    sender: String, text: String, state: ChatDeliveryState, audience: ChatAudience,
    isFromParent: Bool, editedAt: Date? = nil, deletedAt: Date? = nil
  ) {
    self.id = id
    self.deviceID = deviceID
    self.threadID = threadID
    self.sentAt = sentAt
    self.sender = String(sender.prefix(80))
    self.text = String(text.prefix(2_000))
    self.editedAt = editedAt
    self.deletedAt = deletedAt
    self.state = state
    self.audience = audience
    self.isFromParent = isFromParent
  }
}

public struct HubAppActivity: Codable, Equatable, Identifiable, Sendable {
  public var id: String { "\(deviceID)|\(bundleIdentifier)" }
  public let deviceID: String
  public let bundleIdentifier: String
  public let applicationName: String
  public let isForeground: Bool
  public let observedAt: Date

  public init(
    deviceID: String, bundleIdentifier: String, applicationName: String,
    isForeground: Bool, observedAt: Date = Date()
  ) {
    self.deviceID = deviceID
    self.bundleIdentifier = String(bundleIdentifier.prefix(200))
    self.applicationName = String(applicationName.prefix(120))
    self.isForeground = isForeground
    self.observedAt = observedAt
  }
}

public struct ActivityConfiguration: Codable, Equatable, Sendable {
  public let deviceID: String
  public let enabled: Bool
  public let retentionDays: Int

  public init(deviceID: String, enabled: Bool = true, retentionDays: Int = 7) {
    self.deviceID = deviceID
    self.enabled = enabled
    self.retentionDays = max(1, min(retentionDays, 30))
  }
}

public struct HubBrowserTab: Codable, Equatable, Identifiable, Sendable {
  public var id: String { "\(deviceID)|\(browser)|\(profileID)|\(origin)|\(title)" }
  public let deviceID: String
  public let browser: String
  public let profileID: String
  public let title: String
  public let origin: String
  public let isActive: Bool
  public let observedAt: Date

  public init(
    deviceID: String, browser: String, profileID: String, title: String, origin: String,
    isActive: Bool, observedAt: Date = Date()
  ) {
    self.deviceID = deviceID
    self.browser = String(browser.lowercased().prefix(40))
    self.profileID = String(profileID.prefix(80))
    self.title = String(title.prefix(300))
    self.origin = String(origin.prefix(500))
    self.isActive = isActive
    self.observedAt = observedAt
  }
}

public struct BrowserConfiguration: Codable, Equatable, Sendable {
  public let deviceID: String
  public let enabled: Bool
  public let retentionDays: Int

  public init(deviceID: String, enabled: Bool = false, retentionDays: Int = 7) {
    self.deviceID = deviceID
    self.enabled = enabled
    self.retentionDays = max(1, min(retentionDays, 30))
  }
}

public enum MoreTimeRequestState: String, Codable, Sendable {
  case pending
  case acknowledged
}

public struct MoreTimeRequestRecord: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let deviceID: String
  public let requestedMinutes: Int
  public let note: String
  public let createdAt: Date
  public let state: MoreTimeRequestState

  public init(
    id: UUID = UUID(), deviceID: String, requestedMinutes: Int, note: String,
    createdAt: Date = Date(), state: MoreTimeRequestState = .pending
  ) {
    self.id = id
    self.deviceID = deviceID
    self.requestedMinutes = max(5, min(requestedMinutes, 240))
    self.note = String(note.prefix(500))
    self.createdAt = createdAt
    self.state = state
  }
}

public struct HubStorageSummary: Codable, Equatable, Sendable {
  public let activityRecords: Int
  public let browserTabRecords: Int
  public let chatMessages: Int
  public let queuedEnvelopes: Int

  public init(
    activityRecords: Int, browserTabRecords: Int = 0, chatMessages: Int,
    queuedEnvelopes: Int
  ) {
    self.activityRecords = activityRecords
    self.browserTabRecords = browserTabRecords
    self.chatMessages = chatMessages
    self.queuedEnvelopes = queuedEnvelopes
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
