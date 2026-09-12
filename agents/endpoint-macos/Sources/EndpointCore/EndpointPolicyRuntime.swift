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
  case invalidInstallerMaintenance
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
  public var lastActiveUptime: TimeInterval?
  public var lastSessionActive: Bool?
  public var clockTrusted: Bool
  public var issuedWarnings: [Int]
  public var immediateAction: PolicyAction?
  public var immediateActionExpiresAt: Date?
  public var restrictionBeganAt: Date?
  public var restrictionID: UUID?
  public var restrictionSource: PolicyDecisionSource?
  public var restrictionAction: PolicyAction?
  public var restrictionEnforced: Bool?
  public var lastRestrictionRearmAt: Date?
  public var pendingUserEvents: [EndpointPolicyEvent]?

  public init(
    usageDay: String? = nil, activeUseSeconds: TimeInterval = 0,
    adultOverrideUntil: Date? = nil, verifier: AdultCodeVerifier? = nil,
    failedAdultAttempts: [Date] = [], adultCodeLockedUntil: Date? = nil,
    lastWallClock: Date? = nil, lastUptime: TimeInterval? = nil,
    lastActiveUptime: TimeInterval? = nil, lastSessionActive: Bool? = nil,
    clockTrusted: Bool = true,
    issuedWarnings: [Int] = [], immediateAction: PolicyAction? = nil,
    immediateActionExpiresAt: Date? = nil, restrictionBeganAt: Date? = nil,
    restrictionID: UUID? = nil,
    restrictionSource: PolicyDecisionSource? = nil, restrictionAction: PolicyAction? = nil,
    restrictionEnforced: Bool? = nil, lastRestrictionRearmAt: Date? = nil,
    pendingUserEvents: [EndpointPolicyEvent] = []
  ) {
    self.usageDay = usageDay
    self.activeUseSeconds = activeUseSeconds
    self.adultOverrideUntil = adultOverrideUntil
    self.verifier = verifier
    self.failedAdultAttempts = Array(failedAdultAttempts.suffix(3))
    self.adultCodeLockedUntil = adultCodeLockedUntil
    self.lastWallClock = lastWallClock
    self.lastUptime = lastUptime
    self.lastActiveUptime = lastActiveUptime
    self.lastSessionActive = lastSessionActive
    self.clockTrusted = clockTrusted
    self.issuedWarnings = Array(Set(issuedWarnings)).sorted(by: >)
    self.immediateAction = immediateAction
    self.immediateActionExpiresAt = immediateActionExpiresAt
    self.restrictionBeganAt = restrictionBeganAt
    self.restrictionID = restrictionID
    self.restrictionSource = restrictionSource
    self.restrictionAction = restrictionAction
    self.restrictionEnforced = restrictionEnforced
    self.lastRestrictionRearmAt = lastRestrictionRearmAt
    self.pendingUserEvents = Array(pendingUserEvents.suffix(32))
  }
}

public enum EndpointPolicyEvent: Codable, Equatable, Sendable {
  case warning(minutes: Int, action: PolicyAction, explanation: String)
  /// Decode-only compatibility for RC7 queues. It lacks the version/expiry needed for safe use
  /// and is discarded by `claimUserEvents`.
  case enforce(action: PolicyAction, explanation: String)
  case enforcePolicy(
    action: PolicyAction, explanation: String, policyVersion: UInt64, restrictionID: UUID)
  case enforceImmediate(action: PolicyAction, explanation: String, expiresAt: Date)
  case clockChangeDetected
  case bonusGranted(minutes: Int, until: Date)
  case timeRequestRejected(minutes: Int)
}

/// Decides whether the visible login helper may repeat a schedule lock. A persisted decision can
/// briefly outlive sleep, wake, or the start of a newly allowed window, so only a recent daemon
/// evaluation whose projected allowance is still in the future may relock the active session.
public enum EndpointScheduleRelockGate {
  public static let maximumDecisionAge: TimeInterval = 30
  public static let minimumRetryInterval: TimeInterval = 60

