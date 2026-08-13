import SwiftUI

struct ChatShellView: View {
  let store: ControllerStore

  @State private var audience = ChatAudienceMode.direct
  @State private var draft = ""
  @State private var localPreviews: [LocalChatPreview] = []

  private var messages: [ChatMessage] {
    switch audience {
    case .direct:
      guard let deviceID = store.selectedDeviceID else { return [] }
      return store.chatMessages.filter { $0.deviceID == deviceID }
    case .familyGroup, .announcement:
      return []
    }
  }

  private var visiblePreviews: [LocalChatPreview] {
    localPreviews.filter { preview in
      guard preview.audience == audience else { return false }
      return audience != .direct
        || preview.recipientIDs.contains(where: { $0 == store.selectedDeviceID })
    }
  }

  private var recipients: [ManagedDevice] {
    audience.recipients(from: store.devices, selectedDeviceID: store.selectedDeviceID)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      audienceSummary
      Divider()
      conversation
      Divider()
      composer
    }
    .navigationTitle("Chat")
    .accessibilityIdentifier(AccessibilityID.chat.rawValue)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Family chat")
            .font(.largeTitle.weight(.semibold))
          Text("Local synthetic preview · Transport arrives in Stage 02")
            .foregroundStyle(.secondary)
        }
        Spacer()
        if audience == .direct {
          Picker("Device", selection: Bindable(store).selectedDeviceID) {
            ForEach(store.devices) { device in
              Text(device.name).tag(Optional(device.id))
            }
          }
          .frame(width: 200)
        }
      }

      Picker("Audience", selection: $audience) {
        ForEach(ChatAudienceMode.allCases) { mode in
          Label(mode.title, systemImage: mode.systemImage).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier(AccessibilityID.chatAudience.rawValue)
    }
    .padding(24)
  }

  private var audienceSummary: some View {
    HStack(spacing: 12) {
      Image(systemName: audience.systemImage)
        .font(.title2)
        .foregroundStyle(audience == .announcement ? Color.orange : Color.accentColor)
        .frame(width: 36, height: 36)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))

      VStack(alignment: .leading, spacing: 3) {
        Text(summaryTitle)
          .font(.headline)
        Text(summaryDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text("\(recipients.count) device\(recipients.count == 1 ? "" : "s")")
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .background(.bar)
  }

  private var conversation: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        if messages.isEmpty && visiblePreviews.isEmpty {
          ContentUnavailableView(
            emptyTitle,
            systemImage: audience.systemImage,
            description: Text(emptyDescription)
          )
          .padding(.top, 60)
        } else {
          ForEach(messages) { message in
            MessageBubble(message: message, deviceName: deviceName(for: message.deviceID))
          }
          ForEach(visiblePreviews) { preview in
            LocalPreviewBubble(preview: preview)
          }
        }
      }
      .padding(24)
    }
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        TextField(audience.composerPlaceholder, text: $draft)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier(AccessibilityID.chatComposer.rawValue)
          .onSubmit(addLocalPreview)
        Button(buttonTitle, action: addLocalPreview)
          .buttonStyle(.borderedProminent)
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier(AccessibilityID.chatPreviewButton.rawValue)
      }
      Label(
        "Adds a local preview only. Nothing is sent or queued to a device in Stage 01.",
        systemImage: "internaldrive"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(16)
    .background(.bar)
  }

  private var summaryTitle: String {
    switch audience {
    case .direct: recipients.first?.name ?? "Select a device"
    case .familyGroup: "Shared family conversation"
    case .announcement: "All child devices"
    }
  }

  private var summaryDetail: String {
    switch audience {
    case .direct: "A one-to-one conversation preview."
    case .familyGroup:
      "Parent and children share one conversation across \(recipientList)."
    case .announcement:
      "A parent-only broadcast preview addressed to \(recipientList)."
    }
  }

  private var recipientList: String {
    recipients.map(\.name).formatted(.list(type: .and))
  }

  private var emptyTitle: String {
    switch audience {
    case .direct: "No preview messages"
    case .familyGroup: "No family group messages"
    case .announcement: "No announcements yet"
    }
  }

  private var emptyDescription: String {
    switch audience {
    case .direct: "No messages are stored for this synthetic device."
    case .familyGroup: "Add a local group-message preview for every synthetic child device."
    case .announcement: "Add a local parent announcement preview for every synthetic child device."
    }
  }

  private var buttonTitle: String {
    switch audience {
    case .direct: "Add Direct Preview"
    case .familyGroup: "Preview Group Message"
    case .announcement: "Preview Announcement"
    }
  }

  private func deviceName(for id: ManagedDevice.ID) -> String? {
    audience == .familyGroup ? store.devices.first { $0.id == id }?.name : nil
  }

  private func addLocalPreview() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !recipients.isEmpty else { return }
    localPreviews.append(
      LocalChatPreview(
        id: UUID(),
        audience: audience,
        sentAt: Date(),
        text: text,
        recipientIDs: recipients.map(\.id),
        recipientNames: recipients.map(\.name)
      )
    )
    draft = ""
  }
}

private struct MessageBubble: View {
  let message: ChatMessage
  let deviceName: String?

  var body: some View {
    HStack {
      if message.isFromParent { Spacer(minLength: 80) }
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(message.sender)
            .font(.caption.weight(.semibold))
          if let deviceName {
            Text("· \(deviceName)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text(message.sentAt, style: .time)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text(message.text)
          .textSelection(.enabled)
        Text(message.state.rawValue.capitalized)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(12)
      .frame(maxWidth: 480, alignment: .leading)
      .background(
        message.isFromParent
          ? AnyShapeStyle(Color.accentColor.opacity(0.13)) : AnyShapeStyle(.regularMaterial),
        in: RoundedRectangle(cornerRadius: 13)
      )
      if !message.isFromParent { Spacer(minLength: 80) }
    }
  }
}

private struct LocalPreviewBubble: View {
  let preview: LocalChatPreview

  var body: some View {
    HStack {
      Spacer(minLength: 80)
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Label(
            preview.audience == .announcement ? "Parent announcement" : "Parent preview",
            systemImage: preview.audience.systemImage
          )
          .font(.caption.weight(.semibold))
          Spacer()
          Text(preview.sentAt, style: .time)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text(preview.text)
          .textSelection(.enabled)
        Text("To: \(preview.recipientNames.formatted(.list(type: .and)))")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Label("Local preview · Not sent", systemImage: "internaldrive")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.orange)
      }
      .padding(12)
      .frame(maxWidth: 520, alignment: .leading)
      .background(
        preview.audience == .announcement
          ? AnyShapeStyle(Color.orange.opacity(0.13))
          : AnyShapeStyle(Color.accentColor.opacity(0.13)),
        in: RoundedRectangle(cornerRadius: 13)
      )
    }
  }
}
