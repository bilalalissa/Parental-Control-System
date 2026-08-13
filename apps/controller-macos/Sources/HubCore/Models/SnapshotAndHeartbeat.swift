import Foundation

public struct AdaptiveHeartbeat: Sendable {
  public let activeInterval: TimeInterval
  public let idleInterval: TimeInterval
  public let offlineAfter: TimeInterval

  public init(
    activeInterval: TimeInterval = 15,
    idleInterval: TimeInterval = 60,
    offlineAfter: TimeInterval = 75
  ) {
    self.activeInterval = activeInterval
    self.idleInterval = idleInterval
    self.offlineAfter = offlineAfter
  }

  public func interval(recentActivity: Bool, constrained: Bool) -> TimeInterval {
    constrained || !recentActivity ? idleInterval : activeInterval
  }
}

public final class DeltaSnapshotTracker: @unchecked Sendable {
  private let lock = NSLock()
  private var previous: [String: JSONValue] = [:]
  private var version: UInt64 = 0

  public init() {}

  public func delta(for snapshot: [String: JSONValue]) -> (
    version: UInt64, changed: [String: JSONValue]
  ) {
    lock.lock()
    defer { lock.unlock() }
    var changed: [String: JSONValue] = [:]
    for (key, value) in snapshot where previous[key] != value { changed[key] = value }
    for key in previous.keys where snapshot[key] == nil { changed[key] = .null }
    if !changed.isEmpty {
      version += 1
      previous = snapshot
    }
    return (version, changed)
  }
}
