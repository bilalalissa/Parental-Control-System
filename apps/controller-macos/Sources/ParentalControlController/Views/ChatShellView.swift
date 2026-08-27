import DesignSystem
import HubCore
import SwiftUI

struct ChatShellView: View {
  let store: ControllerStore
  @State private var audience = ChatAudienceMode.direct
  @State private var selectedDeviceID: String?
  @State private var draft = ""
  @State private var editingMessage: HubChatMessage?
  @State private var deletingMessage: HubChatMessage?

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
    .onAppear(perform: selectUnreadConversationAndMark)
    .onChange(of: devices.map(\.id)) { _, ids in
      if selectedDeviceID == nil || !ids.contains(selectedDeviceID ?? "") {
        selectedDeviceID = ids.first
      }
    }
    .onChange(of: selectedDeviceID) { _, _ in markVisibleMessagesRead() }
    .onChange(of: audience) { _, _ in markVisibleMessagesRead() }
    .onChange(of: messages.map { "\($0.id.uuidString):\($0.state.rawValue)" }) { _, _ in
      markVisibleMessagesRead()
    }
    .sheet(item: $editingMessage) { message in
      EditParentMessageSheet(initialText: message.text) { text in
        store.editParentChatMessage(id: message.id, text: text)
      }
    }
    .alert(
      "Delete this message?",
      isPresented: Binding(
        get: { deletingMessage != nil },
        set: { if !$0 { deletingMessage = nil } })
    ) {
      Button("Delete", role: .destructive) {
        if let message = deletingMessage { store.deleteParentChatMessage(id: message.id) }
        deletingMessage = nil
      }
      Button("Cancel", role: .cancel) { deletingMessage = nil }
    } message: {
      Text("The message will become a deletion notice on the parent and child devices.")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          ControlEyebrow("Secure local conversation")
          Text("Family chat").font(ControlTheme.displayTitle)
          Text("Encrypted LAN delivery · bounded 30-day local retention")
            .foregroundStyle(.secondary)
        }
        Spacer()
        if audience == .direct {
          Picker("Device", selection: $selectedDeviceID) {
            ForEach(devices) { device in
              let count = unreadCount(for: .direct, deviceID: device.id)
              Text(count > 0 ? "\(device.name) (\(count))" : device.name).tag(Optional(device.id))
            }
          }.frame(width: 220)
        }
      }
      Picker("Audience", selection: $audience) {
        ForEach(ChatAudienceMode.allCases) { mode in
          let count = unreadCount(for: mode)
          Label(count > 0 ? "\(mode.title) (\(count))" : mode.title, systemImage: mode.systemImage)
            .tag(mode)
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
          HubMessageBubble(
            message: message, deviceName: deviceName(message.deviceID),
            onEdit: { editingMessage = message }, onDelete: { deletingMessage = message })
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
    }.padding(16).background(ControlTheme.surfaceStrong)
  }

  private var audienceDescription: String {
    switch audience {
    case .direct:
      return recipients.first.map { "Private conversation with \($0.name)." }
        ?? "Select a child device."
    case .familyGroup: return "One family thread sent to every paired child device."
    case .announcement:
      return "Sent to every child and spoken there using local system speech."
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

  private func markVisibleMessagesRead() {
    let deviceIDs = Set(messages.filter { !$0.isFromParent }.map(\.deviceID))
    store.markChatRead(deviceIDs: Array(deviceIDs), audience: audience.hubAudience)
  }

  private func unreadCount(for mode: ChatAudienceMode, deviceID: String? = nil) -> Int {
    let unread = store.hubStatus?.chatMessages.filter(\.isUnreadForParent) ?? []
    switch mode {
    case .direct:
      return unread.filter {
        $0.audience == .direct && (deviceID == nil || $0.deviceID == deviceID)
      }.count
    case .familyGroup: return unread.filter { $0.audience == .familyGroup }.count
    case .announcement: return unread.filter { $0.audience == .announcement }.count
    }
  }

  private func selectUnreadConversationAndMark() {
    if let unread = store.hubStatus?.chatMessages.first(where: \.isUnreadForParent) {
      selectedDeviceID = unread.deviceID
      switch unread.audience {
      case .direct: audience = .direct
      case .familyGroup: audience = .familyGroup
      case .announcement: audience = .announcement
      }
    } else if selectedDeviceID == nil {
      selectedDeviceID = devices.first?.id
    }
    Task { @MainActor in
      await Task.yield()
      markVisibleMessagesRead()
    }
  }
}

private struct HubMessageBubble: View {
  let message: HubChatMessage
  let deviceName: String
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack {
      if message.isFromParent { Spacer(minLength: 80) }
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(message.sender).font(.caption.weight(.semibold))
          Text("· \(deviceName)").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Text(message.sentAt, style: .time).font(.caption2).foregroundStyle(.secondary)
          if message.isFromParent, message.deletedAt == nil {
            Menu {
              Button("Edit", systemImage: "pencil", action: onEdit)
              Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
              Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Edit or delete this parent message")
          }
        }
        Text(message.displayText)
          .italic(message.deletedAt != nil)
          .foregroundStyle(message.deletedAt == nil ? .primary : .secondary)
          .textSelection(.enabled)
        HStack(spacing: 12) {
          Label(message.state.rawValue.capitalized, systemImage: stateIcon)
          if message.editedAt != nil, message.deletedAt == nil {
            Label("Edited", systemImage: "pencil")
          }
        }
        .font(.caption2).foregroundStyle(message.state == .failed ? .red : .secondary)
      }
      .padding(12)
      .frame(maxWidth: 520, alignment: .leading)
      .background(
        message.isFromParent
          ? AnyShapeStyle(ControlTheme.accent.opacity(0.14))
          : AnyShapeStyle(ControlTheme.surface),
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

private struct EditParentMessageSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  let onSave: (String) -> Void

  init(initialText: String, onSave: @escaping (String) -> Void) {
    _text = State(initialValue: initialText)
    self.onSave = onSave
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Edit message").font(.title2.bold())
      TextEditor(text: $text).frame(minHeight: 100).border(.separator)
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
        Button("Save") {
          onSave(text)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 440)
  }
}
