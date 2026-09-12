import Darwin
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
    XCTAssertEqual(r.label(expectedVersion: 2, now: now, online: false), "Device offline")
    XCTAssertEqual(
      r.label(expectedVersion: 2, now: now.addingTimeInterval(181), online: true),
      "Not reporting")
  }

  func testInstalledBrowserPathDoesNotInventAnEnrolledProfile() {
    XCTAssertTrue(BrowserCoverageInventory.reports([]).isEmpty)
  }

  func testStaleAcknowledgementRemainsAGapUntilAdultRetiresIt() throws {
    let now = Date()
    let fresh = BrowserProtectionReport(
      browser: "arc", profile: "current", version: 7, state: "applied", observedAt: now)
    let old = BrowserProtectionReport(
      browser: "arc", profile: "retired", version: 7, state: "applied",
      observedAt: now.addingTimeInterval(-3_600))
    let inferred = BrowserProtectionReport(
      browser: "safari", profile: "", version: nil, state: "setup-required", observedAt: now)
    let reports = BrowserCoverageInventory.reports([fresh, old, inferred], now: now)

    XCTAssertEqual(reports.map(\.profile), ["current", "retired"])
    XCTAssertTrue(
      BrowserProtectionCoverage.hasProtectionGap(
        reports: reports, expectedVersion: 7, now: now, online: true))
    let policy = try BrowserWebsitePolicy(
      version: 8, domains: ["example.com"], retiredReportIDs: [old.id])
    let active = BrowserProtectionCoverage.enrolledReports(
      reports, retiredReportIDs: policy.retiredReportIDs)
    XCTAssertEqual(active.map(\.profile), ["current"])
    XCTAssertFalse(
      BrowserProtectionCoverage.hasProtectionGap(
        reports: active, expectedVersion: 7, now: now, online: true))
  }

  func testOlderPolicyDecodesWithNoRetiredReports() throws {
    let data = Data(#"{"version":7,"domains":["example.com"]}"#.utf8)
    let policy = try JSONDecoder().decode(BrowserWebsitePolicy.self, from: data)
    XCTAssertEqual(policy.retiredReportIDs, [])
  }

  func testErrorAndVersionMismatchStillRequireAttention() {
    let now = Date()
    for report in [
      BrowserProtectionReport(
        browser: "arc", profile: "error", version: 7, state: "error", observedAt: now),
      BrowserProtectionReport(
        browser: "arc", profile: "old-policy", version: 6, state: "applied", observedAt: now),
    ] {
      XCTAssertTrue(
        BrowserProtectionCoverage.hasProtectionGap(
          reports: [report], expectedVersion: 7, now: now, online: true))
    }
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

  func testBrowserParentPathUsesKernelProcessMetadata() {
    let expected = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    XCTAssertEqual(BrowserProcessInspector.processPath(pid: getpid()), expected)
    XCTAssertNil(BrowserProcessInspector.processPath(pid: -1))
  }

  func testInstalledArcStaticIdentityIsRecognizedWhenAvailable() throws {
    let executable = "/Applications/Arc.app/Contents/MacOS/Arc"
    guard FileManager.default.fileExists(atPath: executable) else {
      throw XCTSkip("Arc is not installed on this test host")
    }
    guard let identity = BrowserProcessInspector.signingIdentity(path: executable) else {
      throw XCTSkip("Installed Arc copy does not currently pass static code-signature validation")
    }
    XCTAssertEqual(identity.signingIdentifier, "company.thebrowser.Browser")
    XCTAssertEqual(identity.teamIdentifier, "S6N382Y83G")
    XCTAssertEqual(
      BrowserCallerAuthorization.expectedBrowser(
        origin: BrowserNativeMessaging.allowedOrigin,
        executablePath: identity.executablePath,
        signingIdentifier: identity.signingIdentifier,
        teamIdentifier: identity.teamIdentifier,
        signatureValid: true),
      "arc")
  }
}
