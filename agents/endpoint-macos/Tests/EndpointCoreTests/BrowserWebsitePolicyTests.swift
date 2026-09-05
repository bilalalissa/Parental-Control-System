import Foundation
import HubCore
import XCTest

@testable import EndpointCore

final class BrowserWebsitePolicyTests: XCTestCase {
  func testDomainNormalization() throws {
    let policy = try BrowserWebsitePolicy(
      version: 1, domains: [" YouTube.com ", "youtube.com", "xn--bcher-kva.de"])
    XCTAssertEqual(policy.domains, ["xn--bcher-kva.de", "youtube.com"])
    for bad in [
      "https://example.com", "a.com/path", "a.com?q=x", "127.0.0.1", "a.local", "*.a.com", "a..com",
      "-a.com",
    ] {
      XCTAssertThrowsError(try BrowserWebsitePolicy(version: 1, domains: [bad]))
    }
  }

  func testProtectedPolicySurvivesRestartAndRejectsRollback() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProtectedConfigurationStore(root: root)
    let p = try BrowserWebsitePolicy(version: 2, domains: ["example.com"])
    try store.setBrowserCollection(enabled: false, retentionDays: 7, websitePolicy: p)
    XCTAssertEqual(try ProtectedConfigurationStore(root: root).load().websitePolicy, p)
    XCTAssertThrowsError(
      try store.setBrowserCollection(
        enabled: true, retentionDays: 7,
        websitePolicy: BrowserWebsitePolicy(version: 1, domains: [])))
    try store.setBrowserCollection(enabled: true, retentionDays: 10)
    XCTAssertEqual(try store.load().websitePolicy, p)
    try store.setBrowserCollection(
      enabled: false, retentionDays: 7,
      websitePolicy: BrowserWebsitePolicy(version: 3, domains: []))
    XCTAssertEqual(try store.load().websitePolicy?.domains, [])
  }

  func testCoverageRequiresMatchingVersionAndRecentOnlineReport() {
    let now = Date()
    let r = BrowserProtectionReport(
      browser: "chrome", profile: "synthetic", version: 2, state: "applied", observedAt: now)
    XCTAssertEqual(r.label(expectedVersion: 2, now: now, online: true), "Policy applied")
    XCTAssertEqual(r.label(expectedVersion: 3, now: now, online: true), "Policy pending")
    XCTAssertEqual(r.label(expectedVersion: 2, now: now, online: false), "Not reporting")
    XCTAssertEqual(
      r.label(expectedVersion: 2, now: now.addingTimeInterval(181), online: true), "Not reporting")
  }

  func testFirefoxRequiresItsOwnExtensionAndVendorIdentity() {
    XCTAssertEqual(
      BrowserCallerAuthorization.expectedBrowser(
        origin: BrowserNativeMessaging.firefoxExtensionID,
        executablePath: "/Applications/Firefox.app/Contents/MacOS/firefox",
        signingIdentifier: "org.mozilla.firefox",
        teamIdentifier: "43AQ936H96", signatureValid: true), "firefox")
    XCTAssertNil(
      BrowserCallerAuthorization.expectedBrowser(
        origin: BrowserNativeMessaging.allowedOrigin,
        executablePath: "/Applications/Firefox.app/Contents/MacOS/firefox",
        signingIdentifier: "org.mozilla.firefox",
        teamIdentifier: "43AQ936H96", signatureValid: true))
  }
}
