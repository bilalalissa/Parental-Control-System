import Foundation

enum DevicePlatform: String, Codable, CaseIterable, Sendable {
  case macOS
  case windows
  case iPadOS

  var displayName: String {
    switch self {
    case .macOS: "macOS"
    case .windows: "Windows"
    case .iPadOS: "iPadOS"
    }
  }

  var systemImage: String {
    switch self {
    case .macOS: "laptopcomputer"
    case .windows: "desktopcomputer"
    case .iPadOS: "ipad"
    }
  }
}

enum DeviceConnectionState: String, Codable, Sendable {
  case online
  case offline
  case approximate

  var title: String {
    switch self {
    case .online: "Online"
    case .offline: "Offline"
    case .approximate: "Approximate presence"
    }
  }
}

enum DeviceCapability: String, Codable, CaseIterable, Sendable {
  case presence
  case approximatePresence
  case sessionState
  case appActivity
  case browserTabs
  case chat
  case schedule
  case lock
  case logoff
  case restart
  case shutdown

  var title: String {
    switch self {
    case .presence: "Presence"
    case .approximatePresence: "Approximate presence"
    case .sessionState: "Session state"
    case .appActivity: "App activity"
    case .browserTabs: "Browser tabs"
    case .chat: "Text chat"
    case .schedule: "Schedule"
    case .lock: "Lock"
    case .logoff: "Log out"
    case .restart: "Restart"
    case .shutdown: "Shut down"
    }
  }
}

struct ManagedDevice: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let name: String
  let platform: DevicePlatform
  let model: String
  let operatingSystem: String
  let architecture: String
  let connectionState: DeviceConnectionState
  let lastSeen: Date
  let currentAllowance: String
  let capabilities: Set<DeviceCapability>
  let limitations: [String]

  var isOnline: Bool { connectionState == .online }
}
