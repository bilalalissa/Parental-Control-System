import Foundation
import Testing

@testable import HubCore

@Suite("activity alerts")
struct ActivityAlertTests {
  @Test("YouTube and game classification uses only shared origins and app identity")
  func classification() {
    let youtube = HubBrowserTab(
      deviceID: "child", browser: "arc", profileID: "profile", title: "A video",
      origin: "https://www.youtube.com", isActive: true)
    let game = HubBrowserTab(
      deviceID: "child", browser: "arc", profileID: "profile", title: "Play",
      origin: "https://games.example.test", isActive: true)
    let ordinary = HubBrowserTab(
      deviceID: "child", browser: "arc", profileID: "profile", title: "Lessons",
      origin: "https://www.khanacademy.org", isActive: true)
    let steam = HubAppActivity(
      deviceID: "child", bundleIdentifier: "com.valvesoftware.steam", applicationName: "Steam",
      isForeground: true)

    #expect(HubActivityAlertClassifier.kind(for: youtube) == .youtube)
    #expect(HubActivityAlertClassifier.kind(for: game) == .possibleGame)
    #expect(HubActivityAlertClassifier.kind(for: ordinary) == nil)
    #expect(HubActivityAlertClassifier.kind(for: steam) == .possibleGame)
  }

  @Test("activity notifications prime existing status and enforce a per-kind cooldown")
  func boundedNotifications() {
    let start = Date(timeIntervalSince1970: 1_000)
    func youtube(at date: Date) -> HubBrowserTab {
      HubBrowserTab(
        deviceID: "child", browser: "arc", profileID: "profile", title: "A video",
        origin: "https://youtube.com", isActive: true, observedAt: date)
    }
    var tracker = HubActivityAlertTracker(cooldown: 60)

    #expect(
      tracker.newlyAlertingObservations(activity: [], tabs: [youtube(at: start)], now: start)
        .isEmpty)
    let first = tracker.newlyAlertingObservations(
      activity: [], tabs: [youtube(at: start.addingTimeInterval(1))],
      now: start.addingTimeInterval(1))
    #expect(first.map(\.kind) == [.youtube])
    #expect(
      tracker.newlyAlertingObservations(
        activity: [], tabs: [youtube(at: start.addingTimeInterval(2))],
        now: start.addingTimeInterval(2)
      ).isEmpty)
    #expect(
      tracker.newlyAlertingObservations(
        activity: [], tabs: [youtube(at: start.addingTimeInterval(62))],
        now: start.addingTimeInterval(62)
      ).map(\.kind) == [.youtube])
  }
}
