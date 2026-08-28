import CryptoKit
import Darwin
import Foundation
import HubCore

public enum EndpointPolicyError: Error, Equatable {
  case noPolicy
  case wrongDevice
  case replayedVersion
  case invalidAdultCode
  case adultCodeLocked
}

public struct AdultCodeVerifier: Codable, Equatable, Sendable {
  public let salt: String
  public let digest: String

  public init(code: String, salt: String = UUID().uuidString) {
    self.salt = salt
    digest = Self.digest(code: code, salt: salt)
  }

  public init(salt: String, digest: String) {
    self.salt = String(salt.prefix(128))
    self.digest = String(digest.prefix(128))
  }

  public func matches(_ code: String) -> Bool {
    let lhs = Array(digest.utf8)
    let rhs = Array(Self.digest(code: code, salt: salt).utf8)
    var difference = lhs.count ^ rhs.count
    for index in 0..<max(lhs.count, rhs.count) {
      difference |= Int((index < lhs.count ? lhs[index] : 0) ^ (index < rhs.count ? rhs[index] : 0))
    }
    return difference == 0
  }

  private static func digest(code: String, salt: String) -> String {
    Data(SHA256.hash(data: Data("adult-code|\(salt)|\(code)".utf8))).base64EncodedString()
  }
}

public struct EndpointPolicyRuntimeState: Codable, Equatable, Sendable {
  public var usageDay: String?
  public var activeUseSeconds: TimeInterval
  public var adultOverrideUntil: Date?
  public var verifier: AdultCodeVerifier?
  public var failedAdultAttempts: [Date]
  public var adultCodeLockedUntil: Date?
  public var lastWallClock: Date?
  public var lastUptime: TimeInterval?
  public var clockTrusted: Bool
  public var issuedWarnings: [Int]
  public var immediateAction: PolicyAction?
  public var immediateActionExpiresAt: Date?
  public var restrictionBeganAt: Date?
  public var restrictionSource: PolicyDecisionSource?
  public var restrictionAction: PolicyAction?
  public var restrictionEnforced: Bool?
  public var pendingUserEvents: [EndpointPolicyEvent]?

  public init(
    usageDay: String? = nil, activeUseSeconds: TimeInterval = 0,
    adultOverrideUntil: Date? = nil, verifier: AdultCodeVerifier? = nil,
    failedAdultAttempts: [Date] = [], adultCodeLockedUntil: Date? = nil,
    lastWallClock: Date? = nil, lastUptime: TimeInterval? = nil, clockTrusted: Bool = true,
    issuedWarnings: [Int] = [], immediateAction: PolicyAction? = nil,
    immediateActionExpiresAt: Date? = nil, restrictionBeganAt: Date? = nil,
    restrictionSource: PolicyDecisionSource? = nil, restrictionAction: PolicyAction? = nil,
    restrictionEnforced: Bool? = nil, pendingUserEvents: [EndpointPolicyEvent] = []
  ) {
    self.usageDay = usageDay
    self.activeUseSeconds = activeUseSeconds
    self.adultOverrideUntil = adultOverrideUntil
    self.verifier = verifier
    self.failedAdultAttempts = Array(failedAdultAttempts.suffix(3))
    self.adultCodeLockedUntil = adultCodeLockedUntil
    self.lastWallClock = lastWallClock
    self.lastUptime = lastUptime
    self.clockTrusted = clockTrusted
    self.issuedWarnings = Array(Set(issuedWarnings)).sorted(by: >)
    self.immediateAction = immediateAction
    self.immediateActionExpiresAt = immediateActionExpiresAt
    self.restrictionBeganAt = restrictionBeganAt
    self.restrictionSource = restrictionSource
    self.restrictionAction = restrictionAction
    self.restrictionEnforced = restrictionEnforced
    self.pendingUserEvents = Array(pendingUserEvents.suffix(32))
  }
}

public enum EndpointPolicyEvent: Codable, Equatable, Sendable {
  case warning(minutes: Int, action: PolicyAction, explanation: String)
  case enforce(action: PolicyAction, explanation: String)
  case clockChangeDetected
  case bonusGranted(minutes: Int, until: Date)
}

public final class EndpointPolicyRuntime: @unchecked Sendable {
  public static let maximumFailedAttempts = 3
  public static let attemptWindow: TimeInterval = 5 * 60
  public static let lockoutDuration: TimeInterval = 5 * 60

