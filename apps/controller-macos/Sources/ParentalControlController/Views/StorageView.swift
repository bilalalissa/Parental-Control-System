import SwiftUI

struct StorageView: View {
  let store: ControllerStore
  @AppStorage("retention.appActivityDays") private var appActivityDays = 7
  @AppStorage("retention.chatDays") private var chatDays = 30
  @AppStorage("retention.auditDays") private var auditDays = 30

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        ScreenHeader(
          title: "Storage & retention",
          subtitle: "Local-only records with visible, bounded retention targets."
        )

        HStack(spacing: 14) {
          MetricCard(
            title: "Database",
            value: ByteCountFormatter.string(
              fromByteCount: store.storageSnapshot.databaseBytes, countStyle: .file),
            subtitle: "SQLite on this Mac",
            systemImage: "cylinder",
            tint: .blue
          )
          MetricCard(
            title: "Paired devices",
            value: "\(store.pairedDevices.count)",
            subtitle: "Authenticated local records",
            systemImage: "laptopcomputer.and.iphone",
            tint: .purple
          )
          MetricCard(
            title: "Audit events",
            value: "\(store.storageSnapshot.auditEventCount)",
            subtitle: "Bounded metadata only",
            systemImage: "checkmark.shield",
            tint: .green
          )
        }

        SectionCard {
          VStack(alignment: .leading, spacing: 16) {
            Text("Retention preferences")
              .font(.headline)
            RetentionStepper(
              title: "Application and tab metadata", days: $appActivityDays, range: 1...30)
            RetentionStepper(title: "Family chat", days: $chatDays, range: 1...90)
            RetentionStepper(title: "Connection and audit events", days: $auditDays, range: 1...90)
            Text(
              "These preferences shape bounded local pruning. Per-device application and browser retention is controlled from Devices."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }

        SectionCard {
          VStack(alignment: .leading, spacing: 10) {
            Label("Data stays on this Mac", systemImage: "externaldrive.badge.checkmark")
              .font(.headline)
            Text(
              "The controller has no hosted account, relay, telemetry endpoint, or public-IP lookup. Pairing secrets remain in macOS Keychain."
            )
            .foregroundStyle(.secondary)
          }
        }
      }
      .padding(24)
    }
    .navigationTitle("Storage")
    .onAppear { store.refreshStorageSnapshot() }
    .accessibilityIdentifier(AccessibilityID.storage.rawValue)
  }
}

private struct RetentionStepper: View {
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
