import DesignSystem
import SwiftUI

struct ControllerSettingsView: View {
  @State private var startupManager = StartupManager()
  @AppStorage("settings.confirmHighImpactActions") private var confirmHighImpactActions = true
  @AppStorage("settings.showCapabilityLimitations") private var showCapabilityLimitations = true
  @AppStorage("retention.appActivityDays") private var appActivityDays = 7
  @AppStorage("retention.chatDays") private var chatDays = 30
  @AppStorage("retention.auditDays") private var auditDays = 30

  var body: some View {
    TabView {
      Form {
        Section("Startup") {
          Toggle(
            "Open Parental Control at login",
            isOn: Binding(
              get: { startupManager.isEnabled },
              set: { startupManager.setEnabled($0) }
            )
          )
          .accessibilityIdentifier(AccessibilityID.startupToggle.rawValue)
          LabeledContent("Status", value: startupManager.statusDescription)
          if let message = startupManager.statusMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Section("Appearance") {
          ControlAppearancePicker()
          Text("System follows the Mac appearance; Light and Dark remain fixed for this app.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Safety") {
          Toggle("Confirm high-impact actions", isOn: $confirmHighImpactActions)
            .disabled(true)
          Toggle("Always show platform limitations", isOn: $showCapabilityLimitations)
          Text(
            "High-impact confirmation cannot be disabled until authenticated actions exist in a later stage."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .tabItem { Label("General", systemImage: "gearshape") }

      Form {
        Section("Local retention") {
          RetentionSettingRow(title: "App/tab metadata", days: $appActivityDays, range: 1...30)
          RetentionSettingRow(title: "Chat", days: $chatDays, range: 1...90)
          RetentionSettingRow(title: "Audit", days: $auditDays, range: 1...90)
        }
        Section("Privacy") {
          Text(
            "This Stage 01 shell uses synthetic local data. It has no endpoint connection, cloud account, relay, analytics, or telemetry service."
          )
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .formStyle(.grouped)
      .tabItem { Label("Privacy", systemImage: "hand.raised") }
    }
    .frame(width: 540, height: 360)
    .scenePadding()
    .accessibilityIdentifier(AccessibilityID.settings.rawValue)
  }
}

private struct RetentionSettingRow: View {
  let title: String
  @Binding var days: Int
  let range: ClosedRange<Int>

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Stepper("\(days) days", value: $days, in: range)
    }
  }
}