  private let lock = NSLock()
  private let root: URL
  private let deviceID: String
  private var policy: ParentalControlPolicy?
  private var state: EndpointPolicyRuntimeState
  private var lastDecision: PolicyDecision?

  public init(
    root: URL, deviceID: String, controllerPublicKey: Data? = nil,
    expectedKeyID: String = "controller-local-authority"
  ) {
    self.root = root
    self.deviceID = deviceID
    if let cached = try? Self.readPolicy(root: root), cached.deviceID == deviceID,
      let controllerPublicKey,
      (try? PolicyCodec.verify(
        cached, publicKey: controllerPublicKey, expectedKeyID: expectedKeyID)) != nil
    {
      policy = cached
    } else {
      policy = nil
    }
    state = (try? Self.readState(root: root)) ?? EndpointPolicyRuntimeState()
  }

  public func install(
    _ candidate: ParentalControlPolicy, controllerPublicKey: Data,
    expectedKeyID: String = "controller-local-authority"
  ) throws {
    try PolicyCodec.verify(
      candidate, publicKey: controllerPublicKey, expectedKeyID: expectedKeyID)
    guard candidate.deviceID == deviceID else { throw EndpointPolicyError.wrongDevice }
    lock.lock()
    defer { lock.unlock() }
    guard candidate.version > (policy?.version ?? 0) else {
      throw EndpointPolicyError.replayedVersion
    }
    let former = policy
    policy = candidate
    state.clockTrusted = true
    state.issuedWarnings = []
    clearRestrictionLocked()
    let formerBonusEnd = former?.exceptions.filter { $0.decision == .allow }.map(\.end).max()
    if let bonusEnd = candidate.exceptions.filter({ $0.decision == .allow }).map(\.end).max(),
      bonusEnd > Date(), bonusEnd > (formerBonusEnd ?? .distantPast)
    {
      let minutes = max(1, Int(ceil(bonusEnd.timeIntervalSinceNow / 60)))
      enqueueUserEventsLocked([.bonusGranted(minutes: minutes, until: bonusEnd)])
    }
    try persistLocked()
  }

  public func configureAdultVerifier(_ verifier: AdultCodeVerifier) throws {
    lock.lock()
    defer { lock.unlock() }
    state.verifier = verifier
    state.failedAdultAttempts = []
    state.adultCodeLockedUntil = nil
    try persistLocked()
  }

  @discardableResult
  public func submitAdultCode(
    _ code: String, now: Date = Date(), duration: TimeInterval = 15 * 60
  ) throws -> Date {
    lock.lock()
    defer { lock.unlock() }
    if let locked = state.adultCodeLockedUntil, locked > now {
      throw EndpointPolicyError.adultCodeLocked
    }
    state.failedAdultAttempts.removeAll { now.timeIntervalSince($0) > Self.attemptWindow }
    guard let verifier = state.verifier, verifier.matches(code) else {
      state.failedAdultAttempts.append(now)
      if state.failedAdultAttempts.count >= Self.maximumFailedAttempts {
        state.adultCodeLockedUntil = now.addingTimeInterval(Self.lockoutDuration)
      }
      try persistLocked()
      throw EndpointPolicyError.invalidAdultCode
    }
    let until = now.addingTimeInterval(max(60, min(duration, 60 * 60)))
    state.adultOverrideUntil = until
    state.failedAdultAttempts = []
    state.adultCodeLockedUntil = nil
    try persistLocked()
    return until
  }

  public func setImmediateAction(
    _ action: PolicyAction, expiresAt: Date, now: Date = Date()
  ) throws {
    guard expiresAt > now, expiresAt.timeIntervalSince(now) <= 15 * 60 else {
      throw ProtocolSecurityError.expired
    }
    lock.lock()
    defer { lock.unlock() }
    state.immediateAction = action
    state.immediateActionExpiresAt = expiresAt
    try persistLocked()
  }

  public func snapshot(now: Date = Date()) -> (
    ParentalControlPolicy?, EndpointPolicyRuntimeState, PolicyDecision?
  ) {
    lock.lock()
    defer { lock.unlock() }
    var current = state
    if current.adultOverrideUntil.map({ $0 <= now }) == true { current.adultOverrideUntil = nil }
    return (policy, current, lastDecision)
  }

