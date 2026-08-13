import AppKit
import SwiftUI

@main
struct ParentalControlControllerApp: App {
  @NSApplicationDelegateAdaptor(ControllerAppDelegate.self) private var appDelegate
  @State private var store = ControllerStore.live()

  var body: some Scene {
    WindowGroup("Parental Control", id: "controller") {
      ControllerRootView(store: store)
        .frame(minWidth: 980, minHeight: 650)
        .accessibilityIdentifier(AccessibilityID.mainWindow.rawValue)
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
      ControllerSettingsView()
    }
  }
}

final class ControllerAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

extension Notification.Name {
  static let showControllerSection = Notification.Name("showControllerSection")
}
