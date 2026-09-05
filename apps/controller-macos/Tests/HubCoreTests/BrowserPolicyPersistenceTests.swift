import Foundation
import XCTest

@testable import HubCore

final class BrowserPolicyPersistenceTests: XCTestCase {
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
