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

  @Test("installer maintenance opens briefly and expires fail closed")
  func installerMaintenance() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    let blocked = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: start.addingTimeInterval(-3_600),
      expiresAt: start.addingTimeInterval(3_600), defaultAction: .lock,
      gracePeriodSeconds: 0,
      weeklyAllowed: PolicyWeekday.allCases.map {
        PolicyWeeklyWindow(day: $0, start: "00:00", end: "23:59")
      },
      blockedIntervals: [
        PolicyBlockedInterval(
          start: start.addingTimeInterval(-60), end: start.addingTimeInterval(1_200),
          action: .lock, reason: "Synthetic installer recovery test")
      ], dailyQuotaMinutes: 1_440, childExplanation: "Synthetic installer recovery test",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: blocked), controllerPublicKey: identity.publicKeyData)
    #expect(
      runtime.tick(now: start, uptime: 100, sessionActive: true).contains {
        if case .enforcePolicy = $0 { return true }
        return false
      })

    let expiry = start.addingTimeInterval(600)
    try runtime.beginInstallerMaintenance(until: expiry, now: start)
    #expect(runtime.tick(now: start, uptime: 100, sessionActive: true).isEmpty)
    #expect(runtime.snapshot(now: start).1.adultOverrideUntil == expiry)
    #expect(
      runtime.tick(now: expiry, uptime: 700, sessionActive: true).contains {
        if case .enforcePolicy = $0 { return true }
        return false
      })
    #expect(throws: EndpointPolicyError.invalidInstallerMaintenance) {
      try runtime.beginInstallerMaintenance(
        until: start.addingTimeInterval(601), now: start)
    }
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
        .enforceImmediate(
          action: .logoff, explanation: "Authenticated immediate action",
          expiresAt: start.addingTimeInterval(700))))
    #expect(runtime.snapshot().1.immediateAction == nil)
  }

  @Test("immediate lock is durably handed to the user helper without a schedule")
  func immediateLockWithoutPolicy() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    let now = Date()
    let expiresAt = now.addingTimeInterval(120)
    try runtime.setImmediateAction(.lock, expiresAt: expiresAt, now: now)
    let expected = EndpointPolicyEvent.enforceImmediate(
      action: .lock, explanation: "Authenticated immediate action", expiresAt: expiresAt)
    #expect(
      runtime.tick(now: now, uptime: 100, sessionActive: true) == [expected])
    #expect(runtime.claimUserEvents(now: now) == [expected])
    #expect(runtime.claimUserEvents(now: now).isEmpty)
  }

  @Test("queued enforcement is rejected after its policy or decision becomes stale")
  func staleQueuedEnforcementIsRejected() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let blocked = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: now.addingTimeInterval(-3_600),
      expiresAt: now.addingTimeInterval(3_600), defaultAction: .lock,
      gracePeriodSeconds: 0,
      weeklyAllowed: PolicyWeekday.allCases.map {
        PolicyWeeklyWindow(day: $0, start: "00:00", end: "23:59")
      },
      blockedIntervals: [
        PolicyBlockedInterval(
          start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60),
          action: .lock, reason: "Synthetic short block")
      ], dailyQuotaMinutes: 1_440, childExplanation: "Synthetic stale-event test",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: blocked), controllerPublicKey: identity.publicKeyData)
    #expect(
      runtime.tick(now: now, uptime: 100, sessionActive: true).contains {
        if case .enforcePolicy = $0 { return true }
        return false
      })

    #expect(runtime.claimUserEvents(now: now.addingTimeInterval(61)).isEmpty)

    _ = runtime.tick(now: now, uptime: 200, sessionActive: true)
    let replacement = blocked.replacing(version: 2, signature: blocked.signature)
    try runtime.install(
      identity.sign(policy: replacement), controllerPublicKey: identity.publicKeyData)
    #expect(runtime.claimUserEvents(now: now).isEmpty)
  }

  @Test("an old restriction event cannot bypass a later restriction grace period")
  func restrictionInstanceBindsQueuedEnforcement() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let value = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: now.addingTimeInterval(-3_600), expiresAt: now.addingTimeInterval(3_600),
      defaultAction: .lock, gracePeriodSeconds: 30,
      weeklyAllowed: PolicyWeekday.allCases.map {
        PolicyWeeklyWindow(day: $0, start: "00:00", end: "23:59")
      },
      blockedIntervals: [
        PolicyBlockedInterval(
          start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60), action: .lock,
          reason: "Restriction A"),
        PolicyBlockedInterval(
          start: now.addingTimeInterval(120), end: now.addingTimeInterval(600), action: .lock,
          reason: "Restriction B"),
      ], dailyQuotaMinutes: 1_440, childExplanation: "Synthetic instance test",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(identity.sign(policy: value), controllerPublicKey: identity.publicKeyData)

    _ = runtime.tick(now: now, uptime: 100, sessionActive: true)
    _ = runtime.tick(now: now.addingTimeInterval(30), uptime: 130, sessionActive: true)
    _ = runtime.tick(now: now.addingTimeInterval(61), uptime: 161, sessionActive: true)
    _ = runtime.tick(now: now.addingTimeInterval(120), uptime: 220, sessionActive: true)
    let duringSecondGrace = runtime.claimUserEvents(now: now.addingTimeInterval(120))
    #expect(
      !duringSecondGrace.contains { event in
        if case .enforcePolicy = event { return true }
        return false
      })

    _ = runtime.tick(now: now.addingTimeInterval(150), uptime: 250, sessionActive: true)
    let afterSecondGrace = runtime.claimUserEvents(now: now.addingTimeInterval(150))
    #expect(
      afterSecondGrace.contains { event in
        if case .enforcePolicy(.lock, "Restriction B", 1, _) = event { return true }
        return false
      })
  }

  @Test("warning and approved-time events survive until the user helper claims them")
  func durableUserEvents() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = Date()
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: policy(version: 1)), controllerPublicKey: identity.publicKeyData)
    _ = runtime.tick(now: now, uptime: 100, sessionActive: true)
    let extended = policy(version: 2).replacing(
      exceptions: [
        PolicyException(
          start: now.addingTimeInterval(-1), end: now.addingTimeInterval(15 * 60),
          decision: .allow, reason: "Synthetic approved time")
      ])
    try runtime.install(
      identity.sign(policy: extended), controllerPublicKey: identity.publicKeyData)

    let restarted = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    let events = restarted.claimUserEvents()
    #expect(
      events.contains { event in
        if case .bonusGranted(let minutes, _) = event { return minutes >= 14 }
        return false
      })
    #expect(restarted.claimUserEvents().isEmpty)
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
    #expect(
      runtime.tick(now: start, uptime: 100, sessionActive: true)
        .contains(.warning(minutes: 1, action: .lock, explanation: "Synthetic bedtime")))

    let restored = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    #expect(
      restored.tick(now: start.addingTimeInterval(59), uptime: 159, sessionActive: true).isEmpty)
    #expect(
      restored.tick(now: start.addingTimeInterval(60), uptime: 160, sessionActive: true)
        .contains { event in
          if case .enforcePolicy(.lock, "Synthetic bedtime", 1, _) = event { return true }
          return false
        })
    #expect(
      restored.tick(now: start.addingTimeInterval(61), uptime: 161, sessionActive: true).isEmpty)
    restored.rearmRestrictionForActiveSession(now: start.addingTimeInterval(62))
    #expect(
      restored.tick(now: start.addingTimeInterval(62), uptime: 162, sessionActive: true)
        .contains { event in
          if case .enforcePolicy(.lock, "Synthetic bedtime", 1, _) = event { return true }
          return false
        })
    restored.rearmRestrictionForActiveSession(now: start.addingTimeInterval(63))
    #expect(
      restored.tick(now: start.addingTimeInterval(63), uptime: 163, sessionActive: true).isEmpty)
    restored.rearmRestrictionForActiveSession(now: start.addingTimeInterval(65))
    #expect(
      restored.tick(now: start.addingTimeInterval(65), uptime: 165, sessionActive: true)
        .contains { event in
          if case .enforcePolicy(.lock, "Synthetic bedtime", 1, _) = event { return true }
          return false
        })

    let rebooted = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    #expect(
      rebooted.tick(now: start.addingTimeInterval(120), uptime: 10, sessionActive: false)
        .contains { event in
          if case .enforcePolicy(.lock, "Synthetic bedtime", 1, _) = event { return true }
          return false
        })
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
    _ = runtime.tick(now: start, uptime: 100, activeUptime: 100, sessionActive: true)
    let wake = runtime.tick(
      now: start.addingTimeInterval(3_600), uptime: 3_700, activeUptime: 100,
      sessionActive: false)
    #expect(!wake.contains(.clockChangeDetected))
    #expect(runtime.snapshot().1.clockTrusted)
    #expect(runtime.snapshot().1.activeUseSeconds == 0)
    _ = runtime.tick(
      now: start.addingTimeInterval(3_615), uptime: 3_715, activeUptime: 115,
      sessionActive: true)
    #expect(runtime.snapshot().1.activeUseSeconds == 0)
    _ = runtime.tick(
      now: start.addingTimeInterval(3_630), uptime: 3_730, activeUptime: 130,
      sessionActive: true)
    #expect(runtime.snapshot().1.activeUseSeconds == 15)

    let restored = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)
    let reboot = restored.tick(
      now: start.addingTimeInterval(3_675), uptime: 10, sessionActive: false)
    #expect(!reboot.contains(.clockChangeDetected))
    #expect(restored.snapshot().0?.version == 1)
    #expect(restored.snapshot().1.clockTrusted)
  }

  @Test("authenticated session boundaries exclude awake lock-screen time from active use")
  func sessionActivityBoundaries() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: policy(version: 1)), controllerPublicKey: identity.publicKeyData)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    _ = runtime.tick(now: start, uptime: 100, activeUptime: 100, sessionActive: true)
    runtime.recordSessionActivity(
      false, now: start.addingTimeInterval(5), activeUptime: 105)
    runtime.recordSessionActivity(
      true, now: start.addingTimeInterval(605), activeUptime: 705)
    #expect(runtime.snapshot().1.activeUseSeconds == 5)
    _ = runtime.tick(
      now: start.addingTimeInterval(620), uptime: 720, activeUptime: 720,
      sessionActive: true)
    #expect(runtime.snapshot().1.activeUseSeconds == 20)
  }

  @Test("projected restriction countdown follows schedule and pauses quota while inactive")
  func projectedRestrictionCountdown() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let quotaPolicy = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: Date(timeIntervalSince1970: 1_700_000_000),
      expiresAt: Date(timeIntervalSince1970: 2_100_000_000), defaultAction: .lock,
      weeklyAllowed: PolicyWeekday.allCases.map {
        PolicyWeeklyWindow(day: $0, start: "00:00", end: "23:59")
      }, dailyQuotaMinutes: 20, childExplanation: "Synthetic countdown",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: quotaPolicy), controllerPublicKey: identity.publicKeyData)
    _ = runtime.tick(now: start, uptime: 100, sessionActive: true)
    let activeRestriction = try #require(
      runtime.projectedRestrictionDate(now: start, sessionActive: true))
    #expect(activeRestriction == start.addingTimeInterval(20 * 60))
    #expect(
      runtime.projectedRestrictionDate(
        now: start, sessionActive: false, horizonMinutes: 20) == nil)
    let inactiveRestriction = try #require(
      runtime.projectedRestrictionDate(now: start, sessionActive: false))
    #expect(inactiveRestriction > activeRestriction)
  }

  @Test("allowance summary separates the weekly window from the effective quota limit")
  func allowanceSummaryExplainsEarlierQuotaRestriction() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-03T14:12:00Z"))
    let policy = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "America/Regina",
      effectiveAt: now.addingTimeInterval(-3_600),
      expiresAt: now.addingTimeInterval(86_400), defaultAction: .lock,
      weeklyAllowed: [
        PolicyWeeklyWindow(day: .thursday, start: "06:58", end: "21:50")
      ], dailyQuotaMinutes: 120, bonusMinutes: 150,
      childExplanation: "Synthetic allowance summary",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(identity.sign(policy: policy), controllerPublicKey: identity.publicKeyData)
    _ = runtime.tick(now: now, uptime: 100, sessionActive: true)

    let nextRestriction = try #require(
      runtime.projectedRestrictionDate(now: now, sessionActive: true))
    #expect(nextRestriction == now.addingTimeInterval(270 * 60))
    let summary = try #require(
      runtime.allowanceSummary(
        now: now, sessionActive: true, nextRestrictionAt: nextRestriction))
    #expect(summary.timezone == "America/Regina")
    #expect(
      summary.scheduledWindowStartAt
        == ISO8601DateFormatter().date(from: "2026-09-03T12:58:00Z"))
    #expect(
      summary.scheduledWindowEndAt
        == ISO8601DateFormatter().date(from: "2026-09-04T03:50:00Z"))
    let plannedWindowSeconds = try #require(summary.plannedWindowSeconds)
    #expect(abs(plannedWindowSeconds - TimeInterval((14 * 60 + 52) * 60)) < 0.001)
    #expect(summary.totalQuotaMinutes == 270)
    #expect(summary.quotaRemainingMinutes == 270)
    #expect(summary.limitingReason == "Daily active-use quota reached")
  }

  @Test("quota projection resets at policy midnight before crossing into the next day")
  func projectedQuotaAcrossMidnightUsesNextDayBoundary() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-12T02:50:00Z"))
    let policy = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "America/Regina",
      effectiveAt: now.addingTimeInterval(-3_600),
      expiresAt: now.addingTimeInterval(8 * 86_400), defaultAction: .warningOnly,
      weeklyAllowed: PolicyWeekday.allCases.map {
        PolicyWeeklyWindow(day: $0, start: "08:00", end: "18:00")
      }, dailyQuotaMinutes: 540, bonusMinutes: 10,
      childExplanation: "Synthetic cross-midnight projection",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let initial = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try initial.install(identity.sign(policy: policy), controllerPublicKey: identity.publicKeyData)
    let state = EndpointPolicyRuntimeState(
      usageDay: "2026-09-11", activeUseSeconds: 51 * 60, lastSessionActive: true)
    try JSONEncoder.endpoint.encode(state).write(
      to: root.appendingPathComponent("policy-runtime.json"), options: .atomic)
    let runtime = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)

    let restriction = try #require(
      runtime.projectedRestrictionDate(now: now, sessionActive: true))
    #expect(restriction == ISO8601DateFormatter().date(from: "2026-09-12T15:10:00Z"))
    #expect(restriction != ISO8601DateFormatter().date(from: "2026-09-13T00:00:00Z"))
    let summary = try #require(
      runtime.allowanceSummary(
        now: now, sessionActive: true, nextRestrictionAt: restriction))
    #expect(summary.quotaRemainingMinutes == 499)
    #expect(summary.limitingReason == "Daily active-use quota reached")
  }

  @Test("projected allowance countdown follows the end of a blocked interval")
  func projectedAllowanceCountdown() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let blockedPolicy = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: Date(timeIntervalSince1970: 1_700_000_000),
      expiresAt: Date(timeIntervalSince1970: 2_100_000_000), defaultAction: .lock,
      weeklyAllowed: PolicyWeekday.allCases.map {
        PolicyWeeklyWindow(day: $0, start: "00:00", end: "23:59")
      },
      blockedIntervals: [
        PolicyBlockedInterval(
          start: start.addingTimeInterval(-60), end: start.addingTimeInterval(10 * 60),
          action: .lock, reason: "Synthetic countdown block")
      ], dailyQuotaMinutes: 1_440, childExplanation: "Synthetic countdown",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(
      identity.sign(policy: blockedPolicy), controllerPublicKey: identity.publicKeyData)
    _ = runtime.tick(now: start, uptime: 100, sessionActive: true)
    #expect(runtime.projectedRestrictionDate(now: start, sessionActive: true) == nil)
    #expect(runtime.projectedAllowanceDate(now: start) == start.addingTimeInterval(10 * 60))
  }

  @Test("quota reset and next weekly window stay distinct after Saturday quota exhaustion")
  func warningOnlyQuotaResetIsNotScheduledAvailability() throws {
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-12T21:24:00Z"))
    let midnight = try #require(ISO8601DateFormatter().date(from: "2026-09-13T06:00:00Z"))
    let sundayWindow = try #require(
      ISO8601DateFormatter().date(from: "2026-09-13T14:00:00Z"))

    func runtime(action: PolicyAction) throws -> (EndpointPolicyRuntime, URL) {
      let root = temporaryRoot()
      let policy = ParentalControlPolicy(
        version: 1, deviceID: "child-policy-test", timezone: "America/Regina",
        effectiveAt: now.addingTimeInterval(-86_400),
        expiresAt: now.addingTimeInterval(8 * 86_400), defaultAction: action,
        weeklyAllowed: PolicyWeekday.allCases.map {
          PolicyWeeklyWindow(day: $0, start: "08:00", end: "18:00")
        }, dailyQuotaMinutes: 540, bonusMinutes: 10,
        childExplanation: "Synthetic Saturday quota projection",
        signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
      let initial = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
      try initial.install(
        identity.sign(policy: policy), controllerPublicKey: identity.publicKeyData)
      try JSONEncoder.endpoint.encode(
        EndpointPolicyRuntimeState(
          usageDay: "2026-09-12", activeUseSeconds: 550 * 60, lastSessionActive: true)
      ).write(to: root.appendingPathComponent("policy-runtime.json"), options: .atomic)
      return (
        EndpointPolicyRuntime(
          root: root, deviceID: "child-policy-test",
          controllerPublicKey: identity.publicKeyData), root
      )
    }

    let (warningRuntime, warningRoot) = try runtime(action: .warningOnly)
    defer { try? FileManager.default.removeItem(at: warningRoot) }
    #expect(warningRuntime.projectedAllowanceDate(now: now) == midnight)
    let warningSummary = try #require(
      warningRuntime.allowanceSummary(now: now, sessionActive: true, nextRestrictionAt: nil))
    #expect(warningSummary.nextScheduledWindowStartAt == sundayWindow)

    let (lockRuntime, lockRoot) = try runtime(action: .lock)
    defer { try? FileManager.default.removeItem(at: lockRoot) }
    #expect(lockRuntime.projectedAllowanceDate(now: now) == sundayWindow)
    let lockSummary = try #require(
      lockRuntime.allowanceSummary(now: now, sessionActive: true, nextRestrictionAt: nil))
    #expect(lockSummary.nextScheduledWindowStartAt == sundayWindow)
  }

  @Test("warning countdown preserves the evaluator's higher-priority decision source")
  func warningCountdownUsesDecisionSource() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-12T23:50:00Z"))
    let intervalEnd = try #require(
      ISO8601DateFormatter().date(from: "2026-09-13T00:30:00Z"))
    let policy = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: now.addingTimeInterval(-86_400),
      expiresAt: now.addingTimeInterval(8 * 86_400), defaultAction: .warningOnly,
      weeklyAllowed: PolicyWeekday.allCases.map {
        PolicyWeeklyWindow(day: $0, start: "00:00", end: "23:59")
      },
      blockedIntervals: [
        PolicyBlockedInterval(
          start: now.addingTimeInterval(-5 * 60), end: intervalEnd,
          action: .warningOnly, reason: "Synthetic higher-priority warning")
      ], dailyQuotaMinutes: 1, childExplanation: "Synthetic overlapping warning",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let initial = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try initial.install(identity.sign(policy: policy), controllerPublicKey: identity.publicKeyData)
    try JSONEncoder.endpoint.encode(
      EndpointPolicyRuntimeState(
        usageDay: "2026-09-12", activeUseSeconds: 60, lastSessionActive: true)
    ).write(to: root.appendingPathComponent("policy-runtime.json"), options: .atomic)
    let runtime = EndpointPolicyRuntime(
      root: root, deviceID: "child-policy-test", controllerPublicKey: identity.publicKeyData)

    _ = runtime.tick(now: now, uptime: 100, sessionActive: true)

    #expect(runtime.snapshot(now: now).2?.source == .blockedInterval)
    #expect(runtime.projectedAllowanceDate(now: now) == intervalEnd)
  }

  @Test("schedule relock stops at an allowed-window boundary and rejects stale decisions")
  func scheduleRelockGate() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_030)
    var status = EndpointStatus(
      deviceID: "child-policy-test", deviceName: "Synthetic Mac", model: "Mac",
      operatingSystem: "macOS", architecture: "arm64", uptimeSeconds: 100,
      bootTime: now.addingTimeInterval(-100), sessionState: .active, consoleUser: "child",
      policyVersion: 1, policyDecision: .block, policyAction: .lock,
      policyLastEvaluatedAt: now.addingTimeInterval(-5),
      policyNextAllowanceAt: now.addingTimeInterval(60))

    #expect(
      EndpointScheduleRelockGate.shouldRelock(
        status: status, sessionIsActive: true, screenSaverIsForeground: false,
        consoleUserPresent: true, now: now, lastAttemptAt: nil))
    #expect(
      !EndpointScheduleRelockGate.shouldRelock(
        status: status, sessionIsActive: true, screenSaverIsForeground: false,
        consoleUserPresent: true, now: now,
        lastAttemptAt: now.addingTimeInterval(
          -(EndpointScheduleRelockGate.minimumRetryInterval - 1))))

    status.policyNextAllowanceAt = now
    #expect(
      !EndpointScheduleRelockGate.shouldRelock(
        status: status, sessionIsActive: true, screenSaverIsForeground: false,
        consoleUserPresent: true, now: now, lastAttemptAt: nil))

    status.policyNextAllowanceAt = nil
    status.policyLastEvaluatedAt = now.addingTimeInterval(
      -(EndpointScheduleRelockGate.maximumDecisionAge + 1))
    #expect(
      !EndpointScheduleRelockGate.shouldRelock(
        status: status, sessionIsActive: true, screenSaverIsForeground: false,
        consoleUserPresent: true, now: now, lastAttemptAt: nil))
  }

  @Test("projected allowance aligns to the exact scheduled minute")
  func projectedAllowanceUsesMinuteBoundary() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = try #require(
      ISO8601DateFormatter().date(from: "2027-01-04T07:59:45Z"))
    let policy = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: now.addingTimeInterval(-3_600),
      expiresAt: now.addingTimeInterval(86_400), defaultAction: .lock,
      weeklyAllowed: [PolicyWeeklyWindow(day: .monday, start: "08:00", end: "20:00")],
      dailyQuotaMinutes: 1_440, childExplanation: "Synthetic exact boundary",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(identity.sign(policy: policy), controllerPublicKey: identity.publicKeyData)
    _ = runtime.tick(now: now, uptime: 100, sessionActive: true)

    #expect(
      runtime.projectedAllowanceDate(now: now)
        == ISO8601DateFormatter().date(from: "2027-01-04T08:00:00Z"))
  }

  @Test("projected restriction aligns to the exact scheduled minute")
  func projectedRestrictionUsesMinuteBoundary() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let identity = try Ed25519Identity(keyID: "controller-local-authority")
    let now = try #require(
      ISO8601DateFormatter().date(from: "2027-01-04T19:59:45Z"))
    let policy = ParentalControlPolicy(
      version: 1, deviceID: "child-policy-test", timezone: "UTC",
      effectiveAt: now.addingTimeInterval(-3_600),
      expiresAt: now.addingTimeInterval(86_400), defaultAction: .lock,
      weeklyAllowed: [PolicyWeeklyWindow(day: .monday, start: "08:00", end: "20:00")],
      dailyQuotaMinutes: 1_440, childExplanation: "Synthetic exact boundary",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
    let runtime = EndpointPolicyRuntime(root: root, deviceID: "child-policy-test")
    try runtime.install(identity.sign(policy: policy), controllerPublicKey: identity.publicKeyData)
    _ = runtime.tick(now: now, uptime: 100, activeUptime: 100, sessionActive: true)

    #expect(
      runtime.projectedRestrictionDate(now: now, sessionActive: true)
        == ISO8601DateFormatter().date(from: "2027-01-04T20:00:00Z"))
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
