import DesignSystem
import HubCore
import SwiftUI

struct DevicesView: View {
  let store: ControllerStore

  var body: some View {
    HSplitView {
      List(selection: Bindable(store).selectedDeviceID) {
        Section("Paired devices") {
          ForEach(store.pairedDevices) { device in
            PairedDeviceSidebarRow(
              device: device,
              pendingRequestCount: store.pendingTimeRequestCount(deviceID: device.id)
            )
            .tag(device.id)
          }
        }
      }
      .listStyle(.sidebar)
      .frame(minWidth: 230, idealWidth: 270, maxWidth: 330)
      .overlay {
        if store.pairedDevices.isEmpty {
          ContentUnavailableView(
            "No paired devices", systemImage: "laptopcomputer.and.iphone",
            description: Text("Create a one-time pairing code from Dashboard."))
        }
      }
      .accessibilityIdentifier(AccessibilityID.deviceList.rawValue)

      Group {
        if let device = store.selectedPairedDevice {
          PairedDeviceDetailView(
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
            store: store
          )
          .id(device.id)
        } else {
          ContentUnavailableView(
            "Select a paired device", systemImage: "laptopcomputer.and.iphone",
            description: Text("Device details and privacy controls appear here."))
        }
      }
      .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
      .background(ControlTheme.canvas)
    }
    .navigationTitle("Devices")
    .accessibilityIdentifier(AccessibilityID.devices.rawValue)
  }
}

private struct PairedDeviceSidebarRow: View {
  let device: HubDeviceRecord
  let pendingRequestCount: Int

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: platformIcon)
        .foregroundStyle(.secondary)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(device.name).lineLimit(1)
        HStack(spacing: 5) {
          Circle()
            .fill(device.state() == .online ? ControlTheme.success : ControlTheme.textMuted)
            .frame(width: 6, height: 6)
          Text(device.state() == .online ? "Online" : "Offline")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
      if pendingRequestCount > 0 {
        Text(pendingRequestCount > 99 ? "99+" : "\(pendingRequestCount)")
          .font(.caption2.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(ControlTheme.accent, in: Capsule())
          .accessibilityLabel("Pending time requests")
          .accessibilityValue("\(pendingRequestCount)")
      }
    }
    .padding(.vertical, 3)
    .accessibilityIdentifier(AccessibilityID.pairedDeviceDisclosure.rawValue)
  }

  private var platformIcon: String {
    switch device.platform.lowercased() {
    case "windows": "desktopcomputer"
    case "ipados", "ios": "ipad"
    default: "laptopcomputer"
    }
  }
}

private struct PairedDeviceDetailView: View {
  let device: HubDeviceRecord
  let configuration: ActivityConfiguration
  let activity: [HubAppActivity]
  let browserConfiguration: BrowserConfiguration
  let browserTabs: [HubBrowserTab]
  let requests: [MoreTimeRequestRecord]
  let store: ControllerStore

  @State private var retentionDays: Int
  @State private var browserRetentionDays: Int
  @State private var pendingHighImpactAction: PolicyAction?

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

