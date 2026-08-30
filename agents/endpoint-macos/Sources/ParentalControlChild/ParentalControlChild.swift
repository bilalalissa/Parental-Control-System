import AppKit
import DesignSystem
import EndpointCore
import SwiftUI
import UserNotifications

@main
struct ParentalControlChildApp: App {
  @NSApplicationDelegateAdaptor(ChildAppDelegate.self) private var appDelegate
  @StateObject private var model = ChildDashboardModel()
  var body: some Scene {
    WindowGroup("Parental Control") {
      ChildDashboard(model: model)
        .frame(minWidth: 680, minHeight: 580)
        .controlTheme()
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
  @Published var latestTimeRequest: EndpointTimeRequest?
  @Published var error = "Connecting to the protected endpoint service…"
  @Published var actionMessage = ""
  private let client = EndpointXPCClient()
  private var timer: Timer?
  private var chatVisible = false
  private var incomingNotificationTracker = IncomingMessageNotificationTracker()

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
    center.addObserver(
      self, selector: #selector(policyEvent(_:)),
      name: Notification.Name("com.bilalalissa.ParentalControlAgent.policy-event"), object: nil)
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  deinit { DistributedNotificationCenter.default().removeObserver(self) }

  @objc private func chatChanged() { refresh() }

  @objc private func policyEvent(_ notification: Notification) {
    let info = notification.userInfo
    let kind = info?["kind"] as? String ?? "policy"
    let explanation = info?["explanation"] as? String ?? "Your family policy changed."
    let content = UNMutableNotificationContent()
    if kind == "warning", let minutes = info?["minutes"] as? String {
      content.title = "Time warning"
      content.body = "A restriction starts in about \(minutes) minute(s). \(explanation)"
    } else if kind == "clock-change" {
      content.title = "Clock adjustment detected"
      content.body = explanation
    } else {
      content.title = "Family restriction active"
      content.body = explanation
    }
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    refresh()
  }

  func refresh() {
    client.fetchDashboard { [weak self] result in
      Task { @MainActor in
        switch result {
        case .success(let value):
          let newParentMessages =
            self?.incomingNotificationTracker.newlyReceivedMessages(
              in: value.messages) ?? []
          self?.status = value.status
          self?.messages = value.messages
          if self?.latestTimeRequest?.state != value.latestTimeRequest?.state,
            let request = value.latestTimeRequest
          {
            switch request.state {
            case .pending:
              self?.actionMessage = "Waiting for your parent to review the request."
            case .approved:
              self?.actionMessage = "Your parent approved \(request.requestedMinutes) minutes."
            case .rejected:
              self?.actionMessage = "Your parent did not approve this time request."
            }
          }
          self?.latestTimeRequest = value.latestTimeRequest
          self?.error = ""
          if !newParentMessages.isEmpty {
            self?.notifyAboutIncomingMessages(count: newParentMessages.count)
          }
          if self?.chatVisible == true { self?.markChatRead() }
        case .failure:
          self?.error =
            "Endpoint service unavailable. Ask an administrator to run parental-control-agentctl status."
        }
      }
    }
  }

  private func notifyAboutIncomingMessages(count: Int) {
    let content = UNMutableNotificationContent()
    content.title = count == 1 ? "Message from your parent" : "Messages from your parent"
    content.body =
      count == 1 ? "Open Parental Control to read it." : "Open Parental Control to read them."
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
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
        if result.isSuccess { self?.refresh() }
      }
    }
  }

