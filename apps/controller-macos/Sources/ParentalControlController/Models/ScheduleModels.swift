import Foundation

enum Weekday: Int, CaseIterable, Codable, Identifiable, Sendable {
  case monday = 0
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday
  case sunday

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .monday: "Monday"
    case .tuesday: "Tuesday"
    case .wednesday: "Wednesday"
    case .thursday: "Thursday"
    case .friday: "Friday"
    case .saturday: "Saturday"
    case .sunday: "Sunday"
    }
  }

  var shortTitle: String { String(title.prefix(3)) }
}

enum RestrictionAction: String, CaseIterable, Codable, Identifiable, Sendable {
  case warningOnly
  case lock
  case logoff
  case restart
  case shutdown

  var id: String { rawValue }

  var title: String {
    switch self {
    case .warningOnly: "Warn only"
    case .lock: "Lock"
    case .logoff: "Log out"
    case .restart: "Restart"
    case .shutdown: "Shut down"
    }
  }
}

struct WeeklyWindow: Identifiable, Codable, Equatable, Sendable {
  var id: UUID
  var day: Weekday
  var startMinute: Int
  var endMinute: Int
  var isEnabled: Bool

  init(
    id: UUID = UUID(),
    day: Weekday,
    startMinute: Int = 8 * 60,
    endMinute: Int = 20 * 60,
    isEnabled: Bool = true
  ) {
    self.id = id
    self.day = day
    self.startMinute = startMinute
    self.endMinute = endMinute
    self.isEnabled = isEnabled
  }

  var startLabel: String { Self.timeLabel(minutes: startMinute) }
  var endLabel: String { Self.timeLabel(minutes: endMinute) }

  static func timeLabel(minutes: Int) -> String {
    let normalized = max(0, min(minutes, 1439))
    return String(format: "%02d:%02d", normalized / 60, normalized % 60)
  }
}

struct ScheduleDraft: Codable, Equatable, Sendable {
  var timezone: String
  var dailyQuotaMinutes: Int
  var warningMinutes: Int
  var bonusMinutes: Int
  var bonusUntil: Date?
  var gracePeriodSeconds: Int
  var action: RestrictionAction
  var windows: [WeeklyWindow]

  init(
    timezone: String, dailyQuotaMinutes: Int, warningMinutes: Int, bonusMinutes: Int,
    bonusUntil: Date? = nil,
    gracePeriodSeconds: Int, action: RestrictionAction, windows: [WeeklyWindow]
  ) {
    self.timezone = timezone
    self.dailyQuotaMinutes = dailyQuotaMinutes
    self.warningMinutes = warningMinutes
    self.bonusMinutes = bonusMinutes
    self.bonusUntil = bonusUntil
    self.gracePeriodSeconds = gracePeriodSeconds
    self.action = action
    self.windows = windows
  }

  static let standard = ScheduleDraft(
    timezone: TimeZone.current.identifier,
    dailyQuotaMinutes: 120,
    warningMinutes: 5,
    bonusMinutes: 0,
    gracePeriodSeconds: 60,
    action: .lock,
    windows: Weekday.allCases.map { WeeklyWindow(day: $0, isEnabled: $0.rawValue < 5) }
  )

  private enum CodingKeys: String, CodingKey {
    case timezone, dailyQuotaMinutes, warningMinutes, bonusMinutes, bonusUntil, gracePeriodSeconds,
      action,
      windows
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    timezone = try values.decode(String.self, forKey: .timezone)
    dailyQuotaMinutes = try values.decode(Int.self, forKey: .dailyQuotaMinutes)
    warningMinutes = try values.decode(Int.self, forKey: .warningMinutes)
    bonusMinutes = try values.decodeIfPresent(Int.self, forKey: .bonusMinutes) ?? 0
    bonusUntil = try values.decodeIfPresent(Date.self, forKey: .bonusUntil)
    gracePeriodSeconds = try values.decodeIfPresent(Int.self, forKey: .gracePeriodSeconds) ?? 60
    action = try values.decode(RestrictionAction.self, forKey: .action)
    windows = try values.decode([WeeklyWindow].self, forKey: .windows)
  }

  mutating func approveRequestedTime(minutes: Int, now: Date = Date()) {
    let bounded = max(5, min(minutes, 240))
    bonusMinutes = max(0, min(1_440, bonusMinutes + bounded))
    let start = max(now, bonusUntil ?? now)
    bonusUntil = start.addingTimeInterval(TimeInterval(bounded * 60))
  }
}

enum ScheduleValidationIssue: Equatable, Sendable {
  case quotaOutOfRange
  case warningOutOfRange
  case invalidTime(day: Weekday)
  case noEnabledWindow
  case overlappingWindows

  var message: String {
    switch self {
    case .quotaOutOfRange: "Daily quota must be between 1 minute and 24 hours."
    case .warningOutOfRange: "Warning time must be between 1 and 60 minutes."
    case .invalidTime(let day):
      "The enabled window for \(day.title) must use valid, different start and end times."
    case .noEnabledWindow: "Enable at least one weekly window."
    case .overlappingWindows: "Enabled windows must not overlap, including across midnight."
    }
  }
}

enum ScheduleValidator {
  private struct Interval {
    let id: UUID
    let start: Int
    let end: Int
  }

  static func validate(_ draft: ScheduleDraft) -> [ScheduleValidationIssue] {
    var issues: [ScheduleValidationIssue] = []
    if !(1...1440).contains(draft.dailyQuotaMinutes) { issues.append(.quotaOutOfRange) }
    if !(1...60).contains(draft.warningMinutes) { issues.append(.warningOutOfRange) }

    let enabled = draft.windows.filter(\.isEnabled)
    if enabled.isEmpty { issues.append(.noEnabledWindow) }
    for window in enabled
    where !(0..<1440).contains(window.startMinute) || !(0..<1440).contains(window.endMinute)
      || window.startMinute == window.endMinute
    {
      issues.append(.invalidTime(day: window.day))
    }

    let weekMinutes = 7 * 1440
    var intervals: [Interval] = []
    for window in enabled where window.startMinute != window.endMinute {
      let start = window.day.rawValue * 1440 + window.startMinute
      var end = window.day.rawValue * 1440 + window.endMinute
      if end <= start { end += 1440 }
      if end <= weekMinutes {
        intervals.append(Interval(id: window.id, start: start, end: end))
      } else {
        intervals.append(Interval(id: window.id, start: start, end: weekMinutes))
        intervals.append(Interval(id: window.id, start: 0, end: end - weekMinutes))
      }
    }

    let sorted = intervals.sorted { lhs, rhs in
      lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
    }
    if zip(sorted, sorted.dropFirst()).contains(where: { first, second in
      first.id != second.id && second.start < first.end
    }) {
      issues.append(.overlappingWindows)
    }
    return issues
  }
}
