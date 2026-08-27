import Foundation
import Testing

@testable import EndpointCore

@Suite("incoming message notifications")
struct IncomingMessageNotificationTrackerTests {
  @Test("existing history is primed and each later parent message alerts once")
  func newParentMessagesOnly() {
    let existing = EndpointChatMessage(
      sender: "Parent", text: "Existing", state: .delivered, isFromParent: true)
    let child = EndpointChatMessage(
      sender: "Child", text: "Reply", state: .sent, isFromParent: false)
    var tracker = IncomingMessageNotificationTracker()

    #expect(tracker.newlyReceivedMessages(in: [existing, child]).isEmpty)
    #expect(tracker.newlyReceivedMessages(in: [existing, child]).isEmpty)

    let incoming = EndpointChatMessage(
      sender: "Parent", text: "New", state: .delivered, isFromParent: true)
    #expect(
      tracker.newlyReceivedMessages(in: [existing, child, incoming]).map(\.id) == [incoming.id])
    #expect(tracker.newlyReceivedMessages(in: [existing, child, incoming]).isEmpty)

    var edited = incoming
    edited.text = "Edited"
    edited.editedAt = Date()
    #expect(tracker.newlyReceivedMessages(in: [existing, child, edited]).isEmpty)
  }
}
