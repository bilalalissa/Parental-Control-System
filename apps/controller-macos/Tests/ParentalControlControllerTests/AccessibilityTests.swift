import Testing

@testable import ParentalControlController

@Suite("Accessibility contract")
struct AccessibilityTests {
  @Test("primary identifiers are unique and stable")
  func uniqueIdentifiers() {
    let values = AccessibilityID.allCases.map(\.rawValue)
    #expect(values.count == Set(values).count)
    #expect(values.contains("controller.main-window"))
    #expect(values.contains("schedule.save"))
    #expect(values.contains("settings.start-at-login"))
    #expect(values.contains("chat.audience"))
    #expect(values.contains("chat.add-local-preview"))
  }
}
