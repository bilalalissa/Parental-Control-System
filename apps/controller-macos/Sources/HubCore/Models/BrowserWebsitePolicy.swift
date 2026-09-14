import Foundation

/// Domain-only browser rules, transported in an authenticated controller envelope.
public struct BrowserWebsitePolicy: Codable, Equatable, Sendable {
  public let version: Int64
  public let domains: [String]
  /// Browser/profile report identities that an adult explicitly retired after removing a
  /// profile or reinstalling its extension. This never gets inferred from app installation or
  /// heartbeat age: a stale enrolled profile remains a visible protection gap until an adult
  /// confirms that it no longer needs coverage.
  public let retiredReportIDs: [String]

  public init(version: Int64, domains: [String], retiredReportIDs: [String] = []) throws {
    guard version > 0, version <= 9_007_199_254_740_991, domains.count <= 256,
      domains.reduce(0, { $0 + $1.utf8.count }) <= 32_768,
      retiredReportIDs.count <= 32,
      retiredReportIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 121 }),
      retiredReportIDs.reduce(0, { $0 + $1.utf8.count }) <= 3_872
    else {
      throw BrowserPolicyError.invalidPolicy
    }
    self.version = version
    self.domains = try Array(Set(domains.map(Self.normalize))).sorted()
    self.retiredReportIDs = Array(Set(retiredReportIDs)).sorted()
  }

  public func validated() throws -> Self {
    try Self(version: version, domains: domains, retiredReportIDs: retiredReportIDs)
  }

  private enum CodingKeys: String, CodingKey { case version, domains, retiredReportIDs }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      version: values.decode(Int64.self, forKey: .version),
      domains: values.decode([String].self, forKey: .domains),
      retiredReportIDs: values.decodeIfPresent([String].self, forKey: .retiredReportIDs) ?? [])
  }

  /// Leave room for authenticated status metadata and pairing responses within 64 KiB.
  /// Never truncate an editable policy: reject an oversized aggregate before persistence.
  public static func validateStatusBudget(_ configurations: [BrowserConfiguration]) throws {
    let policies = configurations.map {
      BrowserConfiguration(
        deviceID: $0.deviceID, enabled: $0.enabled,
        retentionDays: $0.retentionDays, websitePolicy: $0.websitePolicy)
    }
    guard try JSONEncoder().encode(policies).count <= 24 * 1024 else {
      throw BrowserPolicyError.statusBudgetExceeded
    }
  }

  public static func normalize(_ input: String) throws -> String {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let labels = value.split(separator: ".", omittingEmptySubsequences: false)
    guard value.utf8.count <= 253, labels.count >= 2,
      labels.allSatisfy({ label in
        !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
          && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
      }), labels.last!.utf8.contains(where: { (97...122).contains($0) }),
      !value.hasSuffix(".local"), !value.hasSuffix(".localhost")
    else { throw BrowserPolicyError.invalidDomain }
    return value
  }
}

public enum BrowserPolicyError: Error {
  case invalidDomain, invalidPolicy, stalePolicy, statusBudgetExceeded
}

public struct BrowserProtectionReport: Codable, Equatable, Identifiable, Sendable {
  public var id: String { "\(browser)|\(profile)" }
  public let browser: String
  public let profile: String
  public let version: Int64?
  public let state: String
  public let observedAt: Date

  public init(browser: String, profile: String, version: Int64?, state: String, observedAt: Date) {
    self.browser = String(browser.prefix(40))
    self.profile = String(profile.prefix(80))
    self.version = version
    self.state =
      ["applied", "error", "setup-required", "unsupported"].contains(state) ? state : "error"
    self.observedAt = observedAt
  }

  public func label(expectedVersion: Int64?, now: Date, online: Bool) -> String {
    if !online { return "Device offline" }
    if state == "unsupported" { return "Unsupported" }
    if state == "setup-required" { return "Setup required" }
    let recent = isRecent(now: now)
    if state == "error" { return "Application failed" }
    guard let expectedVersion, version == expectedVersion else {
      return recent ? "Policy pending" : "Not reporting current policy"
    }
    return recent ? "Policy applied" : "Not reporting"
  }

  public func requiresAdultAttention(expectedVersion: Int64?, now: Date, online: Bool) -> Bool {
    guard online, let expectedVersion else { return false }
    return state != "applied" || version != expectedVersion || !isRecent(now: now)
  }

  private func isRecent(now: Date) -> Bool {
    now.timeIntervalSince(observedAt) < 180 && observedAt.timeIntervalSince(now) < 120
  }
}

public enum BrowserProtectionCoverage {
  /// Empty profile identifiers were synthesized by RC7 from application installation paths.
  /// They never proved that a browser profile or extension existed and must not drive coverage.
  public static func enrolledReports(
    _ reports: [BrowserProtectionReport], retiredReportIDs: [String] = []
  )
    -> [BrowserProtectionReport]
  {
    let retired = Set(retiredReportIDs)
    return Array(reports.filter { !$0.profile.isEmpty && !retired.contains($0.id) }.suffix(24))
  }

  public static func hasProtectionGap(
    reports: [BrowserProtectionReport], expectedVersion: Int64?, now: Date, online: Bool
  ) -> Bool {
    guard online, expectedVersion != nil else { return false }
    let enrolled = reports
    guard !enrolled.isEmpty else { return true }
    return enrolled.contains {
      $0.requiresAdultAttention(expectedVersion: expectedVersion, now: now, online: online)
    }
  }

}
