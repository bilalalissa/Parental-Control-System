import SwiftUI

struct ChatShellView: View {
  let store: ControllerStore

  private var messages: [ChatMessage] {
    guard let deviceID = store.selectedDeviceID else { return [] }
    return store.chatMessages.filter { $0.deviceID == deviceID }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Family chat")
            .font(.largeTitle.weight(.semibold))
          Text("Local synthetic preview · Transport arrives in Stage 02")
            .foregroundStyle(.secondary)
        }
        Spacer()
        Picker("Device", selection: Bindable(store).selectedDeviceID) {
          ForEach(store.devices) { device in
            Text(device.name).tag(Optional(device.id))
          }
        }
        .frame(width: 190)
      }
      .padding(24)

      Divider()

      ScrollView {
        LazyVStack(spacing: 12) {
          if messages.isEmpty {
            ContentUnavailableView(
              "No preview messages",
              systemImage: "bubble.left.and.bubble.right",
              description: Text("No messages are stored for this synthetic device.")
            )
            .padding(.top, 70)
          } else {
            ForEach(messages) { message in
              MessageBubble(message: message)
            }
          }
        }
        .padding(24)
      }

      Divider()

      HStack(spacing: 10) {
        TextField("Pair a device in Stage 02 to send a message", text: .constant(""))
          .textFieldStyle(.roundedBorder)
          .disabled(true)
          .accessibilityIdentifier(AccessibilityID.chatComposer.rawValue)
        Button("Send") {}
          .buttonStyle(.borderedProminent)
          .disabled(true)
      }
      .padding(16)
      .background(.bar)
    }
    .navigationTitle("Chat")
    .accessibilityIdentifier(AccessibilityID.chat.rawValue)
  }
}

private struct MessageBubble: View {
  let message: ChatMessage

  var body: some View {
    HStack {
      if message.isFromParent { Spacer(minLength: 80) }
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(message.sender)
            .font(.caption.weight(.semibold))
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
      .frame(maxWidth: 440, alignment: .leading)
      .background(
        message.isFromParent
          ? AnyShapeStyle(Color.accentColor.opacity(0.13)) : AnyShapeStyle(.regularMaterial),
        in: RoundedRectangle(cornerRadius: 13)
      )
      if !message.isFromParent { Spacer(minLength: 80) }
    }
  }
}
