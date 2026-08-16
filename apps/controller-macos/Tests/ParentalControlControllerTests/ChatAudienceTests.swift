import Foundation
import HubCore
import Testing

@testable import ParentalControlController

@Suite("Chat audiences")
struct ChatAudienceTests {
  @Test("direct chat targets only the selected device")
  func directRecipient() {
    let devices = fixtures
    let recipients = ChatAudienceMode.direct.recipients(
      from: devices, selectedDeviceID: devices[1].id)
    #expect(recipients.map(\.id) == [devices[1].id])
  }

  @Test("group chat and announcements target every child device")
  func broadcastRecipients() {
    let devices = fixtures
    #expect(
      ChatAudienceMode.familyGroup.recipients(from: devices, selectedDeviceID: nil).map(\.id)
        == devices.map(\.id))
    #expect(
      ChatAudienceMode.announcement.recipients(from: devices, selectedDeviceID: nil).map(\.id)
        == devices.map(\.id))
  }

  @Test("unread badge counts only incoming messages that are not read")
  func unreadCount() {
    let incoming = HubChatMessage(
      deviceID: "child", sender: "Child", text: "One", state: .delivered,
      audience: .direct, isFromParent: false)
    let read = HubChatMessage(
      deviceID: "child", sender: "Child", text: "Two", state: .read,
      audience: .direct, isFromParent: false)
    let outgoing = HubChatMessage(
      deviceID: "child", sender: "Parent", text: "Three", state: .delivered,
      audience: .direct, isFromParent: true)

    #expect([incoming, read, outgoing].filter(\.isUnreadForParent).count == 1)
  }

  private var fixtures: [ManagedDevice] {
    [
      ManagedDevice(
        id: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
        name: "Child Mac",
        platform: .macOS,
        model: "Synthetic",
        operatingSystem: "macOS",
        architecture: "arm64",
        connectionState: .online,
        lastSeen: .distantPast,
        currentAllowance: "Preview",
        capabilities: [],
        limitations: []
      ),
      ManagedDevice(
        id: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!,
        name: "Child iPad",
        platform: .iPadOS,
        model: "Synthetic",
        operatingSystem: "iPadOS",
        architecture: "arm64",
        connectionState: .approximate,
        lastSeen: .distantPast,
        currentAllowance: "Preview",
        capabilities: [],
        limitations: []
      ),
    ]
  }
}
