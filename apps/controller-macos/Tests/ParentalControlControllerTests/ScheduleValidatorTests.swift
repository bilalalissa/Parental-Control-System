import Foundation
import Testing

@testable import ParentalControlController

@Suite("Schedule validation")
struct ScheduleValidatorTests {
  @Test("standard schedule is valid and defaults to lock")
  func standardSchedule() {
    let schedule = ScheduleDraft.standard
    #expect(schedule.action == .lock)
    #expect(ScheduleValidator.validate(schedule).isEmpty)
  }

  @Test("quota and warning bounds are enforced")
  func numericBounds() {
    var schedule = ScheduleDraft.standard
    schedule.dailyQuotaMinutes = 0
    schedule.warningMinutes = 61
    let issues = ScheduleValidator.validate(schedule)
    #expect(issues.contains(.quotaOutOfRange))
    #expect(issues.contains(.warningOutOfRange))
  }

  @Test("at least one enabled window is required")
  func noEnabledWindows() {
    var schedule = ScheduleDraft.standard
    for index in schedule.windows.indices {
      schedule.windows[index].isEnabled = false
    }
    #expect(ScheduleValidator.validate(schedule).contains(.noEnabledWindow))
  }

  @Test("same-day overlap is rejected")
  func sameDayOverlap() {
    var schedule = ScheduleDraft.standard
    schedule.windows = [
      WeeklyWindow(day: .monday, startMinute: 8 * 60, endMinute: 12 * 60),
      WeeklyWindow(day: .monday, startMinute: 11 * 60, endMinute: 13 * 60),
    ]
    #expect(ScheduleValidator.validate(schedule).contains(.overlappingWindows))
  }

  @Test("cross-midnight overlap is rejected")
  func crossMidnightOverlap() {
    var schedule = ScheduleDraft.standard
    schedule.windows = [
      WeeklyWindow(day: .friday, startMinute: 20 * 60, endMinute: 60),
      WeeklyWindow(day: .saturday, startMinute: 30, endMinute: 2 * 60),
    ]
    #expect(ScheduleValidator.validate(schedule).contains(.overlappingWindows))
  }

  @Test("adjacent windows do not overlap")
  func adjacentWindows() {
    var schedule = ScheduleDraft.standard
    schedule.windows = [
      WeeklyWindow(day: .monday, startMinute: 8 * 60, endMinute: 12 * 60),
      WeeklyWindow(day: .monday, startMinute: 12 * 60, endMinute: 14 * 60),
    ]
    #expect(!ScheduleValidator.validate(schedule).contains(.overlappingWindows))
  }

  @Test("approved request extends quota and creates a bounded allow interval")
  func approvedRequestedTime() {
    var schedule = ScheduleDraft.standard
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    schedule.approveRequestedTime(minutes: 15, now: now)
    #expect(schedule.bonusMinutes == 15)
    #expect(schedule.bonusUntil == now.addingTimeInterval(15 * 60))
    schedule.approveRequestedTime(minutes: 15, now: now.addingTimeInterval(60))
    #expect(schedule.bonusMinutes == 30)
    #expect(schedule.bonusUntil == now.addingTimeInterval(30 * 60))
  }
}