  func submitAdultCode(_ code: String, minutes: Int = 15) {
    client.submitAdultCode(EndpointAdultOverrideRequest(code: code, minutes: minutes)) {
      [weak self] result in
      Task { @MainActor in
        switch result {
        case .success(let until):
          self?.actionMessage =
            "Adult override active until \(until.formatted(date: .omitted, time: .shortened))."
        case .failure(let error):
          self?.actionMessage = String(describing: error)
        }
        self?.refresh()
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
  @State private var adultCode = ""
  @State private var selectedTab = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 14) {
        Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(
          width: 58, height: 58)
        VStack(alignment: .leading, spacing: 5) {
          ControlEyebrow("Visible family endpoint")
          Text("Parental controls are visible and active")
            .font(.system(.title2, design: .monospaced, weight: .bold))
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
          .background(ControlTheme.surface, in: RoundedRectangle(cornerRadius: 8))

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
    .background(ControlTheme.canvas)
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
        VStack(alignment: .leading, spacing: 8) {
          if let version = status.policyVersion {
            LabeledContent("Signed policy", value: "Version \(version)")
            LabeledContent(
              "Current decision", value: status.policyDecision?.rawValue.capitalized ?? "Pending")
            LabeledContent(
              "Restriction", value: status.policyAction?.rawValue.capitalized ?? "None")
            if status.policyDecision == .allow, let restrictionAt = status.policyNextRestrictionAt {
              TimelineView(.periodic(from: .now, by: 1)) { context in
                LabeledContent(
                  "Next restriction",
                  value: Self.countdown(until: restrictionAt, now: context.date)
                )
                .monospacedDigit()
              }
            } else if status.policyDecision == .block {
              LabeledContent("Countdown", value: "Restriction active")
            } else {
              LabeledContent("Next restriction", value: "Not within the next 8 days")
            }
            Text(status.policyReason ?? "The policy is evaluated locally, including while offline.")
              .font(.caption).foregroundStyle(.secondary)
            if let until = status.adultOverrideUntil, until > Date() {
              Label(
                "Adult override until \(until.formatted(date: .omitted, time: .shortened))",
                systemImage: "checkmark.shield")
            }
            HStack {
              SecureField("Adult code", text: $adultCode)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
              Button("Allow 15 Minutes") {
                model.submitAdultCode(adultCode)
                adultCode = ""
              }
              .disabled(adultCode.filter(\.isNumber).count < 4)
            }
            Text(
              "Three failed attempts trigger a five-minute lockout. Settings are read-only here."
            )
            .font(.caption2).foregroundStyle(.secondary)
          } else {
            Text("Waiting for a signed family schedule from the parent controller.")
          }
        }
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
              .background(ControlTheme.surface, in: RoundedRectangle(cornerRadius: 10))
              .overlay {
                RoundedRectangle(cornerRadius: 10).stroke(ControlTheme.border)
              }
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
      if let request = model.latestTimeRequest {
        LabeledContent("Latest request") {
          Label(
            request.state.rawValue.capitalized,
            systemImage: request.state == .approved
              ? "checkmark.circle.fill"
              : (request.state == .rejected ? "xmark.circle.fill" : "clock.fill")
          )
          .foregroundStyle(
            request.state == .approved
              ? ControlTheme.success
              : (request.state == .rejected ? ControlTheme.accent : .secondary))
        }
        Text(
          "\(request.requestedMinutes) minutes · \(request.createdAt.formatted(date: .omitted, time: .shortened))"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Stepper("Request \(requestMinutes) minutes", value: $requestMinutes, in: 5...240, step: 5)
      TextField("Optional note", text: $requestNote)
      Button("Send Request") {
        model.requestTime(minutes: requestMinutes, note: requestNote)
        requestNote = ""
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.latestTimeRequest?.state == .pending)
      Text(
        "A request is not an automatic time grant. Your parent must approve bonus time."
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
        GroupBox("Appearance") {
          ControlAppearancePicker()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
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

  static func countdown(until date: Date, now: Date = Date()) -> String {
    let total = max(0, Int(date.timeIntervalSince(now).rounded(.down)))
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    let seconds = total % 60
    if days > 0 { return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds) }
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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
            .background(ControlTheme.accent, in: Capsule())
            .accessibilityLabel("Unread messages")
            .accessibilityValue("\(badge)")
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(
        selection == tag
          ? AnyShapeStyle(ControlTheme.accent.opacity(0.16)) : AnyShapeStyle(.clear),
        in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selection == tag ? .isSelected : [])
  }
}
