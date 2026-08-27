import CryptoKit
import Foundation

public enum PolicyAction: String, Codable, CaseIterable, Sendable {
  case warningOnly
  case lock
  case logoff
  case restart
  case shutdown
}

public enum PolicyWeekday: String, Codable, CaseIterable, Sendable {
  case monday = "Monday"
  case tuesday = "Tuesday"
  case wednesday = "Wednesday"
  case thursday = "Thursday"
  case friday = "Friday"
  case saturday = "Saturday"
  case sunday = "Sunday"

  fileprivate var calendarWeekday: Int {
    switch self {
    case .sunday: 1
    case .monday: 2
    case .tuesday: 3
    case .wednesday: 4
    case .thursday: 5
    case .friday: 6
    case .saturday: 7
    }
  }

  fileprivate static func from(calendarWeekday: Int) -> PolicyWeekday? {
    allCases.first { $0.calendarWeekday == calendarWeekday }
  }
}

public struct PolicyWeeklyWindow: Codable, Equatable, Sendable {
  public let day: PolicyWeekday
  public let start: String
  public let end: String

  public init(day: PolicyWeekday, start: String, end: String) {
    self.day = day
    self.start = start
    self.end = end
  }
}

public struct PolicyBlockedInterval: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let start: Date
  public let end: Date
  public let action: PolicyAction
  public let reason: String

  public init(
    id: UUID = UUID(), start: Date, end: Date, action: PolicyAction, reason: String
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.action = action
    self.reason = String(reason.prefix(200))
  }
}

public enum PolicyExceptionDecision: String, Codable, Sendable {
  case allow
  case block
}

public struct PolicyException: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let start: Date
  public let end: Date
  public let decision: PolicyExceptionDecision
  public let action: PolicyAction?
  public let reason: String

  public init(
    id: UUID = UUID(), start: Date, end: Date, decision: PolicyExceptionDecision,
    action: PolicyAction? = nil, reason: String
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.decision = decision
    self.action = action
    self.reason = String(reason.prefix(200))
  }
}

public struct PolicySignature: Codable, Equatable, Sendable {
  public let algorithm: String
  public let keyID: String
  public let value: String

  public init(algorithm: String = "Ed25519", keyID: String, value: String) {
    self.algorithm = algorithm
    self.keyID = keyID
    self.value = value
  }

  enum CodingKeys: String, CodingKey {
    case algorithm
    case keyID = "keyId"
    case value
  }
}

