import Foundation

enum AppSection: String, CaseIterable, Identifiable {
  case dashboard
  case devices
  case schedule
  case chat
  case audit
  case storage

  var id: String { rawValue }

  var title: String {
    switch self {
    case .dashboard: "Dashboard"
    case .devices: "Devices"
    case .schedule: "Schedule"
    case .chat: "Chat"
    case .audit: "Audit"
    case .storage: "Storage"
    }
  }

  var systemImage: String {
    switch self {
    case .dashboard: "rectangle.3.group"
    case .devices: "laptopcomputer.and.iphone"
    case .schedule: "calendar.badge.clock"
    case .chat: "bubble.left.and.bubble.right"
    case .audit: "checkmark.shield"
    case .storage: "externaldrive"
    }
  }
}