  public func projectedRestrictionDate(
    now: Date = Date(), sessionActive: Bool, horizonMinutes: Int = 8 * 24 * 60
  ) -> Date? {
    lock.lock()
    defer { lock.unlock() }
    guard let policy else { return nil }
    let boundedHorizon = max(1, min(horizonMinutes, 8 * 24 * 60))
    let initialMinutes = Int(state.activeUseSeconds / 60)
    let overrideUntil = state.adultOverrideUntil
    let current = PolicyEvaluator.evaluate(
      policy,
      input: PolicyEvaluationInput(
        at: now, activeUseMinutes: initialMinutes,
        adultOverrideActive: overrideUntil.map { $0 > now } ?? false))
    guard current.decision == .allow else { return nil }
    for minute in 1...boundedHorizon {
      let future = now.addingTimeInterval(TimeInterval(minute * 60))
      let projectedActiveSeconds =
        state.activeUseSeconds + (sessionActive ? TimeInterval(minute * 60) : 0)
      let decision = PolicyEvaluator.evaluate(
        policy,
        input: PolicyEvaluationInput(
          at: future, activeUseMinutes: Int(projectedActiveSeconds / 60),
          adultOverrideActive: overrideUntil.map { $0 > future } ?? false))
      if decision.decision == .block { return future }
    }
    return nil
  }

  public func claimUserEvents(limit: Int = 16) -> [EndpointPolicyEvent] {
    lock.lock()
    defer { lock.unlock() }
    let count = min(max(1, limit), min(state.pendingUserEvents?.count ?? 0, 32))
    guard count > 0 else { return [] }
    let pending = state.pendingUserEvents ?? []
    let claimed = Array(pending.prefix(count))
    state.pendingUserEvents = Array(pending.dropFirst(count))
    do {
      try persistLocked()
    } catch {
      state.pendingUserEvents = pending
      return []
    }
    return claimed
  }

  public func tick(
    now: Date = Date(), uptime: TimeInterval = EndpointContinuousClock.uptime(),
    sessionActive: Bool
  ) -> [EndpointPolicyEvent] {
    lock.lock()
    defer { lock.unlock() }
    var events: [EndpointPolicyEvent] = []
    if state.immediateActionExpiresAt.map({ $0 <= now }) == true {
      state.immediateAction = nil
      state.immediateActionExpiresAt = nil
    }
    if let immediateAction = state.immediateAction {
      events.append(
        .enforce(action: immediateAction, explanation: "Authenticated immediate action"))
      state.immediateAction = nil
      state.immediateActionExpiresAt = nil
      enqueueUserEventsLocked(events)
      try? persistLocked()
      return events
    }
    guard let policy else { return [] }
    let day = dayKey(now, timezone: policy.timezone)
    if state.usageDay != day {
      state.usageDay = day
      state.activeUseSeconds = 0
      state.issuedWarnings = []
    }
    if let formerWall = state.lastWallClock, let formerUptime = state.lastUptime {
      let wallDelta = now.timeIntervalSince(formerWall)
      let uptimeDelta = uptime - formerUptime
      if uptimeDelta < 0 {
        // A monotonic clock cannot move backward during one boot. Treat this as an expected reboot:
        // keep the signed policy, quota, override, and grace state, then establish a new baseline.
        // Re-issue an active restriction after login because the prior boot's action is no longer
        // evidence that this session is protected.
        state.restrictionEnforced = false
      } else if wallDelta < -5 || abs(wallDelta - uptimeDelta) > 120 {
        if state.clockTrusted { events.append(.clockChangeDetected) }
        state.clockTrusted = false
      } else if sessionActive, uptimeDelta > 0 {
        state.activeUseSeconds += min(uptimeDelta, 120)
      }
    }
    state.lastWallClock = now
    state.lastUptime = uptime
    if state.adultOverrideUntil.map({ $0 <= now }) == true { state.adultOverrideUntil = nil }
    let input = PolicyEvaluationInput(
      at: now, activeUseMinutes: Int(state.activeUseSeconds / 60),
      adultOverrideActive: state.adultOverrideUntil.map({ $0 > now }) ?? false,
      immediateAction: state.immediateAction)
    var decision = PolicyEvaluator.evaluate(policy, input: input)
    if !state.clockTrusted, !(state.adultOverrideUntil.map({ $0 > now }) ?? false) {
      decision = PolicyDecision(
        decision: .block, action: policy.defaultAction, source: .inactivePolicy,
        reason: "Clock change detected; reconnect to refresh the signed policy")
    }
    let remaining = minutesUntilRestriction(policy: policy, input: input)
    if decision.decision == .allow, let remaining,
      let offset = PolicyEvaluator.warningOffset(
        policy, remainingMinutes: remaining, alreadyIssued: Set(state.issuedWarnings))
    {
      state.issuedWarnings.append(offset)
      events.append(
        .warning(
          minutes: offset, action: policy.defaultAction, explanation: policy.childExplanation))
    }
    if decision.decision == .allow {
      if lastDecision?.decision == .block { state.issuedWarnings = [] }
      clearRestrictionLocked()
    } else if let action = decision.action {
      let changed = state.restrictionSource != decision.source || state.restrictionAction != action
      if changed {
        state.restrictionBeganAt = now
        state.restrictionSource = decision.source
        state.restrictionAction = action
        state.restrictionEnforced = false
        if policy.gracePeriodSeconds > 0 {
          let minutes = max(1, Int(ceil(Double(policy.gracePeriodSeconds) / 60)))
          events.append(
            .warning(minutes: minutes, action: action, explanation: decision.reason))
        }
      }
      let immediate = decision.source == .immediateCommand || decision.source == .inactivePolicy
      let elapsed = now.timeIntervalSince(state.restrictionBeganAt ?? now)
      if state.restrictionEnforced != true,
        immediate || elapsed >= TimeInterval(policy.gracePeriodSeconds)
      {
        events.append(.enforce(action: action, explanation: decision.reason))
        state.restrictionEnforced = true
      }
    }
    lastDecision = decision
    state.immediateAction = nil
    state.immediateActionExpiresAt = nil
    enqueueUserEventsLocked(events)
    try? persistLocked()
    return events
  }

