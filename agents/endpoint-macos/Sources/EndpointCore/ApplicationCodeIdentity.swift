import Foundation
import HubCore
import Security

public struct ApplicationCodeIdentity: Codable, Equatable, Sendable {
  public let signingIdentifier: String
  public let teamIdentifier: String

  public init(signingIdentifier: String, teamIdentifier: String) {
    self.signingIdentifier = String(signingIdentifier.prefix(200))
    self.teamIdentifier = String(teamIdentifier.prefix(64))
  }

  public static func validated(at bundleURL: URL) -> ApplicationCodeIdentity? {
    var staticCode: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode,
      SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), nil)
        == errSecSuccess
    else { return nil }
    var rawInformation: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &rawInformation)
        == errSecSuccess,
      let information = rawInformation as? [String: Any],
      let signingIdentifier = information[kSecCodeInfoIdentifier as String] as? String,
      let teamIdentifier = information[kSecCodeInfoTeamIdentifier as String] as? String,
      !signingIdentifier.isEmpty, !teamIdentifier.isEmpty
    else { return nil }
    return ApplicationCodeIdentity(
      signingIdentifier: signingIdentifier, teamIdentifier: teamIdentifier)
  }
}

public enum ApplicationRestrictionEvaluator {
  public static func matches(
    bundleIdentifier: String, identity: ApplicationCodeIdentity?,
    policy: ApplicationRestrictionPolicy?
  ) -> ApplicationRestrictionRule? {
    guard !ApplicationRestrictionRule.isProtected(bundleIdentifier),
      let identity, let rule = policy?.rule(for: bundleIdentifier),
      identity.signingIdentifier == rule.signingIdentifier,
      identity.teamIdentifier == rule.teamIdentifier
    else { return nil }
    return rule
  }
}

public struct ApplicationRestrictionAttemptGate: Sendable {
  private var handledPolicyVersions: [Int32: Int64] = [:]

  public init() {}

  public mutating func begin(processIdentifier: Int32, policyVersion: Int64) -> Bool {
    guard processIdentifier > 0, policyVersion > 0,
      handledPolicyVersions[processIdentifier] != policyVersion
    else { return false }
    handledPolicyVersions[processIdentifier] = policyVersion
    return true
  }

  public mutating func processDidTerminate(_ processIdentifier: Int32) {
    handledPolicyVersions.removeValue(forKey: processIdentifier)
  }

  public func isCurrent(processIdentifier: Int32, policyVersion: Int64) -> Bool {
    handledPolicyVersions[processIdentifier] == policyVersion
  }
}
