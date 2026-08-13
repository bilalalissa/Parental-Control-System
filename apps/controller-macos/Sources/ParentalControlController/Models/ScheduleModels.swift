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
  case shutdown

  var id: String { rawValue }

  var title: String {
    switch self {
    case .warningOnly: "Warn only"
    case .lock: "Lock"
    case .logoff: "Log out"
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
  var action: RestrictionAction
  var windows: [WeeklyWindow]

  static let standard = ScheduleDraft(
    timezone: TimeZone.current.identifier,
    dailyQuotaMinutes: 120,
    warningMinutes: 5,
    action: .lock,
    windows: Weekday.allCases.map { WeeklyWindow(day: $0, isEnabled: $0.rawValue < 5) }
  )
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
