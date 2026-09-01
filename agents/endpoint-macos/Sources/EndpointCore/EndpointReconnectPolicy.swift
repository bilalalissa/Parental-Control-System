import Foundation

public enum EndpointReconnectAction: Equatable, Sendable {
  case connect(retryAfter: TimeInterval)
  case reconnect
  case wait(TimeInterval)
}

/// Keeps reconnects prompt after an established LAN connection is lost while bounding failures.
public struct EndpointReconnectPolicy: Sendable {
  public let maximumShortAttempts: Int
  public let shortDelay: TimeInterval
  public let cooldown: TimeInterval
  public let onlinePollInterval: TimeInterval
  public let controllerContactTimeout: TimeInterval

  private var attempts = 0

  public init(
    maximumShortAttempts: Int = 3, shortDelay: TimeInterval = 2,
    cooldown: TimeInterval = 60, onlinePollInterval: TimeInterval = 15,
    controllerContactTimeout: TimeInterval = 90
  ) {
    self.maximumShortAttempts = max(1, maximumShortAttempts)
    self.shortDelay = max(1, shortDelay)
    self.cooldown = max(self.shortDelay, cooldown)
    self.onlinePollInterval = max(5, onlinePollInterval)
    self.controllerContactTimeout = max(self.onlinePollInterval * 2, controllerContactTimeout)
  }

  public mutating func timerFired(connectionState: EndpointConnectionState)
    -> EndpointReconnectAction
  {
    timerFired(
      connectionState: connectionState,
      lastControllerContact: connectionState == .online ? Date() : nil)
  }

  public mutating func timerFired(
    connectionState: EndpointConnectionState, lastControllerContact: Date?, now: Date = Date()
  ) -> EndpointReconnectAction {
    if connectionState == .online {
      guard let lastControllerContact else { return .reconnect }
      let age = now.timeIntervalSince(lastControllerContact)
      guard age >= -5, age <= controllerContactTimeout else { return .reconnect }
      attempts = 0
      return .wait(onlinePollInterval)
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
