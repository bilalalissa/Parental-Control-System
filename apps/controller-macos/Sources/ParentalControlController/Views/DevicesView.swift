import SwiftUI

struct DevicesView: View {
  let store: ControllerStore

  var body: some View {
    HSplitView {
      List(selection: Bindable(store).selectedDeviceID) {
        ForEach(store.devices) { device in
          DeviceSidebarRow(device: device)
            .tag(device.id)
        }
      }
      .listStyle(.inset)
      .frame(minWidth: 230, idealWidth: 270, maxWidth: 330)
      .accessibilityIdentifier(AccessibilityID.deviceList.rawValue)

      Group {
        if let device = store.selectedDevice {
          DeviceDetailView(device: device)
        } else {
          ContentUnavailableView("Select a device", systemImage: "laptopcomputer.and.iphone")
        }
      }
      .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle("Devices")
    .accessibilityIdentifier(AccessibilityID.devices.rawValue)
  }
}

private struct DeviceSidebarRow: View {
  let device: ManagedDevice

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: device.platform.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(device.name)
          .lineLimit(1)
        Text(device.connectionState.title)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 3)
  }
}

private struct DeviceDetailView: View {
  let device: ManagedDevice

  private let columns = [GridItem(.adaptive(minimum: 150), spacing: 9)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 16) {
          Image(systemName: device.platform.systemImage)
            .font(.system(size: 34))
            .foregroundStyle(.tint)
            .frame(width: 58, height: 58)
            .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
          VStack(alignment: .leading, spacing: 5) {
            Text(device.name)
              .font(.largeTitle.weight(.semibold))
            Text("\(device.model) · \(device.operatingSystem)")
              .foregroundStyle(.secondary)
          }
          Spacer()
          StatusBadge(state: device.connectionState)
        }

        SectionCard {
          Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 10) {
            DetailRow(label: "Platform", value: device.platform.displayName)
            DetailRow(label: "Architecture", value: device.architecture)
            DetailRow(
              label: "Last seen",
              value: device.lastSeen.formatted(date: .abbreviated, time: .shortened))
            DetailRow(label: "Allowance", value: device.currentAllowance)
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("Supported capabilities")
            .font(.title3.weight(.semibold))
          LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
            ForEach(device.capabilities.sorted { $0.title < $1.title }, id: \.self) { capability in
              Label(capability.title, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
          }
        }

        SectionCard {
          VStack(alignment: .leading, spacing: 10) {
            Label("Platform limitations", systemImage: "info.circle.fill")
              .font(.headline)
            ForEach(device.limitations, id: \.self) { limitation in
              Text("• \(limitation)")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        HStack {
          Label("Remote actions arrive in later approved stages.", systemImage: "lock.shield")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Lock") {}
            .disabled(true)
          Button("More Actions…") {}
            .disabled(true)
        }
      }
      .padding(24)
    }
    .background(.background.secondary)
    .accessibilityIdentifier(AccessibilityID.deviceDetail.rawValue)
  }
}

private struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    GridRow {
      Text(label)
        .foregroundStyle(.secondary)
      Text(value)
        .textSelection(.enabled)
    }
  }
}
