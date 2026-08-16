import Foundation

public enum EndpointReconnectAction: Equatable, Sendable {
  case connect(retryAfter: TimeInterval)
  case wait(TimeInterval)
}

/// Keeps reconnects prompt after an established LAN connection is lost while bounding failures.
public struct EndpointReconnectPolicy: Sendable {
  public let maximumShortAttempts: Int
  public let shortDelay: TimeInterval
  public let cooldown: TimeInterval

  private var attempts = 0

  public init(
    maximumShortAttempts: Int = 3, shortDelay: TimeInterval = 2,
    cooldown: TimeInterval = 60
  ) {
    self.maximumShortAttempts = max(1, maximumShortAttempts)
    self.shortDelay = max(1, shortDelay)
    self.cooldown = max(self.shortDelay, cooldown)
  }

  public mutating func timerFired(connectionState: EndpointConnectionState)
    -> EndpointReconnectAction
  {
    if connectionState == .online {
      attempts = 0
      return .wait(cooldown)
    }
    guard attempts < maximumShortAttempts else {
      attempts = 0
      return .wait(cooldown)
    }
    attempts += 1
    return .connect(retryAfter: shortDelay)
  }

  /// An authenticated connection that closes should not wait for the online idle timer.
  public mutating func establishedConnectionLost() -> TimeInterval {
    attempts = 0
    return 0
  }
}
