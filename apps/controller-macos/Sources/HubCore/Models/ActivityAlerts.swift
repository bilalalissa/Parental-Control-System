import Foundation

public enum HubActivityAlertKind: String, CaseIterable, Equatable, Hashable, Sendable {
  case youtube
  case possibleGame

  public var title: String {
    switch self {
    case .youtube: "YouTube"
    case .possibleGame: "Possible game"
    }
  }
}

public struct HubActivityAlertObservation: Equatable, Sendable {
  public let kind: HubActivityAlertKind
  public let deviceID: String
  public let key: String
  public let observedAt: Date

  public init(kind: HubActivityAlertKind, deviceID: String, key: String, observedAt: Date) {
    self.kind = kind
    self.deviceID = deviceID
    self.key = key
    self.observedAt = observedAt
  }
}

public enum HubActivityAlertClassifier {
  private static let gameDomains = [
    "chess.com", "crazygames.com", "epicgames.com", "itch.io", "miniclip.com", "poki.com",
    "roblox.com",
  ]
  private static let gameMarkers = [
    "battle.net", "battlenet", "blizzard", "epicgames", "fortnite", "goggalaxy", "minecraft",
    "mojang", "riotclient", "riotgames", "roblox", "steam",
  ]

  public static func kind(for tab: HubBrowserTab) -> HubActivityAlertKind? {
    guard let host = URLComponents(string: tab.origin)?.host?.lowercased() else { return nil }
    if domain(host, matches: "youtube.com") || domain(host, matches: "youtu.be") {
      return .youtube
    }
    if gameDomains.contains(where: { domain(host, matches: $0) }) {
      return .possibleGame
    }
    let labels = Set(host.split(separator: ".").map(String.init))
    return labels.contains("game") || labels.contains("games") || labels.contains("gaming")
      ? .possibleGame : nil
  }

  public static func kind(for application: HubAppActivity) -> HubActivityAlertKind? {
    let name = application.applicationName.lowercased()
    let bundle = application.bundleIdentifier.lowercased()
    let compact = (name + bundle).filter(\.isLetter)
    if gameMarkers.contains(where: { marker in
      let compactMarker = marker.filter(\.isLetter)
      return name.contains(marker) || bundle.contains(marker) || compact.contains(compactMarker)
    }) {
      return .possibleGame
    }
    let tokens = Set(
      (name + "." + bundle).split { !$0.isLetter && !$0.isNumber }.map(String.init))
    return !tokens.isDisjoint(with: ["game", "games", "gaming"])
      ? .possibleGame : nil
  }

  public static func observations(
    activity: [HubAppActivity], tabs: [HubBrowserTab]
  ) -> [HubActivityAlertObservation] {
    let appObservations = activity.compactMap { application -> HubActivityAlertObservation? in
      guard let kind = kind(for: application) else { return nil }
      return HubActivityAlertObservation(
        kind: kind, deviceID: application.deviceID, key: "app|\(application.id)",
        observedAt: application.observedAt)
    }
    let tabObservations = tabs.compactMap { tab -> HubActivityAlertObservation? in
      guard let kind = kind(for: tab) else { return nil }
      return HubActivityAlertObservation(
        kind: kind, deviceID: tab.deviceID, key: "tab|\(tab.id)", observedAt: tab.observedAt)
    }
    return appObservations + tabObservations
  }

  private static func domain(_ host: String, matches domain: String) -> Bool {
    host == domain || host.hasSuffix(".\(domain)")
  }
}

public struct HubActivityAlertTracker: Sendable {
  private var latestObservationByKey: [String: Date] = [:]
  private var lastNotificationByDeviceAndKind: [String: Date] = [:]
  private var hasLoadedStatus = false
  private let cooldown: TimeInterval

  public init(cooldown: TimeInterval = 30 * 60) {
    self.cooldown = max(60, cooldown)
  }

  public mutating func newlyAlertingObservations(
    activity: [HubAppActivity], tabs: [HubBrowserTab], now: Date = Date()
  ) -> [HubActivityAlertObservation] {
    let observations = HubActivityAlertClassifier.observations(activity: activity, tabs: tabs)
    let currentKeys = Set(observations.map(\.key))
    let previous = latestObservationByKey
    latestObservationByKey = Dictionary(
      uniqueKeysWithValues: observations.map { ($0.key, $0.observedAt) })
    defer { hasLoadedStatus = true }
    guard hasLoadedStatus else { return [] }

    let changed = observations.filter { observation in
      guard let previousDate = previous[observation.key] else { return true }
      return observation.observedAt > previousDate
    }
    var result: [HubActivityAlertObservation] = []
    for observation in changed.sorted(by: { $0.observedAt < $1.observedAt }) {
      let group = "\(observation.deviceID)|\(observation.kind.rawValue)"
      if let lastNotification = lastNotificationByDeviceAndKind[group],
        now.timeIntervalSince(lastNotification) < cooldown
      {
        continue
      }
      lastNotificationByDeviceAndKind[group] = now
      result.append(observation)
    }

    if lastNotificationByDeviceAndKind.count > 256 {
      lastNotificationByDeviceAndKind = Dictionary(
        uniqueKeysWithValues: lastNotificationByDeviceAndKind.sorted { $0.value > $1.value }
          .prefix(256).map { ($0.key, $0.value) })
    }
    latestObservationByKey = latestObservationByKey.filter { currentKeys.contains($0.key) }
    return result
  }
}
