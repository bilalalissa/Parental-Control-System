import AppKit
import EndpointCore
import SwiftUI
import UserNotifications

@main
struct ParentalControlChildApp: App {
  @NSApplicationDelegateAdaptor(ChildAppDelegate.self) private var appDelegate
  @StateObject private var model = ChildDashboardModel()
  var body: some Scene {
    WindowGroup("Parental Control") {
      ChildDashboard(model: model).frame(minWidth: 680, minHeight: 580)
    }
    .windowResizability(.contentMinSize)
  }
}

final class ChildAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    Task {
      _ = try? await center.requestAuthorization(options: [.alert, .sound])
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

@MainActor
final class ChildDashboardModel: NSObject, ObservableObject {
  @Published var status: EndpointStatus?
  @Published var messages: [EndpointChatMessage] = []
  @Published var error = "Connecting to the protected endpoint service…"
  @Published var actionMessage = ""
  private let client = EndpointXPCClient()
  private var timer: Timer?
  private var chatVisible = false

  var unreadMessageCount: Int {
    messages.filter(\.isUnreadFromParent).count
  }

  override init() {
    super.init()
    let center = DistributedNotificationCenter.default()
    center.addObserver(
      self, selector: #selector(chatChanged),
      name: Notification.Name("com.bilalalissa.ParentalControlAgent.chat-received"), object: nil)
    center.addObserver(
      self, selector: #selector(chatChanged),
      name: Notification.Name("com.bilalalissa.ParentalControlAgent.chat-changed"), object: nil)
    Task {
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound])
    }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  deinit { DistributedNotificationCenter.default().removeObserver(self) }

  @objc private func chatChanged() { refresh() }

  func refresh() {
    client.fetchDashboard { [weak self] result in
      Task { @MainActor in
        switch result {
        case .success(let value):
          self?.status = value.status
          self?.messages = value.messages
          self?.error = ""
          if self?.chatVisible == true { self?.markChatRead() }
        case .failure:
          self?.error =
            "Endpoint service unavailable. Ask an administrator to run parental-control-agentctl status."
        }
      }
    }
  }

  func setChatVisible(_ visible: Bool) {
    chatVisible = visible
    if visible { markChatRead() }
  }

  private func markChatRead() {
    guard messages.contains(where: { $0.isFromParent && $0.state != .read }) else { return }
    client.markChatRead { [weak self] result in
      guard result.isSuccess else { return }
      Task { @MainActor in self?.refresh() }
    }
  }

  func send(_ text: String) {
    let latestParentMessage = messages.last { $0.isFromParent }
    let request: EndpointChatRequest
    if let latestParentMessage, latestParentMessage.audience == .familyGroup {
      request = EndpointChatRequest(
        text: text, audience: .familyGroup, threadID: latestParentMessage.threadID)
    } else {
      request = EndpointChatRequest(text: text)
    }
    client.sendChat(request) { [weak self] result in
      Task { @MainActor in
        self?.actionMessage =
          result.isSuccess ? "Message queued securely." : "Message could not be queued."
        if result.isSuccess { NSSound.beep() }
        self?.refresh()
      }
    }
  }

  func requestTime(minutes: Int, note: String) {
    client.requestMoreTime(EndpointMoreTimeRequest(minutes: minutes, note: note)) {
      [weak self] result in
      Task { @MainActor in
        self?.actionMessage =
          result.isSuccess
          ? "Request queued for your parent." : "Request could not be queued."
      }
    }
  }
}

extension Result {
  fileprivate var isSuccess: Bool {
    if case .success = self { return true }
    return false
  }
}