  public static func shouldRelock(
    status: EndpointStatus, sessionIsActive: Bool, screenSaverIsForeground: Bool,
    consoleUserPresent: Bool, now: Date = Date(), lastAttemptAt: Date?
  ) -> Bool {
    guard sessionIsActive, status.sessionState == .active, consoleUserPresent,
      !screenSaverIsForeground, status.policyDecision == .block, status.policyAction == .lock,
      let evaluatedAt = status.policyLastEvaluatedAt
    else { return false }
    let decisionAge = now.timeIntervalSince(evaluatedAt)
    guard decisionAge >= 0, decisionAge <= maximumDecisionAge else { return false }
    if let nextAllowanceAt = status.policyNextAllowanceAt, nextAllowanceAt <= now { return false }
    return lastAttemptAt.map { now.timeIntervalSince($0) >= minimumRetryInterval } ?? true
  }
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

  /// Applies the short recovery window created by an administrator-authorized package install.
  /// The installer marker is root-only and consumed once by the daemon; callers cannot extend
  /// the window beyond ten minutes.
  public func beginInstallerMaintenance(until: Date, now: Date = Date()) throws {
    guard until > now,
      until.timeIntervalSince(now) <= EndpointInstallerMaintenanceMarker.maximumDuration
    else { throw EndpointPolicyError.invalidInstallerMaintenance }
    lock.lock()
    defer { lock.unlock() }
    if state.adultOverrideUntil.map({ $0 < until }) ?? true {
      state.adultOverrideUntil = until
    }
    clearRestrictionLocked()
    try persistLocked()
  }

  public func recordRejectedTimeRequest(minutes: Int) {
    lock.lock()
    defer { lock.unlock() }
    enqueueUserEventsLocked([.timeRequestRejected(minutes: max(5, min(minutes, 240)))])
    try? persistLocked()
  }

  /// A lock does not prevent an authorized macOS login. Re-arm the current restriction when a
  /// standard child session becomes active so an unlock outside the allowed window is visibly
  /// warned/enforced again through the same allowlisted lock path.
  public func rearmRestrictionForActiveSession(now: Date = Date()) {
    lock.lock()
    defer { lock.unlock() }
    guard state.restrictionBeganAt != nil, state.restrictionEnforced == true else { return }
    guard state.lastRestrictionRearmAt.map({ now.timeIntervalSince($0) >= 2 }) ?? true else {
      return
    }
    state.restrictionEnforced = false
    state.restrictionID = UUID()
    state.lastRestrictionRearmAt = now
    try? persistLocked()
  }

  /// Records authenticated GUI activity boundaries without evaluating or enforcing policy. This
  /// prevents awake time at the Lock Screen from being charged when sleep/wake and session-active
  /// notifications arrive between the daemon's periodic evaluations.
  public func recordSessionActivity(
    _ sessionActive: Bool, now: Date = Date(),
    activeUptime: TimeInterval = EndpointActiveUseClock.uptime()
  ) {
    lock.lock()
    defer { lock.unlock() }
    guard let policy else { return }
    let day = dayKey(now, timezone: policy.timezone)
    let usageDayChanged = state.usageDay != day
    if usageDayChanged {
      state.usageDay = day
      state.activeUseSeconds = 0
      state.issuedWarnings = []
    }
    if !usageDayChanged, state.lastSessionActive == true,
      let formerActiveUptime = state.lastActiveUptime
    {
      let activeDelta = activeUptime - formerActiveUptime
      if activeDelta >= 0 { state.activeUseSeconds += min(activeDelta, 120) }
    }
    state.lastActiveUptime = activeUptime
    state.lastSessionActive = sessionActive
    try? persistLocked()
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
    return projectedRestrictionDateLocked(
      now: now, sessionActive: sessionActive, horizonMinutes: horizonMinutes)
  }

