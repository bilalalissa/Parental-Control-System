import Foundation

public enum ApplicationRestrictionPolicyError: Error, Equatable, CustomStringConvertible {
  case invalidVersion
  case tooManyRules
  case invalidBundleIdentifier
  case protectedApplication
  case unsignedApplication
  case duplicateRule
  case configurationTooLarge

  public var description: String {
    switch self {
    case .invalidVersion: "The application restriction policy version must be positive."
    case .tooManyRules: "At most 32 applications may be restricted."
    case .invalidBundleIdentifier: "A rule has an invalid application bundle identifier."
    case .protectedApplication: "System and parental-control applications cannot be restricted."
    case .unsignedApplication:
      "Only applications with a validated signing identity may be restricted."
    case .duplicateRule: "Each application may appear only once."
    case .configurationTooLarge: "The application restriction configuration is too large."
    }
  }
}

public struct ApplicationRestrictionRule: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var id: String { bundleIdentifier }
  public let bundleIdentifier: String
  public let signingIdentifier: String
  public let teamIdentifier: String
  public let applicationName: String

  public init(
    bundleIdentifier: String, signingIdentifier: String, teamIdentifier: String,
    applicationName: String
  ) throws {
    self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    self.signingIdentifier = signingIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    self.teamIdentifier = teamIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    self.applicationName = String(
      applicationName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    try validate()
  }

  public func validate() throws {
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
    guard !bundleIdentifier.isEmpty, bundleIdentifier.utf8.count <= 200,
      bundleIdentifier.contains("."),
      bundleIdentifier.unicodeScalars.allSatisfy(allowed.contains),
      signingIdentifier == bundleIdentifier
    else { throw ApplicationRestrictionPolicyError.invalidBundleIdentifier }
    guard !Self.isProtected(bundleIdentifier) else {
      throw ApplicationRestrictionPolicyError.protectedApplication
    }
    guard !teamIdentifier.isEmpty, teamIdentifier.utf8.count <= 64,
      teamIdentifier.utf8.allSatisfy({ byte in
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
      })
    else { throw ApplicationRestrictionPolicyError.unsignedApplication }
  }

  public static func isProtected(_ bundleIdentifier: String) -> Bool {
    bundleIdentifier.hasPrefix("com.apple.")
      || bundleIdentifier.hasPrefix("com.bilalalissa.")
      || bundleIdentifier == "com.apple.loginwindow"
      || bundleIdentifier == "com.apple.finder"
      || bundleIdentifier == "com.apple.dock"
  }
}

public struct ApplicationRestrictionPolicy: Codable, Equatable, Sendable {
  public static let maximumRules = 32
  public static let maximumEncodedBytes = 12 * 1_024
  public let version: Int64
  public let rules: [ApplicationRestrictionRule]

  public init(version: Int64, rules: [ApplicationRestrictionRule]) throws {
    self.version = version
    self.rules = rules.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    try validate()
  }

  public func validated() throws -> Self {
    try validate()
    return self
  }

  public func rule(for bundleIdentifier: String) -> ApplicationRestrictionRule? {
    rules.first { $0.bundleIdentifier == bundleIdentifier }
  }

  public static func validateStatusBudget(_ configurations: [ActivityConfiguration]) throws {
    guard try JSONEncoder().encode(configurations).count <= 20 * 1_024 else {
      throw ApplicationRestrictionPolicyError.configurationTooLarge
    }
  }

  private func validate() throws {
    guard version > 0, version <= 9_007_199_254_740_991 else {
      throw ApplicationRestrictionPolicyError.invalidVersion
    }
    guard rules.count <= Self.maximumRules else {
      throw ApplicationRestrictionPolicyError.tooManyRules
    }
    for rule in rules { try rule.validate() }
    guard Set(rules.map(\.bundleIdentifier)).count == rules.count else {
      throw ApplicationRestrictionPolicyError.duplicateRule
    }
    guard try JSONEncoder().encode(self).count <= Self.maximumEncodedBytes else {
      throw ApplicationRestrictionPolicyError.configurationTooLarge
    }
  }
}