public struct ParentalControlPolicy: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID { policyID }
  public let policyID: UUID
  public let version: UInt64
  public let deviceID: String
  public let timezone: String
  public let effectiveAt: Date
  public let expiresAt: Date?
  public let defaultAction: PolicyAction
  public let warningOffsetsMinutes: [Int]
  public let gracePeriodSeconds: Int
  public let weeklyAllowed: [PolicyWeeklyWindow]
  public let blockedIntervals: [PolicyBlockedInterval]
  public let exceptions: [PolicyException]
  public let dailyQuotaMinutes: Int
  public let bonusMinutes: Int
  public let childExplanation: String
  public let signature: PolicySignature

  public init(
    policyID: UUID = UUID(), version: UInt64, deviceID: String, timezone: String,
    effectiveAt: Date = Date(), expiresAt: Date? = nil, defaultAction: PolicyAction = .lock,
    warningOffsetsMinutes: [Int] = [15, 5, 1], gracePeriodSeconds: Int = 60,
    weeklyAllowed: [PolicyWeeklyWindow], blockedIntervals: [PolicyBlockedInterval] = [],
    exceptions: [PolicyException] = [], dailyQuotaMinutes: Int, bonusMinutes: Int = 0,
    childExplanation: String, signature: PolicySignature
  ) {
    self.policyID = policyID
    self.version = version
    self.deviceID = String(deviceID.prefix(128))
    self.timezone = timezone
    self.effectiveAt = effectiveAt
    self.expiresAt = expiresAt
    self.defaultAction = defaultAction
    self.warningOffsetsMinutes = Array(
      Set(warningOffsetsMinutes.filter { (1...1440).contains($0) })
    ).sorted(by: >).prefix(8).map { $0 }
    self.gracePeriodSeconds = max(0, min(gracePeriodSeconds, 900))
    self.weeklyAllowed = Array(weeklyAllowed.prefix(64))
    self.blockedIntervals = Array(blockedIntervals.prefix(64))
    self.exceptions = Array(exceptions.prefix(64))
    self.dailyQuotaMinutes = max(0, min(dailyQuotaMinutes, 1440))
    self.bonusMinutes = max(0, min(bonusMinutes, 1440))
    self.childExplanation = String(childExplanation.prefix(500))
    self.signature = signature
  }

  enum CodingKeys: String, CodingKey {
    case policyID = "policyId"
    case version
    case deviceID = "deviceId"
    case timezone, effectiveAt, expiresAt, defaultAction, warningOffsetsMinutes
    case gracePeriodSeconds, weeklyAllowed, blockedIntervals, exceptions
    case dailyQuotaMinutes, bonusMinutes, childExplanation, signature
  }

  public func replacing(
    version: UInt64? = nil, bonusMinutes: Int? = nil, signature: PolicySignature? = nil
  ) -> ParentalControlPolicy {
    ParentalControlPolicy(
      policyID: policyID, version: version ?? self.version, deviceID: deviceID,
      timezone: timezone, effectiveAt: effectiveAt, expiresAt: expiresAt,
      defaultAction: defaultAction, warningOffsetsMinutes: warningOffsetsMinutes,
      gracePeriodSeconds: gracePeriodSeconds, weeklyAllowed: weeklyAllowed,
      blockedIntervals: blockedIntervals, exceptions: exceptions,
      dailyQuotaMinutes: dailyQuotaMinutes, bonusMinutes: bonusMinutes ?? self.bonusMinutes,
      childExplanation: childExplanation, signature: signature ?? self.signature)
  }
}

public enum PolicyDecisionKind: String, Codable, Sendable {
  case allow
  case block
}

public enum PolicyDecisionSource: String, Codable, Sendable {
  case adultOverride
  case immediateCommand
  case exception
  case blockedInterval
  case dailyQuota
  case weeklyWindow
  case defaultPolicy = "default"
  case inactivePolicy
}

public struct PolicyDecision: Codable, Equatable, Sendable {
  public let decision: PolicyDecisionKind
  public let action: PolicyAction?
  public let source: PolicyDecisionSource
  public let reason: String

  public init(
    decision: PolicyDecisionKind, action: PolicyAction? = nil, source: PolicyDecisionSource,
    reason: String
  ) {
    self.decision = decision
    self.action = action
    self.source = source
    self.reason = String(reason.prefix(500))
  }
}

public struct PolicyEvaluationInput: Sendable {
  public let at: Date
  public let activeUseMinutes: Int
  public let adultOverrideActive: Bool
  public let immediateAction: PolicyAction?

  public init(
    at: Date, activeUseMinutes: Int, adultOverrideActive: Bool = false,
    immediateAction: PolicyAction? = nil
  ) {
    self.at = at
    self.activeUseMinutes = max(0, activeUseMinutes)
    self.adultOverrideActive = adultOverrideActive
    self.immediateAction = immediateAction
  }
}

