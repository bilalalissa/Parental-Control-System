import Foundation
import HubCore
import Testing

@testable import ParentalControlController

@Suite("Controller derived state")
@MainActor
struct ControllerDerivedStateTests {
  @Test("presence ages offline on the observable controller clock")
  func presenceAgesOffline() throws {
    let fixture = try TemporaryControllerDatabase()
    defer { fixture.remove() }
    let store = try ControllerStore(database: ControllerDatabase(path: fixture.path))
    let lastSeen = Date(timeIntervalSince1970: 1_800_000_000)
    store.hubStatus = status(
      devices: [device(id: "active", lastSeen: lastSeen)], requests: [])

    store.presenceNow = lastSeen.addingTimeInterval(30)
    #expect(store.onlineDeviceCount == 1)
    #expect(store.offlineDeviceCount == 0)

    store.presenceNow = lastSeen.addingTimeInterval(76)
    #expect(store.onlineDeviceCount == 0)
    #expect(store.offlineDeviceCount == 1)
  }

  @Test("request badges count only active paired devices")
  func requestBadgesExcludeOrphansAndRevokedDevices() throws {
    let fixture = try TemporaryControllerDatabase()
    defer { fixture.remove() }
    let store = try ControllerStore(database: ControllerDatabase(path: fixture.path))
    let active = device(id: "active", lastSeen: Date())
    let revoked = device(id: "revoked", lastSeen: Date(), isRevoked: true)
    store.hubStatus = status(
      devices: [active, revoked],
      requests: [
        MoreTimeRequestRecord(
          deviceID: active.id, requestedMinutes: 15, note: "Active synthetic request"),
        MoreTimeRequestRecord(
          deviceID: "orphan", requestedMinutes: 20, note: "Orphan synthetic request"),
        MoreTimeRequestRecord(
          deviceID: revoked.id, requestedMinutes: 25, note: "Revoked synthetic request"),
      ])

    #expect(store.pendingTimeRequestCount == 1)
    #expect(store.pendingTimeRequestCount(deviceID: active.id) == 1)
    #expect(store.pendingTimeRequestCount(deviceID: revoked.id) == 0)
  }

  @Test("three-column minimum widths fit inside the minimum window")
  func threeColumnLayoutBudget() {
    #expect(ControllerLayout.navigationSidebarMinimum <= ControllerLayout.navigationSidebarIdeal)
    #expect(ControllerLayout.navigationSidebarIdeal <= ControllerLayout.navigationSidebarMaximum)
    #expect(ControllerLayout.deviceListMinimum <= ControllerLayout.deviceListIdeal)
    #expect(ControllerLayout.deviceListIdeal <= ControllerLayout.deviceListMaximum)
    #expect(ControllerLayout.requiredThreeColumnWidth <= ControllerLayout.minimumWindowWidth)
  }

  private func status(
    devices: [HubDeviceRecord], requests: [MoreTimeRequestRecord]
  ) -> LocalHubStatus {
    LocalHubStatus(
      port: 0, certificateFingerprint: "synthetic", devices: devices, invitation: nil,
      moreTimeRequests: requests)
  }

  private func device(
    id: String, lastSeen: Date, isRevoked: Bool = false
  ) -> HubDeviceRecord {
    HubDeviceRecord(
      id: id, name: "Synthetic \(id)", platform: "macOS", keyID: "key-\(id)",
      publicKey: Data(repeating: 7, count: 32), capabilities: ["presence"],
      pairedAt: lastSeen, lastSeen: lastSeen, isRevoked: isRevoked)
  }
}

private struct TemporaryControllerDatabase {
  let directory: URL
  let path: String

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    path = directory.appendingPathComponent("controller.sqlite3").path
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}