  public func allowanceSummary(
    now: Date = Date(), sessionActive: Bool, nextRestrictionAt: Date?
  ) -> EndpointAllowanceSummary? {
    lock.lock()
    defer { lock.unlock() }
    guard let policy else { return nil }
    let scheduled = PolicyEvaluator.weeklyAllowedInterval(policy, containing: now)
    let temporaryAllowanceUntil = policy.exceptions.filter {
      $0.decision == .allow && now >= $0.start && now < $0.end
    }.map(\.end).max()
    let activeUseMinutes = Int(state.activeUseSeconds / 60)
    let limitingReason = nextRestrictionAt.flatMap { restrictionAt -> String? in
      let projectedActiveSeconds = projectedActiveUseSeconds(
        at: restrictionAt, from: now, sessionActive: sessionActive, timezone: policy.timezone)
      let decision = PolicyEvaluator.evaluate(
        policy,
        input: PolicyEvaluationInput(
          at: restrictionAt, activeUseMinutes: Int(projectedActiveSeconds / 60),
          adultOverrideActive: state.adultOverrideUntil.map { $0 > restrictionAt } ?? false))
      return decision.decision == .block ? decision.reason : nil
    }
    return EndpointAllowanceSummary(
      timezone: policy.timezone, scheduledWindowStartAt: scheduled?.start,
      scheduledWindowEndAt: scheduled?.end, dailyQuotaMinutes: policy.dailyQuotaMinutes,
      bonusMinutes: policy.bonusMinutes, activeUseMinutes: activeUseMinutes,
      temporaryAllowanceUntil: temporaryAllowanceUntil, limitingReason: limitingReason)
  }

  public func projectedAllowanceDate(
    now: Date = Date(), horizonMinutes: Int = 8 * 24 * 60
  ) -> Date? {
    lock.lock()
    defer { lock.unlock() }
    guard let policy, state.clockTrusted else { return nil }
    let boundedHorizon = max(1, min(horizonMinutes, 8 * 24 * 60))
    let currentActiveMinutes = Int(state.activeUseSeconds / 60)
    let currentDay = dayKey(now, timezone: policy.timezone)
    let overrideUntil = state.adultOverrideUntil
    let current = PolicyEvaluator.evaluate(
      policy,
      input: PolicyEvaluationInput(
        at: now, activeUseMinutes: currentActiveMinutes,
        adultOverrideActive: overrideUntil.map { $0 > now } ?? false))
    guard current.decision == .block else { return nil }
    let horizonEnd = now.addingTimeInterval(TimeInterval(boundedHorizon * 60))
    var candidates = Set<Date>()
    let exactBoundaries =
      [policy.effectiveAt, policy.expiresAt].compactMap { $0 }
      + policy.blockedIntervals.flatMap { [$0.start, $0.end] }
      + policy.exceptions.flatMap { [$0.start, $0.end] }
    for boundary in exactBoundaries where boundary > now && boundary <= horizonEnd {
      candidates.insert(boundary)
    }
    for interval in PolicyEvaluator.weeklyAllowedIntervals(
      policy, intersecting: DateInterval(start: now, end: horizonEnd))
    {
      candidates.insert(interval.start)
      candidates.insert(interval.end)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: policy.timezone) ?? .current
    var day = calendar.startOfDay(for: now)
    for _ in 0..<9 {
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      if next <= horizonEnd { candidates.insert(next) }
      day = next
    }
    for future in candidates.sorted() where future > now && future <= horizonEnd {
      let projectedActiveMinutes =
        dayKey(future, timezone: policy.timezone) == currentDay ? currentActiveMinutes : 0
      let decision = PolicyEvaluator.evaluate(
        policy,
        input: PolicyEvaluationInput(
          at: future, activeUseMinutes: projectedActiveMinutes,
          adultOverrideActive: overrideUntil.map { $0 > future } ?? false))
      if decision.decision == .allow { return future }
    }
    return nil
  }

