import Foundation
import Testing

@testable import HubCore

@Suite("Pairing and hub persistence")
struct PairingAndPersistenceTests {
  @Test("pairing code is one-time, expiring, and rate-limited")
  func pairingTicket() throws {
    let coordinator = PairingCoordinator()
    let now = Date()
    _ = coordinator.create(
      host: "127.0.0.1", port: 443, certificateFingerprint: "AA", now: now, code: "123456")
    #expect(throws: PairingError.invalidCode) {
      try coordinator.consume(code: "000000", now: now)
    }
    try coordinator.consume(code: "123456", now: now)
    #expect(throws: PairingError.consumed) {
      try coordinator.consume(code: "123456", now: now)
    }

    _ = coordinator.create(
      host: "127.0.0.1", port: 443, certificateFingerprint: "AA", now: now,
      lifetime: 1, code: "654321")
    #expect(throws: PairingError.expired) {
      try coordinator.consume(code: "654321", now: now.addingTimeInterval(2))
    }
  }

  @Test("paired device and sequence survive database restart")
  func restartPersistence() throws {
    let fixture = try TemporaryHubDatabase()
    defer { fixture.remove() }
    let identity = try Ed25519Identity(keyID: "device-key")
    let pairedAt = Date(timeIntervalSince1970: 1_700_000_000)
    do {
      let database = try HubDatabase(path: fixture.path)
      try database.upsertDevice(
        HubDeviceRecord(
          id: "mock-one",
          name: "Mock One",
          platform: "macOS",
          keyID: identity.keyID,
          publicKey: identity.publicKeyData,
          capabilities: ["presence", "chat"],
          pairedAt: pairedAt,
          lastSeen: pairedAt
        ))
      try database.updateSeen(
        deviceID: "mock-one", sequence: 7, snapshotVersion: 3, now: pairedAt.addingTimeInterval(1))
    }
    let reopened = try HubDatabase(path: fixture.path)
    let persistedDevice = try reopened.device(id: "mock-one")
    let device = try #require(persistedDevice)
    #expect(device.lastSequence == 7)
    #expect(device.snapshotVersion == 3)
    #expect(device.state(now: pairedAt.addingTimeInterval(80)) == .offline)
  }

  @Test("audit, outbound queues, and receipts stay bounded")
  func boundedPersistence() throws {
    let fixture = try TemporaryHubDatabase()
    defer { fixture.remove() }
    let database = try HubDatabase(path: fixture.path)
    for index in 0..<(HubDatabase.maximumAuditRecords + 20) {
      try database.appendAudit(
        HubAuditRecord(event: "test", deviceID: "mock", detail: "record \(index)"))
    }
    for index in 0..<(HubDatabase.maximumQueuedEnvelopesPerDevice + 20) {
      try database.enqueue(
        QueuedEnvelope(
          deviceID: "mock",
          expiresAt: Date().addingTimeInterval(300),
          envelope: Data("message-\(index)".utf8)
        ))
    }
    for index in 0..<(HubDatabase.maximumReceipts + 20) {
      try database.appendReceipt(
        ReceiptRecord(
          deviceID: "mock", originalMessageID: UUID(), state: "accepted",
          timestamp: Date().addingTimeInterval(TimeInterval(index))))
    }
    let counts = try database.counts()
    #expect(counts.audit == HubDatabase.maximumAuditRecords)
    #expect(counts.queued == HubDatabase.maximumQueuedEnvelopesPerDevice)
    #expect(counts.receipts == HubDatabase.maximumReceipts)
  }

  @Test("revocation clears queued traffic and unpair removes the device")
  func revokeAndUnpair() throws {
    let fixture = try TemporaryHubDatabase()
    defer { fixture.remove() }
    let database = try HubDatabase(path: fixture.path)
    let identity = try Ed25519Identity(keyID: "device-key")
    try database.upsertDevice(
      HubDeviceRecord(
        id: "mock-revoke",
        name: "Mock Revoke",
        platform: "mock-macOS",
        keyID: identity.keyID,
        publicKey: identity.publicKeyData,
        capabilities: ["presence"],
        pairedAt: Date(),
        lastSeen: Date()))
    try database.enqueue(
      QueuedEnvelope(
        deviceID: "mock-revoke",
        expiresAt: Date().addingTimeInterval(60),
        envelope: Data("receipt".utf8)))
    try database.revoke(deviceID: "mock-revoke")
    #expect(try database.device(id: "mock-revoke")?.isRevoked == true)
    #expect(try database.queued(deviceID: "mock-revoke").isEmpty)
    try database.unpair(deviceID: "mock-revoke")
    #expect(try database.device(id: "mock-revoke") == nil)
  }

  @Test("chat, activity, retention, and broadcast queues stay bounded")
  func stage04Persistence() throws {
    let fixture = try TemporaryHubDatabase()
    defer { fixture.remove() }
    let database = try HubDatabase(path: fixture.path)
    let identity = try Ed25519Identity(keyID: "device-stage04")
    for id in ["child-one", "child-two"] {
      try database.upsertDevice(
        HubDeviceRecord(
          id: id, name: id, platform: "macOS", keyID: "\(identity.keyID)-\(id)",
          publicKey: identity.publicKeyData, capabilities: ["chat", "app-activity"],
          pairedAt: .distantPast, lastSeen: .distantPast))
    }
    let thread = UUID()
    for id in ["child-one", "child-two"] {
      let message = HubChatMessage(
        deviceID: id, threadID: thread, sender: "Parent", text: "Family check-in",
        state: .queued, audience: .familyGroup, isFromParent: true)
      try database.saveChatMessage(message)
      try database.enqueue(
        QueuedEnvelope(
          deviceID: id, expiresAt: Date().addingTimeInterval(30 * 86_400),
          envelope: Data(message.id.uuidString.utf8)))
    }
    #expect(try database.chatMessages().count == 2)
    #expect(try database.chatMessages().allSatisfy { $0.state == .queued })
    #expect(try database.chatMessages().allSatisfy { $0.threadID == thread })
    let mutable = try #require(try database.chatMessages().first)
    let editedAt = Date()
    try database.mutateParentChatMessage(
      id: mutable.id, text: "Corrected family check-in", editedAt: editedAt, deletedAt: nil)
    #expect(try database.chatMessages().first { $0.id == mutable.id }?.editedAt != nil)
    try database.mutateParentChatMessage(
      id: mutable.id, text: "", editedAt: editedAt, deletedAt: Date())
    let deleted = try #require(try database.chatMessages().first { $0.id == mutable.id })
    #expect(deleted.displayText == "Message deleted")
    #expect(deleted.text.isEmpty)

    try database.saveActivityConfiguration(
      ActivityConfiguration(deviceID: "child-one", enabled: true, retentionDays: 1))
    try database.saveActivity(
      [
        HubAppActivity(
          deviceID: "child-one", bundleIdentifier: "com.example.Editor",
          applicationName: "Editor", isForeground: true,
          observedAt: Date().addingTimeInterval(-2 * 86_400)),
        HubAppActivity(
          deviceID: "child-one", bundleIdentifier: "com.example.Browser",
          applicationName: "Browser", isForeground: false),
      ], for: "child-one")
    try database.pruneActivity(now: Date())
    #expect(try database.activity().map(\.applicationName) == ["Browser"])
    try database.saveActivityConfiguration(
      ActivityConfiguration(deviceID: "child-one", enabled: false, retentionDays: 1))
    #expect(try database.activity().isEmpty)
    #expect(try database.storageSummary().queuedEnvelopes == 2)
  }

  @Test("browser records are bounded, retained briefly, and cleared on disable")
  func stage05BrowserPersistence() throws {
    let fixture = try TemporaryHubDatabase()
    defer { fixture.remove() }
    let database = try HubDatabase(path: fixture.path)
    try database.saveBrowserConfiguration(
      BrowserConfiguration(deviceID: "child-browser", enabled: true, retentionDays: 1))
    let records = (0..<150).map { index in
      HubBrowserTab(
        deviceID: "child-browser", browser: index.isMultiple(of: 2) ? "chrome" : "edge",
        profileID: "synthetic-profile", title: "Tab \(index)",
        origin: "https://example\(index).test", isActive: index == 0,
        observedAt: index == 0 ? Date().addingTimeInterval(-2 * 86_400) : Date())
    }
    try database.replaceBrowserTabs(records, for: "child-browser")
    #expect(try database.browserTabs().count == HubDatabase.maximumBrowserTabsPerDevice)
    try database.pruneActivity(now: Date())
    #expect(try database.browserTabs().allSatisfy { $0.title != "Tab 0" })
    #expect(try database.storageSummary().browserTabRecords == 127)

    try database.saveBrowserConfiguration(
      BrowserConfiguration(deviceID: "child-browser", enabled: false, retentionDays: 7))
    #expect(try database.browserTabs().isEmpty)
    let configuration = try #require(
      database.browserConfigurations().first { $0.deviceID == "child-browser" })
    #expect(configuration.enabled == false)
    #expect(configuration.retentionDays == 7)
  }

  @Test("late delivery callbacks cannot regress read receipts")
  func stage05MonotonicReceipts() throws {
    let fixture = try TemporaryHubDatabase()
    defer { fixture.remove() }
    let database = try HubDatabase(path: fixture.path)
    let message = HubChatMessage(
      deviceID: "child-receipt", sender: "Parent", text: "Synthetic message", state: .sent,
      audience: .direct, isFromParent: true)
    try database.saveChatMessage(message)
    try database.updateChatState(id: message.id, state: .delivered)
    try database.updateChatState(id: message.id, state: .read)
    try database.updateChatState(id: message.id, state: .failed)
    try database.updateChatState(id: message.id, state: .delivered)
    #expect(try database.chatMessages().first?.state == .read)
  }
}

private struct TemporaryHubDatabase {
  let directory: URL
  let path: String

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("parental-control-hub-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    path = directory.appendingPathComponent("hub.sqlite3").path
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}
