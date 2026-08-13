import Foundation

enum AccessibilityID: String, CaseIterable {
  case mainWindow = "controller.main-window"
  case sidebar = "controller.sidebar"
  case dashboard = "dashboard.screen"
  case devices = "devices.screen"
  case deviceList = "devices.list"
  case deviceDetail = "devices.detail"
  case schedule = "schedule.screen"
  case scheduleQuota = "schedule.daily-quota"
  case scheduleSave = "schedule.save"
  case chat = "chat.screen"
  case chatComposer = "chat.composer"
  case audit = "audit.screen"
  case storage = "storage.screen"
  case settings = "settings.screen"
  case startupToggle = "settings.start-at-login"
}
