import AppKit
import EndpointCore
import Foundation

final class SessionReporter: NSObject, @unchecked Sendable {
  private let client = EndpointXPCClient()
  private var timer: Timer?
  private var currentState: EndpointSessionState = .active
  func start() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(active), name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(inactive), name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil)
    report(.active)
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      guard let self else { return }
      report(currentState)
    }
  }
  @objc private func active() {
    currentState = .active
    report(currentState)
  }
  @objc private func inactive() {
    currentState = .inactive
    report(currentState)
  }
  private func report(_ state: EndpointSessionState) {
    client.updateSession(
      SessionUpdate(state: state, consoleUser: DeviceSnapshotCollector.consoleUser())
    ) { _ in }
  }
}

let reporter = SessionReporter()
reporter.start()
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
