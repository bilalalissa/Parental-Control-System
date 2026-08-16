import HubCore
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
    .safeAreaInset(edge: .bottom) {
      if let paired = store.hubStatus?.devices, !paired.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Paired macOS devices").font(.headline)
          ForEach(paired) { device in
            PairedDeviceControlRow(
              device: device,
              configuration: store.hubStatus?.activityConfigurations.first {
                $0.deviceID == device.id
              } ?? ActivityConfiguration(deviceID: device.id),
              activity: store.hubStatus?.activity.filter { $0.deviceID == device.id } ?? [],
              browserConfiguration: store.hubStatus?.browserConfigurations.first {
                $0.deviceID == device.id
              } ?? BrowserConfiguration(deviceID: device.id),
              browserTabs: store.hubStatus?.browserTabs.filter { $0.deviceID == device.id } ?? [],
              requests: store.hubStatus?.moreTimeRequests.filter { $0.deviceID == device.id } ?? [],
              store: store)
          }
          if let status = store.activityStatusMessage {
            Text(status).font(.caption).foregroundStyle(.secondary)
          }
          if let status = store.browserStatusMessage {
            Text(status).font(.caption).foregroundStyle(.secondary)
          }
        }
        .padding(12)
        .background(.bar)
      }
    }
    .navigationTitle("Devices")
    .accessibilityIdentifier(AccessibilityID.devices.rawValue)
  }
}

private struct PairedDeviceControlRow: View {
  let device: HubDeviceRecord
  let configuration: ActivityConfiguration
  let activity: [HubAppActivity]
  let browserConfiguration: BrowserConfiguration
  let browserTabs: [HubBrowserTab]
  let requests: [MoreTimeRequestRecord]
  let store: ControllerStore
  @State private var retentionDays: Int
  @State private var browserRetentionDays: Int
  @State private var isExpanded = false

  init(
    device: HubDeviceRecord, configuration: ActivityConfiguration,
    activity: [HubAppActivity], browserConfiguration: BrowserConfiguration,
    browserTabs: [HubBrowserTab], requests: [MoreTimeRequestRecord], store: ControllerStore
  ) {
    self.device = device
    self.configuration = configuration
    self.activity = activity
    self.browserConfiguration = browserConfiguration
    self.browserTabs = browserTabs
    self.requests = requests
    self.store = store
    _retentionDays = State(initialValue: configuration.retentionDays)
    _browserRetentionDays = State(initialValue: browserConfiguration.retentionDays)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button {
          withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .frame(width: 12)
            Circle().fill(device.state() == .online ? .green : .gray).frame(width: 8, height: 8)
            Text(device.name)
            Text(device.state() == .online ? "Online" : "Offline").foregroundStyle(.secondary)
            Text("Last seen \(device.lastSeen.formatted(date: .omitted, time: .standard))")
              .font(.caption).foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.pairedDeviceDisclosure.rawValue)
        .accessibilityLabel("Activity controls for \(device.name)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        Spacer()
        Button("Revoke") { store.revokePairedDevice(device.id) }.disabled(device.isRevoked)
        Button("Unpair") { store.unpairDevice(device.id) }
      }

      if isExpanded {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Toggle(
              "Share application names",
              isOn: Binding(
                get: { configuration.enabled },
                set: {
                  store.configureActivity(
                    deviceID: device.id, enabled: $0, retentionDays: retentionDays)
                })
            )
            .accessibilityIdentifier(AccessibilityID.activitySharingToggle.rawValue)
            Spacer()
            Stepper("Retain \(retentionDays) days", value: $retentionDays, in: 1...30)
              .onChange(of: retentionDays) { _, days in
                store.configureActivity(
                  deviceID: device.id, enabled: configuration.enabled, retentionDays: days)
              }
          }
          Text(
            "Application names and bundle identifiers only—never command lines or window contents."
          )
          .font(.caption).foregroundStyle(.secondary)
          ForEach(activity.prefix(8)) { application in
            HStack {
              Image(systemName: application.isForeground ? "app.badge.checkmark" : "app")
              Text(application.applicationName)
              Text(application.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
              Spacer()
              if application.isForeground {
                Text("Foreground").font(.caption).foregroundStyle(.green)
              }
            }
          }
          if activity.isEmpty {
            Text(
              configuration.enabled
                ? "No application activity received yet." : "Collection disabled."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          Divider()
          HStack {
            Toggle(
              "Share Chrome/Edge tab titles and origins",
              isOn: Binding(
                get: { browserConfiguration.enabled },
                set: {
                  store.configureBrowser(
                    deviceID: device.id, enabled: $0, retentionDays: browserRetentionDays)
                })
            )
            .accessibilityIdentifier(AccessibilityID.browserSharingToggle.rawValue)
            Spacer()
            Stepper(
              "Retain \(browserRetentionDays) days", value: $browserRetentionDays, in: 1...30
            )
            .onChange(of: browserRetentionDays) { _, days in
              store.configureBrowser(
                deviceID: device.id, enabled: browserConfiguration.enabled,
                retentionDays: days)
            }
          }
          Text(
            "Requires the visible extension. Shares titles and website origins only; private tabs, query strings, fragments, page content, forms, cookies, and traffic are excluded."
          )
          .font(.caption).foregroundStyle(.secondary)
          ForEach(Array(browserTabs.prefix(8).enumerated()), id: \.offset) { _, tab in
            HStack {
              Image(systemName: tab.isActive ? "globe.badge.chevron.backward" : "globe")
              VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                Text("\(tab.browser.capitalized) · \(tab.origin)")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if tab.isActive { Text("Active").font(.caption).foregroundStyle(.green) }
            }
          }
          if browserTabs.isEmpty {
            Text(
              browserConfiguration.enabled
                ? "No browser metadata received. Install and enable the extension in Chrome or Edge."
                : "Browser sharing is disabled."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          ForEach(requests.prefix(3)) { request in
            Label(
              "Requested \(request.requestedMinutes) minutes · \(request.createdAt.formatted(date: .omitted, time: .shortened))",
              systemImage: "hourglass.badge.plus"
            )
            .font(.caption)
          }
        }
        .padding(.leading, 20)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .onChange(of: configuration.retentionDays) { _, days in retentionDays = days }
    .onChange(of: browserConfiguration.retentionDays) { _, days in browserRetentionDays = days }
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
