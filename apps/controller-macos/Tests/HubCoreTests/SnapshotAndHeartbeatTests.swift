import Foundation
import Testing

@testable import HubCore

@Suite("Adaptive heartbeat and delta snapshots")
struct SnapshotAndHeartbeatTests {
  @Test("heartbeats back off when idle or constrained")
  func adaptiveIntervals() {
    let policy = AdaptiveHeartbeat(activeInterval: 10, idleInterval: 45, offlineAfter: 60)
    #expect(policy.interval(recentActivity: true, constrained: false) == 10)
    #expect(policy.interval(recentActivity: false, constrained: false) == 45)
    #expect(policy.interval(recentActivity: true, constrained: true) == 45)
  }

  @Test("only changed snapshot fields advance the version")
  func deltaSnapshots() {
    let tracker = DeltaSnapshotTracker()
    let first = tracker.delta(for: ["state": .string("online"), "battery": .integer(90)])
    #expect(first.version == 1)
    #expect(first.changed.count == 2)
    let unchanged = tracker.delta(for: ["state": .string("online"), "battery": .integer(90)])
    #expect(unchanged.version == 1)
    #expect(unchanged.changed.isEmpty)
    let changed = tracker.delta(for: ["state": .string("online"), "battery": .integer(89)])
    #expect(changed.version == 2)
    #expect(changed.changed == ["battery": .integer(89)])
  }
}
