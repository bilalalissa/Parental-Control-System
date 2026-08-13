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

struct StorageSnapshot: Equatable, Sendable {
  let databaseBytes: Int64
  let deviceCount: Int
  let auditEventCount: Int
  let chatMessageCount: Int
}