struct ChildDashboard: View {
  @ObservedObject var model: ChildDashboardModel
  @State private var draft = ""
  @State private var requestMinutes = 15
  @State private var requestNote = ""
  @State private var selectedTab = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 14) {
        Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(
          width: 58, height: 58)
        VStack(alignment: .leading) {
          Text("Parental controls are visible and active").font(.title2.bold())
          Text("This Mac communicates directly with your parent controller on the local network.")
            .foregroundStyle(.secondary)
        }
      }
      Divider()
      if let status = model.status {
        VStack(spacing: 12) {
          HStack(spacing: 0) {
            ChildTabButton(
              title: "Status", systemImage: "checkmark.shield", tag: 0,
              selection: $selectedTab)
            ChildTabButton(
              title: "Chat", systemImage: "message", badge: model.unreadMessageCount, tag: 1,
              selection: $selectedTab)
            ChildTabButton(
              title: "Request Time", systemImage: "hourglass.badge.plus", tag: 2,
              selection: $selectedTab)
            ChildTabButton(
              title: "Privacy", systemImage: "hand.raised", tag: 3,
              selection: $selectedTab)
          }
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

          Group {
            switch selectedTab {
            case 1: chatView
            case 2: requestView
            case 3: disclosureView(status)
            default: statusView(status)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedTab) { _, value in model.setChatVisible(value == 1) }
      } else {
        Spacer()
        ProgressView().frame(maxWidth: .infinity)
        Text(model.error).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        Spacer()
      }
      if !model.actionMessage.isEmpty {
        Text(model.actionMessage).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(22)
    .toolbar {
      Button("Refresh") { model.refresh() }.accessibilityIdentifier("refresh-status")
    }
  }

  private func statusView(_ status: EndpointStatus) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
        row("Controller", status.connectionState.rawValue.capitalized)
        row("Last contact", status.lastControllerContact?.formatted() ?? "Never")
        row("This Mac", "\(status.deviceName) · \(status.model)")
        row("System", "\(status.operatingSystem) · \(status.architecture)")
        row("Session", status.sessionState.rawValue.capitalized)
        row("Applications", status.activityCollectionEnabled ? "Shared (names only)" : "Not shared")
        row("Retention", "\(status.activityRetentionDays) days on parent controller")
        row("Browser tabs", status.browserCollectionEnabled ? "Shared by extension" : "Not shared")
        row("Tab retention", "\(status.browserRetentionDays) days on parent controller")
      }
      GroupBox("Schedule") {
        Text("No schedule enforcement is configured in Stage 05.")
          .frame(maxWidth: .infinity, alignment: .leading).padding(6)
      }
      Spacer()
    }.padding(.top, 14)
  }

  private var chatView: some View {
    VStack(spacing: 10) {
      ScrollView {
        LazyVStack(spacing: 9) {
          if model.messages.isEmpty {
            ContentUnavailableView("No messages", systemImage: "message")
          }
          ForEach(model.messages) { message in
            HStack {
              if message.isFromParent { Spacer(minLength: 80) }
              VStack(alignment: .leading, spacing: 4) {
                Text(message.sender).font(.caption.bold())
                Text(message.displayText)
                  .italic(message.deletedAt != nil)
                  .foregroundStyle(message.deletedAt == nil ? .primary : .secondary)
                  .textSelection(.enabled)
                HStack(spacing: 12) {
                  Label(
                    message.state.rawValue.capitalized,
                    systemImage: stateIcon(message.state.rawValue))
                  if message.editedAt != nil, message.deletedAt == nil {
                    Label("Edited", systemImage: "pencil")
                  }
                }
                .font(.caption2).foregroundStyle(.secondary)
              }
              .padding(10)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
              if !message.isFromParent { Spacer(minLength: 80) }
            }
          }
        }.padding(.vertical, 10)
      }
      HStack {
        TextField("Message your parent", text: $draft).textFieldStyle(.roundedBorder)
        Button("Send") {
          let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !text.isEmpty else { return }
          model.send(text)
          draft = ""
        }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  private var requestView: some View {
    Form {
      Stepper("Request \(requestMinutes) minutes", value: $requestMinutes, in: 5...240, step: 5)
      TextField("Optional note", text: $requestNote)
      Button("Send Request") {
        model.requestTime(minutes: requestMinutes, note: requestNote)
        requestNote = ""
      }.buttonStyle(.borderedProminent)
      Text(
        "A request is not an automatic time grant. Schedule enforcement begins in a later stage."
      )
      .font(.caption).foregroundStyle(.secondary)
    }.formStyle(.grouped)
  }

  private func disclosureView(_ status: EndpointStatus) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        GroupBox("Information shared") {
          Text(
            "Device and system details, uptime, login/session state, network interface metadata, health, and—when enabled—running application names plus bounded Chrome, Edge, or Arc tab titles and website origins. Chat text is shared only within the paired family connection. Parent announcements are spoken locally using macOS system speech."
          ).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        GroupBox("Never collected") {
          Text(
            "No command lines, window or document contents, file contents, screenshots, keystrokes, passwords, clipboard, camera, microphone, private tabs, URL query strings/fragments, page content, forms, cookies, or network traffic."
          ).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        Label(
          status.activityCollectionEnabled
            ? "Application-name sharing is enabled by your parent."
            : "Application-name sharing is disabled.",
          systemImage: status.activityCollectionEnabled ? "eye" : "eye.slash")
        Label(
          status.browserCollectionEnabled
            ? "Browser title/origin sharing is enabled by your parent."
            : "Browser sharing is disabled.",
          systemImage: status.browserCollectionEnabled
            ? "globe.badge.chevron.backward" : "eye.slash")
      }.padding(.top, 14)
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }

  private func stateIcon(_ state: String) -> String {
    switch state {
    case "queued": "tray"
    case "sent": "paperplane"
    case "delivered": "checkmark.circle"
    case "read": "checkmark.circle.fill"
    case "failed": "exclamationmark.triangle"
    default: "questionmark.circle"
    }
  }
}

private struct ChildTabButton: View {
  let title: String
  let systemImage: String
  var badge = 0
  let tag: Int
  @Binding var selection: Int

  var body: some View {
    Button {
      selection = tag
    } label: {
      HStack(spacing: 6) {
        Label(title, systemImage: systemImage)
        if badge > 0 {
          Text(badge > 99 ? "99+" : "\(badge)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red, in: Capsule())
            .accessibilityLabel("Unread messages")
            .accessibilityValue("\(badge)")
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(
        selection == tag ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear),
        in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selection == tag ? .isSelected : [])
  }
}