public enum PolicyEvaluator {
  public static func evaluate(
    _ policy: ParentalControlPolicy, input: PolicyEvaluationInput
  ) -> PolicyDecision {
    if input.adultOverrideActive {
      return PolicyDecision(
        decision: .allow, source: .adultOverride, reason: "Temporary adult override is active")
    }
    if let action = input.immediateAction {
      return PolicyDecision(
        decision: action == .warningOnly ? .allow : .block, action: action,
        source: .immediateCommand, reason: "Authenticated immediate action")
    }
    guard input.at >= policy.effectiveAt,
      policy.expiresAt.map({ input.at < $0 }) ?? true
    else {
      return PolicyDecision(
        decision: .block, action: policy.defaultAction, source: .inactivePolicy,
        reason: "The signed policy is not currently valid")
    }
    if let exception = policy.exceptions.first(where: {
      input.at >= $0.start && input.at < $0.end
    }) {
      return PolicyDecision(
        decision: exception.decision == .allow ? .allow : .block,
        action: exception.decision == .block ? (exception.action ?? policy.defaultAction) : nil,
        source: .exception, reason: exception.reason)
    }
    if let interval = policy.blockedIntervals.first(where: {
      input.at >= $0.start && input.at < $0.end
    }) {
      return PolicyDecision(
        decision: .block, action: interval.action, source: .blockedInterval,
        reason: interval.reason)
    }
    if input.activeUseMinutes >= policy.dailyQuotaMinutes + policy.bonusMinutes {
      return PolicyDecision(
        decision: .block, action: policy.defaultAction, source: .dailyQuota,
        reason: "Daily active-use quota reached")
    }
    if isInsideWeeklyWindow(policy, at: input.at) {
      return PolicyDecision(
        decision: .allow, source: .weeklyWindow, reason: policy.childExplanation)
    }
    return PolicyDecision(
      decision: policy.defaultAction == .warningOnly ? .allow : .block,
      action: policy.defaultAction, source: .defaultPolicy, reason: policy.childExplanation)
  }

  public static func warningOffset(
    _ policy: ParentalControlPolicy, remainingMinutes: Int, alreadyIssued: Set<Int>
  ) -> Int? {
    policy.warningOffsetsMinutes.sorted(by: >).first {
      remainingMinutes <= $0 && !alreadyIssued.contains($0)
    }
  }

  private static func isInsideWeeklyWindow(_ policy: ParentalControlPolicy, at date: Date) -> Bool {
    guard let zone = TimeZone(identifier: policy.timezone) else { return false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
    guard let weekdayNumber = components.weekday,
      let weekday = PolicyWeekday.from(calendarWeekday: weekdayNumber),
      let hour = components.hour, let minute = components.minute
    else { return false }
    let localMinute = hour * 60 + minute
    for window in policy.weeklyAllowed {
      guard let start = minutes(window.start), let end = minutes(window.end), start != end else {
        continue
      }
      if start < end, window.day == weekday, localMinute >= start, localMinute < end {
        return true
      }
      if start > end {
        if window.day == weekday, localMinute >= start { return true }
        let prior = calendar.date(byAdding: .day, value: -1, to: date).flatMap {
          PolicyWeekday.from(calendarWeekday: calendar.component(.weekday, from: $0))
        }
        if window.day == prior, localMinute < end { return true }
      }
    }
    return false
  }

  private static func minutes(_ value: String) -> Int? {
    let values = value.split(separator: ":", omittingEmptySubsequences: false)
    guard values.count == 2, let hour = Int(values[0]), let minute = Int(values[1]),
      (0...23).contains(hour), (0...59).contains(minute)
    else { return nil }
    return hour * 60 + minute
  }
}

public enum PolicySignatureError: Error, Equatable {
  case unsupportedAlgorithm
  case invalidKeyID
  case invalidSignature
  case invalidPolicy
}

public enum PolicyCodec {
  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  public static func signingData(for policy: ParentalControlPolicy) throws -> Data {
    try encoder().encode(
      policy.replacing(
        signature: PolicySignature(
          algorithm: policy.signature.algorithm, keyID: policy.signature.keyID, value: "")))
  }

  public static func verify(
    _ policy: ParentalControlPolicy, publicKey: Data, expectedKeyID: String
  ) throws {
    guard policy.signature.algorithm == "Ed25519" else {
      throw PolicySignatureError.unsupportedAlgorithm
    }
    guard policy.signature.keyID == expectedKeyID else { throw PolicySignatureError.invalidKeyID }
    guard !policy.deviceID.isEmpty, policy.version > 0,
      TimeZone(identifier: policy.timezone) != nil, !policy.childExplanation.isEmpty,
      policy.blockedIntervals.allSatisfy({ $0.start < $0.end }),
      policy.exceptions.allSatisfy({ $0.start < $0.end }),
      let signature = Data(base64Encoded: policy.signature.value),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      key.isValidSignature(signature, for: try signingData(for: policy))
    else { throw PolicySignatureError.invalidSignature }
  }
}
