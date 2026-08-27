import Foundation
import HubCore
import Testing

@testable import EndpointCore

@Suite("offline signed policy runtime", .serialized)
struct EndpointPolicyRuntimeTests {
  @Test("signed policy persists, tampering and version replay fail closed")
  func persistenceAndReplay() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    let signed = try identity.sign(policy: policy(version: 1))
    try runtime.install(signed, controllerPublicKey: identity.publicKeyData)
    #expect(runtime.snapshot().0?.version == 1)
    #expect(throws: EndpointPolicyError.replayedVersion) {
      try runtime.install(signed, controllerPublicKey: identity.publicKeyData)
    }
    let tampered = signed.replacing(bonusMinutes: 60)
    #expect(throws: PolicySignatureError.self) {
      try runtime.install(tampered, controllerPublicKey: identity.publicKeyData)
    }
    let restored = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    #expect(restored.snapshot().0?.version == 1)
    let mode = try #require(
      (try FileManager.default.attributesOfItem(
        atPath: root.appendingPathComponent("signed-policy.json").path)[.posixPermissions]
        as? NSNumber)?.intValue)
    #expect(mode & 0o777 == 0o600)

    try PolicyCodec.encoder().encode(tampered).write(
      to: root.appendingPathComponent("signed-policy.json"), options: .atomic)
    let rejectedCache = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    #expect(rejectedCache.snapshot().0 == nil)
  }

  @Test("adult verifier is rate limited and override has precedence")
  func adultOverride() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    let verifier = AdultCodeVerifier(code: "827364", salt: "synthetic-salt")
    try runtime.configureAdultVerifier(verifier)
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    for attempt in 0..<3 {
      #expect(throws: EndpointPolicyError.self) {
        try runtime.submitAdultCode("000000", now: start.addingTimeInterval(Double(attempt)))
      }
    }
    #expect(throws: EndpointPolicyError.adultCodeLocked) {
      try runtime.submitAdultCode("827364", now: start.addingTimeInterval(10))
    }
    let until = try runtime.submitAdultCode(
      "827364", now: start.addingTimeInterval(311), duration: 15 * 60)
    #expect(until == start.addingTimeInterval(1_211))
  }

  @Test("clock discontinuity fails closed and an immediate action is isolated")
  func clockAndAction() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: policy(version: 1)), controllerPublicKey: identity.publicKeyData)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    _ = runtime.tick(now: start, uptime: 100, sessionActive: true)
    let changed = runtime.tick(
      now: start.addingTimeInterval(600), uptime: 101, sessionActive: true)
    #expect(changed.contains(.clockChangeDetected))
    #expect(runtime.snapshot().2?.decision == .block)
    #expect(runtime.snapshot().1.clockTrusted == false)

    let refreshed = try identity.sign(policy: policy(version: 2))
    try runtime.install(refreshed, controllerPublicKey: identity.publicKeyData)
    try runtime.setImmediateAction(.logoff, expiresAt: start.addingTimeInterval(700), now: start)
    let action = runtime.tick(
      now: start.addingTimeInterval(610), uptime: 111, sessionActive: false)
    #expect(
      action.contains(
        .enforce(action: .logoff, explanation: "Authenticated immediate action")))
    #expect(runtime.snapshot().1.immediateAction == nil)
  }

  @Test("grace period survives runtime restart and enforces once")
  func persistentGrace() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let blocked = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: Date(timeIntervalSince1970: 1_700_000_000),
      expiresAt: Date(timeIntervalSince1970: 2_100_000_000), defaultAction: .lock,
      warningOffsetsMinutes: [15, 5, 1], gracePeriodSeconds: 60,
      weeklyAllowed: [],
      blockedIntervals: [
        PolicyBlockedInterval(
          start: start.addingTimeInterval(-10), end: start.addingTimeInterval(600),
          action: .lock, reason: "Synthetic bedtime")
      ], dailyQuotaMinutes: 1_440, childExplanation: "Synthetic policy fixture",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: blocked), controllerPublicKey: identity.publicKeyData)
    #expect(runtime.tick(now: start, uptime: 100, sessionActive: true).isEmpty)

    let restored = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    #expect(
      restored.tick(now: start.addingTimeInterval(59), uptime: 159, sessionActive: true).isEmpty)
    #expect(
      restored.tick(now: start.addingTimeInterval(60), uptime: 160, sessionActive: true)
        .contains(.enforce(action: .lock, explanation: "Synthetic bedtime")))
    #expect(
      restored.tick(now: start.addingTimeInterval(61), uptime: 161, sessionActive: true).isEmpty)

    let rebooted = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    #expect(
      rebooted.tick(now: start.addingTimeInterval(120), uptime: 10, sessionActive: false)
        .contains(.enforce(action: .lock, explanation: "Synthetic bedtime")))
  }

  @Test("sleep and resume preserve clock trust without counting sleep as active use")
  func sleepResume() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: policy(version: 1)), controllerPublicKey: identity.publicKeyData)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    _ = runtime.tick(now: start, uptime: 100, sessionActive: true)
    let wake = runtime.tick(
      now: start.addingTimeInterval(3_600), uptime: 3_700, sessionActive: false)
    #expect(!wake.contains(.clockChangeDetected))
    #expect(runtime.snapshot().1.clockTrusted)
    #expect(runtime.snapshot().1.activeUseSeconds == 0)
    _ = runtime.tick(
      now: start.addingTimeInterval(3_615), uptime: 3_715, sessionActive: true)
    #expect(runtime.snapshot().1.activeUseSeconds == 15)

    let restored = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    let reboot = restored.tick(
      now: start.addingTimeInterval(3_675), uptime: 10, sessionActive: false)
    #expect(!reboot.contains(.clockChangeDetected))
    #expect(restored.snapshot().0?.version == 1)
    #expect(restored.snapshot().1.clockTrusted)
  }

  private func policy(version: UInt64) -> ParentalControlPolicy {
    ParentalControlPolicy(
      version: version, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: Date(timeIntervalSince1970: 1_700_000_000),
      expiresAt: Date(timeIntervalSince1970: 2_100_000_000), defaultAction: .lock,
      warningOffsetsMinutes: [15, 5, 1], gracePeriodSeconds: 60,
      weeklyAllowed: PolicyWeekday.allCases.map {
        PolicyWeeklyWindow(day: $0, start: "00:00", end: "23:59")
      }, dailyQuotaMinutes: 1_440,
      childExplanation: "Synthetic policy fixture",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "policy-runtime-\(UUID().uuidString)", isDirectory: true)
  }
}
