import Testing

@testable import HubCore

@Suite("login enforcement readiness")
struct LoginEnforcementReadinessTests {
  @Test("current endpoint reports session enforcement without claiming pre-login control")
  func currentEndpoint() {
    let readiness = HubLoginEnforcementReadiness.currentMacEndpoint

    #expect(readiness.sessionEnforcementAvailable)
    #expect(!readiness.managedIdentityConfigured)
  }

  @Test("legacy Stage 06 capabilities retain truthful transition status")
  func legacyFallback() {
    let readiness = HubLoginEnforcementReadiness(
      capabilities: ["signed-policy", "offline-enforcement", "lock"])

    #expect(readiness.sessionEnforcementAvailable)
    #expect(!readiness.managedIdentityConfigured)
  }

  @Test("managed identity remains a distinct future capability")
  func managedIdentityCapability() {
    let readiness = HubLoginEnforcementReadiness(
      capabilities: HubLoginEnforcementCapability.allCases.map(\.rawValue))

    #expect(readiness.sessionEnforcementAvailable)
    #expect(readiness.managedIdentityConfigured)
  }
}
