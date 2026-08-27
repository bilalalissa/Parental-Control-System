import AppKit
import DesignSystem
import SwiftUI
import UserNotifications

@main
struct ParentalControlControllerApp: App {
  @NSApplicationDelegateAdaptor(ControllerAppDelegate.self) private var appDelegate
  @State private var store = ControllerStore.live()

  var body: some Scene {
    WindowGroup("Parental Control", id: "controller") {
      ControllerRootView(store: store)
        .frame(minWidth: 980, minHeight: 650)
        .accessibilityIdentifier(AccessibilityID.mainWindow.rawValue)
        .controlTheme()
    }
    .defaultSize(width: 1180, height: 760)
    .commands {
      CommandMenu("Controller") {
        Button("Refresh Storage Summary") {
          store.refreshStorageSnapshot()
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Divider()

        Button("Show Dashboard") {
          NotificationCenter.default.post(
            name: .showControllerSection, object: AppSection.dashboard)
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("Show Devices") {
          NotificationCenter.default.post(name: .showControllerSection, object: AppSection.devices)
        }
        .keyboardShortcut("2", modifiers: .command)

        Button("Show Schedule") {
          NotificationCenter.default.post(name: .showControllerSection, object: AppSection.schedule)
        }
        .keyboardShortcut("3", modifiers: .command)
      }
    }

    Settings {
      ControllerSettingsView().controlTheme()
    }
  }
}

final class ControllerAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate
{
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    UNUserNotificationCenter.current().delegate = self
    Task {
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound,
      ])
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}

extension Notification.Name {
  static let showControllerSection = Notification.Name("showControllerSection")
}