  private func enqueueUserEventsLocked(_ events: [EndpointPolicyEvent]) {
    guard !events.isEmpty else { return }
    var pending = state.pendingUserEvents ?? []
    pending.append(contentsOf: events)
    state.pendingUserEvents = Array(pending.suffix(32))
  }

  private func minutesUntilRestriction(
    policy: ParentalControlPolicy, input: PolicyEvaluationInput
  ) -> Int? {
    let quotaRemaining = max(
      0, policy.dailyQuotaMinutes + policy.bonusMinutes - input.activeUseMinutes)
    let maximum = max(policy.warningOffsetsMinutes.max() ?? 0, 1)
    var scheduleRemaining: Int?
    for minute in 1...maximum {
      let future = PolicyEvaluator.evaluate(
        policy,
        input: PolicyEvaluationInput(
          at: input.at.addingTimeInterval(TimeInterval(minute * 60)),
          activeUseMinutes: input.activeUseMinutes + minute,
          adultOverrideActive: input.adultOverrideActive))
      if future.decision == .block {
        scheduleRemaining = minute
        break
      }
    }
    return [quotaRemaining, scheduleRemaining].compactMap { $0 }.min()
  }

  private func dayKey(_ date: Date, timezone: String) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone) ?? .current
    let value = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", value.year ?? 0, value.month ?? 0, value.day ?? 0)
  }

  private func persistLocked() throws {
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    if let policy {
      let url = root.appendingPathComponent("signed-policy.json")
      try PolicyCodec.encoder().encode(policy).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    let stateURL = root.appendingPathComponent("policy-runtime.json")
    try JSONEncoder.endpoint.encode(state).write(to: stateURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
  }

  private func clearRestrictionLocked() {
    state.restrictionBeganAt = nil
    state.restrictionSource = nil
    state.restrictionAction = nil
    state.restrictionEnforced = nil
  }

  private static func readPolicy(root: URL) throws -> ParentalControlPolicy {
    try PolicyCodec.decoder().decode(
      ParentalControlPolicy.self,
      from: Data(contentsOf: root.appendingPathComponent("signed-policy.json")))
  }

  private static func readState(root: URL) throws -> EndpointPolicyRuntimeState {
    try JSONDecoder.endpoint.decode(
      EndpointPolicyRuntimeState.self,
      from: Data(contentsOf: root.appendingPathComponent("policy-runtime.json")))
  }
}

public enum EndpointContinuousClock {
  public static func uptime() -> TimeInterval {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let nanoseconds = Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom)
    return nanoseconds / 1_000_000_000
  }
}
