import SwiftUI

struct DashboardView: View {
  let store: ControllerStore
  let openDevice: (ManagedDevice.ID) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        ScreenHeader(
          title: "Family overview",
          subtitle: "A local-only Stage 01 preview using synthetic devices."
        )

        HStack(spacing: 14) {
          MetricCard(
            title: "Online",
            value: "\(store.onlineDeviceCount)",
            subtitle: "Authenticated presence in later stages",
            systemImage: "wifi",
            tint: .green
          )
          MetricCard(
            title: "Offline",
            value: "\(store.offlineDeviceCount)",
            subtitle: "Never inferred as powered off",
            systemImage: "wifi.slash",
            tint: .secondary
          )
          MetricCard(
            title: "Approximate",
            value: "\(store.approximateDeviceCount)",
            subtitle: "Truthful iPadOS presence",
            systemImage: "ipad",
            tint: .blue
          )
        }

        SectionCard {
          VStack(alignment: .leading, spacing: 12) {
            Label("Privacy-first preview", systemImage: "hand.raised.fill")
              .font(.headline)
            Text(
              "No network service is running and no real device information is collected. Device names, events, and messages on this screen are synthetic fixtures stored in local SQLite."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("Devices")
            .font(.title2.weight(.semibold))
          ForEach(store.devices) { device in
            Button {
              openDevice(device.id)
            } label: {
              DashboardDeviceRow(device: device)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(device.name) details")
          }
        }
      }
      .padding(24)
    }
    .background(.background.secondary)
    .navigationTitle("Dashboard")
    .accessibilityIdentifier(AccessibilityID.dashboard.rawValue)
  }
}

private struct DashboardDeviceRow: View {
  let device: ManagedDevice

  var body: some View {
    SectionCard {
      HStack(spacing: 14) {
        Image(systemName: device.platform.systemImage)
          .font(.title2)
          .foregroundStyle(.tint)
          .frame(width: 36)
        VStack(alignment: .leading, spacing: 3) {
          Text(device.name)
            .font(.headline)
          Text("\(device.platform.displayName) · \(device.currentAllowance)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        StatusBadge(state: device.connectionState)
        Image(systemName: "chevron.right")
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
  }
}
