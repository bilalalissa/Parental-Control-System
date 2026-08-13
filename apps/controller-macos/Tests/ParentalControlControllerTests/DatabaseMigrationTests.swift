import Foundation
import Testing

@testable import ParentalControlController

@Suite("SQLite migrations")
struct DatabaseMigrationTests {
  @Test("all migrations apply once and remain idempotent")
  func migrationsAreIdempotent() throws {
    let fixture = try TemporaryDatabase()
    defer { fixture.remove() }
    let database = try ControllerDatabase(path: fixture.path)

    try database.migrate()
    try database.migrate()

    #expect(
      try database.appliedMigrationVersions() == Set(1...ControllerDatabase.currentSchemaVersion))
  }

  @Test("synthetic data covers distinct platform capabilities")
  func syntheticCapabilityCombinations() throws {
    let fixture = try TemporaryDatabase()
    defer { fixture.remove() }
    let database = try ControllerDatabase(path: fixture.path)
    try database.migrate()
    try database.seedSyntheticDataIfNeeded()
    try database.seedSyntheticDataIfNeeded()

    let devices = try database.loadDevices()
    #expect(devices.count == 3)
    #expect(devices.contains { $0.platform == .macOS && $0.capabilities.contains(.appActivity) })
    #expect(devices.contains { $0.platform == .windows && $0.connectionState == .offline })

    let iPad = try #require(devices.first { $0.platform == .iPadOS })
    #expect(iPad.connectionState == .approximate)
    #expect(iPad.capabilities.contains(.approximatePresence))
    #expect(!iPad.capabilities.contains(.appActivity))
    #expect(!iPad.capabilities.contains(.browserTabs))
    #expect(!iPad.capabilities.contains(.shutdown))
  }

  @Test("schedule revisions round-trip and stay bounded")
  func scheduleRoundTripAndBound() throws {
    let fixture = try TemporaryDatabase()
    defer { fixture.remove() }
    let database = try ControllerDatabase(path: fixture.path)
    try database.migrate()

    var expected = ScheduleDraft.standard
    for revision in 1...25 {
      expected.dailyQuotaMinutes = revision * 15
      try database.saveSchedule(expected)
    }

    #expect(try database.latestSchedule() == expected)
    let snapshot = try database.storageSnapshot()
    #expect(snapshot.deviceCount == 0)
  }
}

private struct TemporaryDatabase {
  let directory: URL
  let path: String

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("parental-control-db-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    path = directory.appendingPathComponent("controller.sqlite3").path
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}
