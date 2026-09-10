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
    return identity(from: staticCode)
  }

  /// Validates the code object that is actually running. Self-updating launchers may have a
  /// signing identifier that differs from their bundle identifier, and validating the live code
  /// avoids treating a mutable display name or path as identity.
  public static func validated(
    processIdentifier: pid_t, at bundleURL: URL
  ) -> ApplicationCodeIdentity? {
    guard processIdentifier > 0 else { return nil }
    let attributes = [kSecGuestAttributePid as String: NSNumber(value: processIdentifier)]
    var code: SecCode?
    guard
      SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, SecCSFlags(), &code)
        == errSecSuccess,
      let code,
      SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess,
      let staticCode = staticCode(for: code),
      let runningURL = codePath(staticCode)
    else { return nil }
    let runningPath = runningURL.resolvingSymlinksInPath().path
    let bundlePath = bundleURL.resolvingSymlinksInPath().path
    guard runningPath == bundlePath || runningPath.hasPrefix(bundlePath + "/") else { return nil }
    return identity(from: staticCode)
  }

  private static func staticCode(for code: SecCode) -> SecStaticCode? {
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess else {
      return nil
    }
    return staticCode
  }

  private static func codePath(_ code: SecStaticCode) -> URL? {
    var path: CFURL?
    guard SecCodeCopyPath(code, SecCSFlags(), &path) == errSecSuccess else { return nil }
    return path as URL?
  }

  private static func identity(from staticCode: SecStaticCode) -> ApplicationCodeIdentity? {
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
    policy: ApplicationRestrictionPolicy?, expectedPolicyVersion: Int64? = nil
  ) -> ApplicationRestrictionRule? {
    guard !ApplicationRestrictionRule.isProtected(bundleIdentifier),
      let identity, let policy,
      expectedPolicyVersion.map({ $0 == policy.version }) ?? true,
      let rule = policy.rule(for: bundleIdentifier),
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
