import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class StartupManager {
  var statusMessage: String?

  var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  var statusDescription: String {
    switch SMAppService.mainApp.status {
    case .enabled:
      "Enabled"
    case .requiresApproval:
      "Requires approval in System Settings"
    case .notRegistered:
      "Disabled"
    case .notFound:
      "Unavailable for this app copy"
    @unknown default:
      "Unknown"
    }
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
        statusMessage =
          SMAppService.mainApp.status == .requiresApproval
          ? "Approve Parental Control in System Settings → General → Login Items."
          : "Parental Control will open when this adult account logs in."
      } else {
        try SMAppService.mainApp.unregister()
        statusMessage = "Startup at login is disabled."
      }
    } catch {
      statusMessage = "Startup setting was not changed: \(error.localizedDescription)"
    }
  }
}