  public func claimUserEvents(limit: Int = 16, now: Date = Date()) -> [EndpointPolicyEvent] {
    lock.lock()
    defer { lock.unlock() }
    let pending = (state.pendingUserEvents ?? []).filter {
      eventIsStillValidLocked($0, now: now)
    }
    state.pendingUserEvents = pending
    let count = min(max(1, limit), min(pending.count, 32))
    guard count > 0 else { return [] }
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
    activeUptime: TimeInterval? = nil,
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
      let expiresAt = state.immediateActionExpiresAt ?? now
      events.append(
        .enforceImmediate(
          action: immediateAction, explanation: "Authenticated immediate action",
          expiresAt: expiresAt))
      state.immediateAction = nil
      state.immediateActionExpiresAt = nil
      enqueueUserEventsLocked(events)
      try? persistLocked()
      return events
    }
    guard let policy else { return [] }
    let day = dayKey(now, timezone: policy.timezone)
    let usageDayChanged = state.usageDay != day
    if usageDayChanged {
      state.usageDay = day
      state.activeUseSeconds = 0
      state.issuedWarnings = []
    }
    let currentActiveUptime = activeUptime ?? uptime
    var rebooted = false
    if let formerWall = state.lastWallClock, let formerUptime = state.lastUptime {
      let wallDelta = now.timeIntervalSince(formerWall)
      let uptimeDelta = uptime - formerUptime
      if uptimeDelta < 0 {
        // A monotonic clock cannot move backward during one boot. Treat this as an expected reboot:
        // keep the signed policy, quota, override, and grace state, then establish a new baseline.
        // Re-issue an active restriction after login because the prior boot's action is no longer
        // evidence that this session is protected.
        state.restrictionEnforced = false
        state.restrictionID = UUID()
        rebooted = true
      } else if wallDelta < -5 || abs(wallDelta - uptimeDelta) > 120 {
        if state.clockTrusted { events.append(.clockChangeDetected) }
        state.clockTrusted = false
      }
    }
    if !usageDayChanged, !rebooted, state.lastSessionActive == true,
      let formerActiveUptime = state.lastActiveUptime
    {
      let activeDelta = currentActiveUptime - formerActiveUptime
      if activeDelta >= 0 { state.activeUseSeconds += min(activeDelta, 120) }
    }
    state.lastWallClock = now
    state.lastUptime = uptime
    state.lastActiveUptime = currentActiveUptime
    state.lastSessionActive = sessionActive
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
    let remaining =
      state.adultOverrideUntil.map({ $0 > now }) == true
      ? nil
      : projectedRestrictionDateLocked(
        now: now, sessionActive: sessionActive,
        horizonMinutes: max(policy.warningOffsetsMinutes.max() ?? 0, 1)
      ).map { max(0, Int(ceil($0.timeIntervalSince(now) / 60))) }
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
        state.restrictionID = UUID()
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
      if state.restrictionID == nil { state.restrictionID = UUID() }
      if state.restrictionEnforced != true,
        immediate || elapsed >= TimeInterval(policy.gracePeriodSeconds)
      {
        events.append(
          .enforcePolicy(
            action: action, explanation: decision.reason, policyVersion: policy.version,
            restrictionID: state.restrictionID!))
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

  private func eventIsStillValidLocked(_ event: EndpointPolicyEvent, now: Date) -> Bool {
    switch event {
    case .enforce:
      return false
    case .enforceImmediate(_, _, let expiresAt):
      return expiresAt > now
    case .enforcePolicy(let action, _, let policyVersion, let restrictionID):
      guard let policy, policy.version == policyVersion,
        state.restrictionID == restrictionID, state.restrictionEnforced == true
      else { return false }
      var decision = PolicyEvaluator.evaluate(
        policy,
        input: PolicyEvaluationInput(
          at: now, activeUseMinutes: Int(state.activeUseSeconds / 60),
          adultOverrideActive: state.adultOverrideUntil.map { $0 > now } ?? false))
      if !state.clockTrusted, !(state.adultOverrideUntil.map { $0 > now } ?? false) {
        decision = PolicyDecision(
          decision: .block, action: policy.defaultAction, source: .inactivePolicy,
          reason: "Clock change detected; reconnect to refresh the signed policy")
      }
      return decision.decision == .block && decision.action == action
    default:
      return true
    }
  }

  private func projectedRestrictionDateLocked(
    now: Date, sessionActive: Bool, horizonMinutes: Int
  ) -> Date? {
    guard let policy else { return nil }
    let boundedHorizon = max(1, min(horizonMinutes, 8 * 24 * 60))
    let horizonEnd = now.addingTimeInterval(TimeInterval(boundedHorizon * 60))
    let overrideUntil = state.adultOverrideUntil
    let current = PolicyEvaluator.evaluate(
      policy,
      input: PolicyEvaluationInput(
        at: now, activeUseMinutes: Int(state.activeUseSeconds / 60),
        adultOverrideActive: overrideUntil.map { $0 > now } ?? false))
    guard current.decision == .allow else { return nil }

    var candidates = Set<Date>()
    for interval in PolicyEvaluator.weeklyAllowedIntervals(
      policy, intersecting: DateInterval(start: now, end: horizonEnd))
    {
      candidates.insert(interval.start)
      candidates.insert(interval.end)
    }
    let exactBoundaries =
      [policy.effectiveAt, policy.expiresAt, overrideUntil].compactMap { $0 }
      + policy.blockedIntervals.flatMap { [$0.start, $0.end] }
      + policy.exceptions.flatMap { [$0.start, $0.end] }
    for boundary in exactBoundaries where boundary > now && boundary <= horizonEnd {
      candidates.insert(boundary)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: policy.timezone) ?? .current
    var dayStart = calendar.startOfDay(for: now)
    let currentDay = dayKey(now, timezone: policy.timezone)
    let quotaSeconds = TimeInterval((policy.dailyQuotaMinutes + policy.bonusMinutes) * 60)
    for _ in 0..<9 {
      guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
      if nextDay > now, nextDay <= horizonEnd { candidates.insert(nextDay) }
      if sessionActive {
        let quotaBoundary =
          dayKey(dayStart, timezone: policy.timezone) == currentDay
          ? now.addingTimeInterval(max(0, quotaSeconds - state.activeUseSeconds))
          : dayStart.addingTimeInterval(quotaSeconds)
        // Daily use resets at the next policy-local midnight. A quota longer than this civil day
        // cannot become limiting before that reset.
        if quotaBoundary > now, quotaBoundary < nextDay, quotaBoundary <= horizonEnd {
          candidates.insert(quotaBoundary)
        }
      }
      dayStart = nextDay
    }

    for future in candidates.sorted() where future > now && future <= horizonEnd {
      let projectedSeconds = projectedActiveUseSeconds(
        at: future, from: now, sessionActive: sessionActive, timezone: policy.timezone)
      let decision = PolicyEvaluator.evaluate(
        policy,
        input: PolicyEvaluationInput(
          at: future, activeUseMinutes: Int(projectedSeconds / 60),
          adultOverrideActive: overrideUntil.map { $0 > future } ?? false))
      if decision.decision == .block { return future }
    }
    return nil
  }

  private func projectedActiveUseSeconds(
    at future: Date, from now: Date, sessionActive: Bool, timezone: String
  ) -> TimeInterval {
    guard sessionActive else {
      return dayKey(future, timezone: timezone) == dayKey(now, timezone: timezone)
        ? state.activeUseSeconds : 0
    }
    guard dayKey(future, timezone: timezone) != dayKey(now, timezone: timezone) else {
      return state.activeUseSeconds + max(0, future.timeIntervalSince(now))
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timezone) ?? .current
    return max(0, future.timeIntervalSince(calendar.startOfDay(for: future)))
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
    state.restrictionID = nil
    state.restrictionSource = nil
    state.restrictionAction = nil
    state.restrictionEnforced = nil
    state.lastRestrictionRearmAt = nil
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

/// Unlike `mach_continuous_time`, this clock pauses while the Mac sleeps. It is used only for
/// active-use accounting; wall-clock tamper detection continues to use the continuous clock.
public enum EndpointActiveUseClock {
  public static func uptime() -> TimeInterval {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let nanoseconds = Double(mach_absolute_time()) * Double(info.numer) / Double(info.denom)
    return nanoseconds / 1_000_000_000
  }
}
