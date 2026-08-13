import Foundation

enum AuditSeverity: String, Codable, Sendable {
  case information
  case notice
  case warning
}

struct AuditEvent: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let timestamp: Date
  let title: String
  let detail: String
  let severity: AuditSeverity
}

enum MessageDeliveryState: String, Codable, Sendable {
  case queued
  case delivered
  case read
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let deviceID: UUID
  let sentAt: Date
  let sender: String
  let text: String
  let state: MessageDeliveryState
  let isFromParent: Bool
}

enum ChatAudienceMode: String, CaseIterable, Identifiable, Sendable {
  case direct
  case familyGroup
  case announcement

  var id: Self { self }

  var title: String {
    switch self {
    case .direct: "Direct"
    case .familyGroup: "Family group"
    case .announcement: "Announcement"
    }
  }

  var systemImage: String {
    switch self {
    case .direct: "person.crop.circle"
    case .familyGroup: "person.3.fill"
    case .announcement: "megaphone.fill"
    }
  }

  var composerPlaceholder: String {
    switch self {
    case .direct: "Write a direct-message preview"
    case .familyGroup: "Write a family group-message preview"
    case .announcement: "Write an announcement for every child device"
    }
  }

  func recipients(from devices: [ManagedDevice], selectedDeviceID: ManagedDevice.ID?)
    -> [ManagedDevice]
  {
    switch self {
    case .direct:
      return devices.filter { $0.id == selectedDeviceID }
    case .familyGroup, .announcement:
      return devices
    }
  }
}

struct LocalChatPreview: Identifiable, Equatable, Sendable {
  let id: UUID
  let audience: ChatAudienceMode
  let sentAt: Date
  let text: String
  let recipientIDs: [UUID]
  let recipientNames: [String]
}

struct StorageSnapshot: Equatable, Sendable {
  let databaseBytes: Int64
  let deviceCount: Int
  let auditEventCount: Int
  let chatMessageCount: Int
}
