import EndpointCore
import SwiftUI
import UserNotifications

@main
struct ParentalControlChildApp: App {
  @StateObject private var model = ChildDashboardModel()
  var body: some Scene {
    WindowGroup("Parental Control") {
      ChildDashboard(model: model).frame(minWidth: 680, minHeight: 580)
    }
    .windowResizability(.contentMinSize)
  }
}

@MainActor
final class ChildDashboardModel: ObservableObject {
  @Published var status: EndpointStatus?
  @Published var messages: [EndpointChatMessage] = []
  @Published var error = "Connecting to the protected endpoint service…"
  @Published var actionMessage = ""
  private let client = EndpointXPCClient()
  private var timer: Timer?

  init() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func refresh() {
    client.fetchDashboard { [weak self] result in
      Task { @MainActor in
        switch result {
        case .success(let value):
          self?.status = value.status
          self?.messages = value.messages
          self?.error = ""
        case .failure:
          self?.error =
            "Endpoint service unavailable. Ask an administrator to run parental-control-agentctl status."
        }
      }
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
        TabView {
          statusView(status).tabItem { Label("Status", systemImage: "checkmark.shield") }
          chatView.tabItem { Label("Chat", systemImage: "message") }
          requestView.tabItem { Label("Request Time", systemImage: "hourglass.badge.plus") }
          disclosureView(status).tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
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
      }
      GroupBox("Schedule") {
        Text("No schedule enforcement is configured in Stage 04.")
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
                Text(message.text).textSelection(.enabled)
                Text(message.state.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)
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
            "Device and system details, uptime, login/session state, network interface metadata, health, and—when enabled—running and foreground application names and bundle identifiers. Chat text is shared only within the paired family connection."
          ).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        GroupBox("Never collected") {
          Text(
            "No command lines, window or document titles, file contents, screenshots, keystrokes, passwords, clipboard, camera, microphone, browser tabs, page content, forms, cookies, or network traffic."
          ).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        Label(
          status.activityCollectionEnabled
            ? "Application-name sharing is enabled by your parent."
            : "Application-name sharing is disabled.",
          systemImage: status.activityCollectionEnabled ? "eye" : "eye.slash")
      }.padding(.top, 14)
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }
}
