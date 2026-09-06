import Foundation
import XCTest

@testable import HubCore

final class BrowserPolicyPersistenceTests: XCTestCase {
  func testCapabilityRefreshValidationRejectsMalformedAndOversizedAnnouncements() throws {
    XCTAssertEqual(
      try LocalHub.validatedCapabilities([
        "capabilities": .array([
          .string("chat"), .string("browser-website-policy"), .string("chat"),
        ])
      ]),
      ["browser-website-policy", "chat"])
    XCTAssertEqual(try LocalHub.validatedCapabilities(["capabilities": .array([])]), [])
    for invalid: [String: JSONValue] in [
      [:], ["capabilities": .string("chat")],
      ["capabilities": .array([.integer(1)])], ["capabilities": .array([.string("")])],
      ["capabilities": .array([.string("invalid capability")])],
      ["capabilities": .array([.string(String(repeating: "a", count: 65))])],
      ["capabilities": .array(Array(repeating: .string("chat"), count: 33))],
    ] {
      XCTAssertThrowsError(try LocalHub.validatedCapabilities(invalid))
    }
  }

  func testCapabilityReplacementPreservesPairingAndCannotReviveRevokedDevice() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try HubDatabase(path: directory.appendingPathComponent("hub.sqlite").path)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let identity = try Ed25519Identity(keyID: "synthetic-key")
    let device = HubDeviceRecord(
      id: "synthetic-child", name: "Synthetic Child", platform: "macOS",
      keyID: identity.keyID, publicKey: identity.publicKeyData, capabilities: ["presence"],
      pairedAt: now, lastSeen: now, lastSequence: 12, snapshotVersion: 9)
    try db.upsertDevice(device)
    try db.refreshCapabilities(deviceID: device.id, capabilities: ["browser-website-policy"])
    let updated = try XCTUnwrap(db.device(id: device.id))
    XCTAssertEqual(updated.capabilities, ["browser-website-policy"])
    XCTAssertEqual(updated.publicKey, device.publicKey)
    XCTAssertEqual(updated.pairedAt, device.pairedAt)
    XCTAssertEqual(updated.lastSequence, device.lastSequence)
    XCTAssertEqual(updated.snapshotVersion, device.snapshotVersion)
    try db.refreshCapabilities(deviceID: device.id, capabilities: [])
    XCTAssertEqual(try db.device(id: device.id)?.capabilities, [])
    try db.revoke(deviceID: device.id)
    try db.refreshCapabilities(deviceID: device.id, capabilities: ["browser-website-policy"])
    XCTAssertEqual(try db.device(id: device.id)?.capabilities, [])
    XCTAssertEqual(try db.device(id: device.id)?.isRevoked, true)
  }

  func testAggregatePoliciesCannotExhaustPairingResponseBudget() throws {
    let domains = (0..<256).map {
      "domain-\($0)-" + String(repeating: "a", count: 45) + ".example.com"
    }
    let policy = try BrowserWebsitePolicy(version: 1, domains: domains)
    let first = BrowserConfiguration(
      deviceID: "synthetic-one", enabled: false, websitePolicy: policy)
    let second = BrowserConfiguration(
      deviceID: "synthetic-two", enabled: false, websitePolicy: policy)
    XCTAssertNoThrow(try BrowserWebsitePolicy.validateStatusBudget([first]))
    XCTAssertThrowsError(try BrowserWebsitePolicy.validateStatusBudget([first, second]))
  }

  func testBrowserConfigurationMigrationAndSharingChangesPreservePolicyAndReports() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("hub.sqlite").path
    let policy = try BrowserWebsitePolicy(version: 5, domains: ["example.com"])
    let report = BrowserProtectionReport(
      browser: "firefox", profile: "test-profile", version: 5,
      state: "applied", observedAt: Date(timeIntervalSince1970: 1_700_000_000))
    do {
      let db = try HubDatabase(path: path)
      try db.saveBrowserConfiguration(
        BrowserConfiguration(
          deviceID: "synthetic-child", enabled: true,
          websitePolicy: policy))
      try db.saveBrowserProtectionReports([report], deviceID: "synthetic-child")
      try db.saveBrowserConfiguration(
        BrowserConfiguration(deviceID: "synthetic-child", enabled: false))
    }
    let db = try HubDatabase(path: path)
    let restored = try XCTUnwrap(db.browserConfigurations().first)
    XCTAssertEqual(restored.websitePolicy, policy)
    XCTAssertEqual(restored.protectionReports, [report])
    XCTAssertFalse(restored.enabled)
  }
}
