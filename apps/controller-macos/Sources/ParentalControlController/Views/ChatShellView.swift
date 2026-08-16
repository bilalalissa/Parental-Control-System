import HubCore
import SwiftUI

struct ChatShellView: View {
  let store: ControllerStore
  @State private var audience = ChatAudienceMode.direct
  @State private var selectedDeviceID: String?
  @State private var draft = ""

  private var devices: [HubDeviceRecord] { store.pairedDevices }
  private var recipients: [HubDeviceRecord] {
    switch audience {
    case .direct: devices.filter { $0.id == selectedDeviceID }
    case .familyGroup, .announcement: devices
    }
  }
  private var messages: [HubChatMessage] {
    let values = store.hubStatus?.chatMessages ?? []
    switch audience {
    case .direct: return values.filter { $0.deviceID == selectedDeviceID && $0.audience == .direct }
    case .familyGroup: return values.filter { $0.audience == .familyGroup }
    case .announcement: return values.filter { $0.audience == .announcement }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      conversation
      Divider()
      composer
    }
    .navigationTitle("Chat")
    .accessibilityIdentifier(AccessibilityID.chat.rawValue)
    .onAppear { if selectedDeviceID == nil { selectedDeviceID = devices.first?.id } }
    .onChange(of: devices.map(\.id)) { _, ids in
      if selectedDeviceID == nil || !ids.contains(selectedDeviceID ?? "") {
        selectedDeviceID = ids.first
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Family chat").font(.largeTitle.weight(.semibold))
          Text("Encrypted LAN delivery · bounded 30-day local retention")
            .foregroundStyle(.secondary)
        }
        Spacer()
        if audience == .direct {
          Picker("Device", selection: $selectedDeviceID) {
            ForEach(devices) { device in Text(device.name).tag(Optional(device.id)) }
          }.frame(width: 220)
        }
      }
      Picker("Audience", selection: $audience) {
        ForEach(ChatAudienceMode.allCases) { mode in
          Label(mode.title, systemImage: mode.systemImage).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier(AccessibilityID.chatAudience.rawValue)
      HStack(spacing: 8) {
        Image(systemName: audience.systemImage)
          .foregroundStyle(audience == .announcement ? Color.orange : Color.accentColor)
        Text(audienceDescription).font(.callout)
        Spacer()
        Text("\(recipients.count) recipient\(recipients.count == 1 ? "" : "s")")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.padding(24)
  }

  private var conversation: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        if messages.isEmpty {
          ContentUnavailableView(
            devices.isEmpty ? "No paired child devices" : "No messages yet",
            systemImage: audience.systemImage,
            description: Text(
              devices.isEmpty
                ? "Pair a macOS child device before sending a message."
                : "Messages will appear here with queued, sent, delivered, read, or failed state.")
          )
          .padding(.top, 60)
        }
        ForEach(messages) { message in
          HubMessageBubble(message: message, deviceName: deviceName(message.deviceID))
        }
      }.padding(24)
    }
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        TextField(
          audience.composerPlaceholder.replacingOccurrences(of: " preview", with: ""), text: $draft
        )
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier(AccessibilityID.chatComposer.rawValue)
        .onSubmit(send)
        Button(audience == .announcement ? "Announce" : "Send", action: send)
          .buttonStyle(.borderedProminent)
          .disabled(
            draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || recipients.isEmpty
          )
          .accessibilityIdentifier(AccessibilityID.chatPreviewButton.rawValue)
      }
      if let status = store.chatStatusMessage {
        Text(status).font(.caption).foregroundStyle(.secondary)
      } else {
        Label("Offline devices retain up to 100 queued envelopes.", systemImage: "tray.full")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.padding(16).background(.bar)
  }

  private var audienceDescription: String {
    switch audience {
    case .direct:
      return recipients.first.map { "Private conversation with \($0.name)." }
        ?? "Select a child device."
    case .familyGroup: return "One family thread sent to every paired child device."
    case .announcement: return "Parent announcement sent to every paired child device."
    }
  }

  private func deviceName(_ id: String) -> String {
    devices.first { $0.id == id }?.name ?? "Child device"
  }

  private func send() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    store.sendChat(text: text, audience: audience, deviceIDs: recipients.map(\.id))
    draft = ""
  }
}

private struct HubMessageBubble: View {
  let message: HubChatMessage
  let deviceName: String

  var body: some View {
    HStack {
      if message.isFromParent { Spacer(minLength: 80) }
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(message.sender).font(.caption.weight(.semibold))
          Text("· \(deviceName)").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Text(message.sentAt, style: .time).font(.caption2).foregroundStyle(.secondary)
        }
        Text(message.text).textSelection(.enabled)
        Label(message.state.rawValue.capitalized, systemImage: stateIcon)
          .font(.caption2).foregroundStyle(message.state == .failed ? .red : .secondary)
      }
      .padding(12)
      .frame(maxWidth: 520, alignment: .leading)
      .background(
        message.isFromParent
          ? AnyShapeStyle(Color.accentColor.opacity(0.13)) : AnyShapeStyle(.regularMaterial),
        in: RoundedRectangle(cornerRadius: 13))
      if !message.isFromParent { Spacer(minLength: 80) }
    }
  }

  private var stateIcon: String {
    switch message.state {
    case .queued: "tray"
    case .sent: "paperplane"
    case .delivered: "checkmark.circle"
    case .read: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle"
    }
  }
}
