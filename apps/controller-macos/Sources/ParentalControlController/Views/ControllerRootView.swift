import DesignSystem
import SwiftUI

struct ControllerRootView: View {
  let store: ControllerStore
  @SceneStorage("controller.selectedSection") private var selectedSectionRaw = AppSection.dashboard
    .rawValue

  private var selection: Binding<AppSection?> {
    Binding(
      get: { AppSection(rawValue: selectedSectionRaw) ?? .dashboard },
      set: { selectedSectionRaw = ($0 ?? .dashboard).rawValue }
    )
  }

  var body: some View {
    NavigationSplitView {
      List(selection: selection) {
        Section("Family") {
          ForEach(AppSection.allCases) { section in
            HStack(spacing: 8) {
              Label(section.title, systemImage: section.systemImage)
              Spacer(minLength: 4)
              if section == .chat, store.unreadChatCount > 0 {
                SidebarCountBadge(count: store.unreadChatCount, label: "Unread messages")
              } else if section == .devices, store.pendingTimeRequestCount > 0 {
                SidebarCountBadge(
                  count: store.pendingTimeRequestCount, label: "Pending time requests")
              }
            }
            .tag(section)
            .accessibilityIdentifier("sidebar.\(section.rawValue)")
          }
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(
        min: ControllerLayout.navigationSidebarMinimum,
        ideal: ControllerLayout.navigationSidebarIdeal,
        max: ControllerLayout.navigationSidebarMaximum
      )
      .navigationTitle("Parental Control")
      .accessibilityIdentifier(AccessibilityID.sidebar.rawValue)
      .safeAreaInset(edge: .bottom) {
        VStack(alignment: .leading, spacing: 5) {
          Label("Local authority", systemImage: "network.badge.shield.half.filled")
            .font(.caption.weight(.medium))
          Text("\(store.pairedDevices.count) paired · No cloud relay")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
      }
    } detail: {
      VStack(spacing: 0) {
        if let message = store.databaseStatusMessage {
          DatabaseStatusBanner(message: message)
        }
        selectedView
      }
      .background(ControlTheme.canvas)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          SettingsLink {
            Label("Settings", systemImage: "gearshape")
          }
          .help("Open controller settings")
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .showControllerSection)) { notification in
      if let section = notification.object as? AppSection {
        selectedSectionRaw = section.rawValue
      }
    }
    .task { store.startHub() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) {
      _ in
      store.stopHub()
    }
  }

  @ViewBuilder
  private var selectedView: some View {
    switch AppSection(rawValue: selectedSectionRaw) ?? .dashboard {
    case .dashboard:
      DashboardView(store: store) { deviceID in
        store.selectedDeviceID = deviceID
        selectedSectionRaw = AppSection.devices.rawValue
      }
    case .devices:
      DevicesView(store: store)
    case .schedule:
      ScheduleEditorView(store: store)
    case .chat:
      ChatShellView(store: store)
    case .audit:
      AuditView(events: store.displayedAuditEvents)
    case .storage:
      StorageView(store: store)
    }
  }
}

enum ControllerLayout {
  static let minimumWindowWidth: CGFloat = 1_080
  static let navigationSidebarMinimum: CGFloat = 210
  static let navigationSidebarIdeal: CGFloat = 230
  static let navigationSidebarMaximum: CGFloat = 280
  static let deviceListMinimum: CGFloat = 240
  static let deviceListIdeal: CGFloat = 275
  static let deviceListMaximum: CGFloat = 330
  static let deviceDetailMinimum: CGFloat = 520

  static let requiredThreeColumnWidth =
    navigationSidebarMinimum + deviceListMinimum + deviceDetailMinimum
}

private struct SidebarCountBadge: View {
  let count: Int
  let label: String

  var body: some View {
    Text(count > 99 ? "99+" : "\(count)")
      .font(.caption2.bold())
      .foregroundStyle(.white)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(ControlTheme.accent, in: Capsule())
      .accessibilityLabel(label)
      .accessibilityValue("\(count)")
  }
}

private struct DatabaseStatusBanner: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.callout)
      .foregroundStyle(.orange)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .background(.orange.opacity(0.10))
  }
}
