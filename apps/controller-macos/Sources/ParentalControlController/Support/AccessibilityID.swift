import Foundation

enum AccessibilityID: String, CaseIterable {
  case mainWindow = "controller.main-window"
  case sidebar = "controller.sidebar"
  case dashboard = "dashboard.screen"
  case devices = "devices.screen"
  case deviceList = "devices.list"
  case deviceDetail = "devices.detail"
  case pairedDeviceDisclosure = "devices.paired-disclosure"
  case activitySharingToggle = "devices.activity-sharing"
  case browserSharingToggle = "devices.browser-sharing"
  case schedule = "schedule.screen"
  case scheduleQuota = "schedule.daily-quota"
  case scheduleSave = "schedule.save"
  case chat = "chat.screen"
  case chatAudience = "chat.audience"
  case chatComposer = "chat.composer"
  case chatPreviewButton = "chat.add-local-preview"
  case audit = "audit.screen"
  case storage = "storage.screen"
  case settings = "settings.screen"
  case startupToggle = "settings.start-at-login"
}
