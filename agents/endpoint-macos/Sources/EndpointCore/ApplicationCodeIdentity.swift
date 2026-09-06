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

/// Immutable process metadata captured before an asynchronous XPC policy lookup. The visible
/// helper must reacquire the process after that lookup and verify that the PID still names the
/// same bundle before it may request termination. This prevents both a dropped weak reference and
/// acting on a reused PID.
public struct ApplicationRestrictionProcessCandidate: Equatable, Sendable {
  public let processIdentifier: Int32
  public let bundleIdentifier: String
  public let bundlePath: String

  public init(processIdentifier: Int32, bundleIdentifier: String, bundleURL: URL) {
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    bundlePath = bundleURL.resolvingSymlinksInPath().path
  }

  public func matchesLiveProcess(bundleIdentifier: String?, bundleURL: URL?) -> Bool {
    guard processIdentifier > 0, bundleIdentifier == self.bundleIdentifier, let bundleURL else {
      return false
    }
    return bundleURL.resolvingSymlinksInPath().path == bundlePath
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