  private var activityAlertKinds: [HubActivityAlertKind] {
    let appKinds = activity.compactMap(HubActivityAlertClassifier.kind(for:))
    let tabKinds = browserTabs.compactMap(HubActivityAlertClassifier.kind(for:))
    return Array(Set(appKinds + tabKinds)).sorted { $0.rawValue < $1.rawValue }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        deviceHeader
        networkSection
        capabilitySection
        immediateActionsSection
        activitySection
        browserSection
        requestSection
        statusMessages
      }
      .padding(24)
    }
    .background(ControlTheme.canvas)
    .onChange(of: configuration.retentionDays) { _, days in retentionDays = days }
    .onChange(of: browserConfiguration.retentionDays) { _, days in browserRetentionDays = days }
    .accessibilityIdentifier(AccessibilityID.deviceDetail.rawValue)
    .confirmationDialog(
      "Confirm \(pendingHighImpactAction?.rawValue ?? "action")",
      isPresented: Binding(
        get: { pendingHighImpactAction != nil },
        set: { if !$0 { pendingHighImpactAction = nil } }),
      titleVisibility: .visible
    ) {
      if let action = pendingHighImpactAction {
        Button("Send \(action.rawValue.capitalized) Request", role: .destructive) {
          store.sendImmediateAction(deviceID: device.id, action: action, confirmed: true)
          pendingHighImpactAction = nil
        }
        Button("Cancel", role: .cancel) { pendingHighImpactAction = nil }
      }
    } message: {
      Text(
        "macOS will show its own confirmation and preserve app save prompts. The child can cancel; this app never force-quits applications."
      )
    }
  }

  private var deviceHeader: some View {
    VStack(alignment: .leading, spacing: 14) {
      ControlEyebrow("Authenticated endpoint")
      HStack(alignment: .top, spacing: 16) {
        Image(systemName: "laptopcomputer")
          .font(.system(size: 32))
          .foregroundStyle(ControlTheme.accent)
          .frame(width: 58, height: 58)
          .background(ControlTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 5) {
          Text(device.name).font(ControlTheme.displayTitle)
          Text(
            "\(device.platform.capitalized) · Paired \(device.pairedAt.formatted(date: .abbreviated, time: .omitted))"
          )
          .foregroundStyle(.secondary)
        }
        Spacer()
        connectionBadge
      }
      HStack(spacing: 18) {
        Label(
          "Last seen \(device.lastSeen.formatted(date: .abbreviated, time: .shortened))",
          systemImage: "clock")
        Label("Local LAN", systemImage: "network")
        Spacer()
        Button("Revoke") { store.revokePairedDevice(device.id) }
          .buttonStyle(.bordered)
        Button("Unpair", role: .destructive) { store.unpairDevice(device.id) }
          .buttonStyle(.bordered)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var connectionBadge: some View {
    let online = device.state() == .online
    let color = online ? ControlTheme.success : ControlTheme.textMuted
    return HStack(spacing: 6) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(online ? "Online" : "Offline")
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(color)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(color.opacity(0.12), in: Capsule())
  }

  private var networkSection: some View {
    SectionCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("Local network interfaces").font(ControlTheme.sectionTitle)
        Text(
          "Private or link-local addresses from physical interfaces only. MAC addresses are informational and are never used for pairing or identity."
        )
        .font(.caption).foregroundStyle(.secondary)
        let interfaces = device.networkInterfaces ?? []
        if interfaces.isEmpty {
          Label(
            "No physical-interface LAN metadata is currently available.",
            systemImage: "network.slash"
          )
          .font(.caption).foregroundStyle(.secondary)
        } else {
          Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
            ForEach(interfaces) { interface in
              GridRow {
                Text(interface.interface).font(.caption.monospaced().weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                  ForEach(interface.addresses, id: \.self) { address in
                    Text(address).font(.caption.monospaced()).textSelection(.enabled)
                  }
                  if interface.addresses.isEmpty {
                    Text("IP unavailable").font(.caption).foregroundStyle(.secondary)
                  }
                }
                Text(interface.macAddress ?? "MAC unavailable")
                  .font(.caption.monospaced())
                  .foregroundStyle(interface.macAddress == nil ? .secondary : .primary)
                  .textSelection(.enabled)
              }
            }
          }
        }
      }
    }
  }

  private var capabilitySection: some View {
    SectionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Supported capabilities").font(ControlTheme.sectionTitle)
        FlowLayout(spacing: 8) {
          ForEach(device.capabilities.sorted(), id: \.self) { capability in
            Label(capabilityTitle(capability), systemImage: "checkmark.circle.fill")
              .font(.caption)
              .foregroundStyle(ControlTheme.success)
              .padding(.horizontal, 9)
              .padding(.vertical, 6)
              .background(ControlTheme.success.opacity(0.10), in: Capsule())
          }
        }
      }
    }
  }

  private var immediateActionsSection: some View {
    SectionCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("Immediate actions").font(ControlTheme.sectionTitle)
        Text(
          "Commands are signed, expire after two minutes, are capability-checked, and generate receipts and audit records. Lock is the safe default."
        )
        .font(.caption).foregroundStyle(.secondary)
        HStack {
          Button("Lock Screen") {
            store.sendImmediateAction(deviceID: device.id, action: .lock, confirmed: true)
          }
          .disabled(device.state() != .online || !device.capabilities.contains("lock"))
          Menu("More Actions") {
            Button("Log Out…") { pendingHighImpactAction = .logoff }
              .disabled(device.state() != .online || !device.capabilities.contains("logoff"))
            Button("Restart…") { pendingHighImpactAction = .restart }
              .disabled(device.state() != .online || !device.capabilities.contains("restart"))
            Button("Shut Down…") { pendingHighImpactAction = .shutdown }
              .disabled(device.state() != .online || !device.capabilities.contains("shutdown"))
          }
          Spacer()
          if device.state() != .online {
            Label("Offline — short-lived actions are unavailable", systemImage: "wifi.slash")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        if let status = store.policyActionStatusMessage {
          Text(status).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var activitySection: some View {
    SectionCard {
      VStack(alignment: .leading, spacing: 10) {
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
        alertLabels
        if activity.isEmpty {
          Text(
            configuration.enabled ? "No application activity received yet." : "Collection disabled."
          )
          .font(.caption).foregroundStyle(.secondary)
        } else {
          ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 8) {
              ForEach(activity) { application in applicationRow(application) }
            }
            .padding(.trailing, 6)
          }
          .scrollIndicators(.visible)
          .frame(height: min(220, max(38, CGFloat(activity.count) * 30)))
          .accessibilityLabel("Recently observed applications")
        }
      }
    }
  }

  @ViewBuilder private var alertLabels: some View {
    if !activityAlertKinds.isEmpty {
      HStack(spacing: 8) {
        Label("Observed activity alerts", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(ControlTheme.accentSoft)
        ForEach(activityAlertKinds, id: \.self) { kind in
          Text(kind.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ControlTheme.accent.opacity(0.14), in: Capsule())
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

  private func applicationRow(_ application: HubAppActivity) -> some View {
    HStack {
      Image(systemName: application.isForeground ? "app.badge.checkmark" : "app")
      Text(application.applicationName)
      Text(application.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
      Spacer()
      if let kind = HubActivityAlertClassifier.kind(for: application) {
        Label(kind.title, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(ControlTheme.accentSoft)
      }
      if application.isForeground {
        Text("Foreground").font(.caption).foregroundStyle(ControlTheme.success)
      }
    }
  }

  private var browserSection: some View {
    SectionCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Toggle(
            "Share Chrome/Edge/Arc tab titles and origins",
            isOn: Binding(
              get: { browserConfiguration.enabled },
              set: {
                store.configureBrowser(
                  deviceID: device.id, enabled: $0, retentionDays: browserRetentionDays)
              })
          )
          .accessibilityIdentifier(AccessibilityID.browserSharingToggle.rawValue)
          Spacer()
          Stepper("Retain \(browserRetentionDays) days", value: $browserRetentionDays, in: 1...30)
            .onChange(of: browserRetentionDays) { _, days in
              store.configureBrowser(
                deviceID: device.id, enabled: browserConfiguration.enabled,
                retentionDays: days)
            }
        }
        Text(
          "Recently observed open tabs are retained for the selected period. Titles and website origins only; private tabs, paths, query strings, fragments, page content, forms, cookies, and traffic are excluded."
        )
        .font(.caption).foregroundStyle(.secondary)
        if browserTabs.isEmpty {
          Text(
            browserConfiguration.enabled
              ? "No browser metadata received. Install and enable the extension in Chrome, Edge, or Arc."
              : "Browser sharing is disabled."
          )
          .font(.caption).foregroundStyle(.secondary)
        } else {
          ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 10) {
              ForEach(browserTabs) { tab in browserRow(tab) }
            }
            .padding(.trailing, 6)
          }
          .scrollIndicators(.visible)
          .frame(height: min(280, max(52, CGFloat(browserTabs.count) * 52)))
          .accessibilityLabel("Recently observed browser tabs")
        }
      }
    }
  }

  private func browserRow(_ tab: HubBrowserTab) -> some View {
    HStack {
      Image(systemName: tab.isActive ? "globe.badge.chevron.backward" : "globe")
      VStack(alignment: .leading, spacing: 2) {
        Text(tab.title)
        Text(
          "\(tab.browser.capitalized) · \(tab.origin) · Observed \(tab.observedAt.formatted(date: .omitted, time: .shortened))"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if let kind = HubActivityAlertClassifier.kind(for: tab) {
        Label(kind.title, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(ControlTheme.accentSoft)
      }
      if tab.isActive {
        Text("Active when observed").font(.caption).foregroundStyle(ControlTheme.success)
      }
    }
  }

  @ViewBuilder private var requestSection: some View {
    if !requests.isEmpty {
      SectionCard {
        VStack(alignment: .leading, spacing: 8) {
          Text("Recent time requests").font(ControlTheme.sectionTitle)
          ForEach(requests.prefix(3)) { request in
            HStack {
              Label(
                "Requested \(request.requestedMinutes) minutes · \(request.createdAt.formatted(date: .omitted, time: .shortened))",
                systemImage: "hourglass.badge.plus"
              )
              .font(.caption)
              Spacer()
              if request.state == .pending {
                HStack(spacing: 6) {
                  Button(
                    store.resolvingTimeRequestIDs.contains(request.id) ? "Resolving…" : "Approve"
                  ) {
                    store.grantBonus(request: request)
                  }
                  .disabled(store.resolvingTimeRequestIDs.contains(request.id))
                  Button("Reject", role: .destructive) {
                    store.rejectBonus(request: request)
                  }
                  .disabled(store.resolvingTimeRequestIDs.contains(request.id))
                }
              } else {
                Label(
                  request.state.isApproved ? "Approved" : request.state.rawValue.capitalized,
                  systemImage: request.state.isApproved
                    ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(
                  request.state.isApproved ? ControlTheme.success : ControlTheme.textMuted)
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder private var statusMessages: some View {
    if let status = store.activityStatusMessage {
      Text(status).font(.caption).foregroundStyle(.secondary)
    }
    if let status = store.browserStatusMessage {
      Text(status).font(.caption).foregroundStyle(.secondary)
    }
  }

  private func capabilityTitle(_ value: String) -> String {
    value
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .capitalized
  }
}

private struct FlowLayout: Layout {
  let spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) -> CGSize {
    layout(proposal: proposal, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) {
    let result = layout(proposal: proposal, subviews: subviews)
    for (index, point) in result.points.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
    }
  }

  private func layout(
    proposal: ProposedViewSize, subviews: Subviews
  ) -> (size: CGSize, points: [CGPoint]) {
    let width = proposal.width ?? 800
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var points: [CGPoint] = []
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      points.append(CGPoint(x: x, y: y))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    return (CGSize(width: width, height: y + rowHeight), points)
  }
}
