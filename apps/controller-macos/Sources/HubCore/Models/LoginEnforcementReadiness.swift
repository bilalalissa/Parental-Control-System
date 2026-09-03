import Foundation

public enum HubLoginEnforcementCapability: String, Codable, CaseIterable, Sendable {
  case session = "session-enforcement"
  case managedIdentity = "managed-identity-login"
}

public struct HubLoginEnforcementReadiness: Equatable, Sendable {
  public let sessionEnforcementAvailable: Bool
  public let managedIdentityConfigured: Bool

  public init<S: Sequence>(capabilities: S) where S.Element == String {
    let values = Set(capabilities)
    sessionEnforcementAvailable =
      values.contains(HubLoginEnforcementCapability.session.rawValue)
      || (values.contains("signed-policy") && values.contains("offline-enforcement")
        && values.contains("lock"))
    managedIdentityConfigured = values.contains(
      HubLoginEnforcementCapability.managedIdentity.rawValue)
  }

  public static let currentMacEndpoint = HubLoginEnforcementReadiness(
    capabilities: [HubLoginEnforcementCapability.session.rawValue])
}
