import CryptoKit
import Foundation
import Testing

@testable import HubCore

@Suite("Signed policy evaluation")
struct PolicyEngineTests {
  private let iso = ISO8601DateFormatter()

  @Test("golden precedence and time-zone vectors")
  func goldenVectors() throws {
    let policy = basePolicy()
    let values: [(String, Int, Bool, PolicyAction?, PolicyDecisionKind, PolicyDecisionSource)] = [
      ("2026-01-13T00:30:00Z", 200, true, .shutdown, .allow, .adultOverride),
      ("2026-01-12T16:00:00Z", 5, false, .lock, .block, .immediateCommand),
      ("2026-01-14T03:30:00Z", 20, false, nil, .allow, .exception),
      ("2026-01-13T00:30:00Z", 20, false, nil, .block, .blockedInterval),
      ("2026-01-12T16:00:00Z", 125, false, nil, .allow, .weeklyWindow),
      ("2026-01-12T16:00:00Z", 135, false, nil, .block, .dailyQuota),
      ("2026-01-17T06:30:00Z", 30, false, nil, .allow, .weeklyWindow),
      ("2026-01-15T16:00:00Z", 0, false, nil, .block, .defaultPolicy),
    ]
    for value in values {
      let result = PolicyEvaluator.evaluate(
        policy,
        input: PolicyEvaluationInput(
          at: try #require(iso.date(from: value.0)), activeUseMinutes: value.1,
          adultOverrideActive: value.2, immediateAction: value.3))
      #expect(result.decision == value.4)
      #expect(result.source == value.5)
    }

    let eastern = ParentalControlPolicy(
      policyID: policy.policyID, version: policy.version, deviceID: policy.deviceID,
      timezone: "America/New_York", effectiveAt: policy.effectiveAt, expiresAt: policy.expiresAt,
      defaultAction: policy.defaultAction, warningOffsetsMinutes: policy.warningOffsetsMinutes,
      gracePeriodSeconds: policy.gracePeriodSeconds, weeklyAllowed: policy.weeklyAllowed,
      blockedIntervals: policy.blockedIntervals, exceptions: policy.exceptions,
      dailyQuotaMinutes: policy.dailyQuotaMinutes, bonusMinutes: policy.bonusMinutes,
      childExplanation: policy.childExplanation, signature: policy.signature)
    let dst = PolicyEvaluator.evaluate(
      eastern,
      input: PolicyEvaluationInput(
        at: try #require(iso.date(from: "2026-03-08T07:30:00Z")), activeUseMinutes: 30))
    #expect(dst.source == .weeklyWindow)
  }

  @Test("policy signature rejects tampering and a different key")
  func signatureVerification() throws {
    let identity = try Ed25519Identity(keyID: "controller-test-key")
    let signed = try identity.sign(policy: basePolicy(keyID: identity.keyID))
    try PolicyCodec.verify(
      signed, publicKey: identity.publicKeyData, expectedKeyID: identity.keyID)

    let tampered = signed.replacing(bonusMinutes: signed.bonusMinutes + 60)
    #expect(throws: PolicySignatureError.self) {
      try PolicyCodec.verify(
        tampered, publicKey: identity.publicKeyData, expectedKeyID: identity.keyID)
    }
    let other = try Ed25519Identity(keyID: "other-controller-key")
    #expect(throws: PolicySignatureError.self) {
      try PolicyCodec.verify(
        signed, publicKey: other.publicKeyData, expectedKeyID: identity.keyID)
    }
  }

  @Test("warning offsets are bounded and issued once")
  func warningTiming() {
    let policy = basePolicy()
    #expect(PolicyEvaluator.warningOffset(policy, remainingMinutes: 15, alreadyIssued: []) == 15)
    #expect(PolicyEvaluator.warningOffset(policy, remainingMinutes: 5, alreadyIssued: [15]) == 5)
    #expect(
      PolicyEvaluator.warningOffset(policy, remainingMinutes: 5, alreadyIssued: [15, 5]) == nil)
    #expect(
      PolicyEvaluator.warningOffset(policy, remainingMinutes: 1, alreadyIssued: [15, 5]) == 1)
    #expect(
      PolicyEvaluator.warningOffset(policy, remainingMinutes: 1, alreadyIssued: [15, 5, 1]) == nil)
  }

  private func basePolicy(keyID: String = "synthetic-controller-key-01") -> ParentalControlPolicy {
    ParentalControlPolicy(
      policyID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, version: 1,
      deviceID: "synthetic-child-01", timezone: "America/Regina",
      effectiveAt: iso.date(from: "2026-01-01T00:00:00Z")!,
      expiresAt: iso.date(from: "2026-12-31T23:59:59Z")!, defaultAction: .lock,
      warningOffsetsMinutes: [15, 5, 1], gracePeriodSeconds: 60,
      weeklyAllowed: [
        PolicyWeeklyWindow(day: .monday, start: "08:00", end: "20:00"),
        PolicyWeeklyWindow(day: .tuesday, start: "08:00", end: "20:00"),
        PolicyWeeklyWindow(day: .friday, start: "20:00", end: "01:00"),
        PolicyWeeklyWindow(day: .sunday, start: "01:00", end: "04:00"),
      ],
      blockedIntervals: [
        PolicyBlockedInterval(
          id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
          start: iso.date(from: "2026-01-13T00:00:00Z")!,
          end: iso.date(from: "2026-01-13T01:00:00Z")!, action: .lock,
          reason: "Family dinner")
      ],
      exceptions: [
        PolicyException(
          id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
          start: iso.date(from: "2026-01-14T03:00:00Z")!,
          end: iso.date(from: "2026-01-14T04:00:00Z")!, decision: .allow,
          reason: "Approved school project")
      ], dailyQuotaMinutes: 120, bonusMinutes: 15,
      childExplanation: "Available during family-approved hours; ask a parent for more time.",
      signature: PolicySignature(keyID: keyID, value: "unsigned"))
  }
}
