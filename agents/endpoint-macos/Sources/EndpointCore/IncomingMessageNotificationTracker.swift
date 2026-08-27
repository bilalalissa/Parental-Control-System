import Foundation

public struct IncomingMessageNotificationTracker: Sendable {
  private var knownParentMessageIDs: Set<UUID> = []
  private var hasLoadedMessages = false

  public init() {}

  public mutating func newlyReceivedMessages(
    in messages: [EndpointChatMessage]
  ) -> [EndpointChatMessage] {
    let parentMessages = messages.filter { $0.isFromParent && $0.deletedAt == nil }
    let currentIDs = Set(parentMessages.map(\.id))
    defer {
      knownParentMessageIDs = currentIDs
      hasLoadedMessages = true
    }
    guard hasLoadedMessages else { return [] }
    return parentMessages.filter { !knownParentMessageIDs.contains($0.id) }
  }
}
