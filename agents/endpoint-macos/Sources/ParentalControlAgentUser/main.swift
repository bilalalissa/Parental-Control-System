import AVFoundation
import AppKit
import CoreFoundation
import CoreServices
import EndpointCore
import Foundation

private func policyWakeCallback(
  _: CFNotificationCenter?, observer: UnsafeMutableRawPointer?, _: CFNotificationName?,
  _: UnsafeRawPointer?, _: CFDictionary?
) {
  guard let observer else { return }
  let reporter = Unmanaged<SessionReporter>.fromOpaque(observer).takeUnretainedValue()
  reporter.policyEventsAvailable()
}

final class SessionReporter: NSObject, @unchecked Sendable {
  private let client = EndpointXPCClient()
  private var timer: Timer?
  private var currentState: EndpointSessionState = .active
  private let speechSynthesizer = AVSpeechSynthesizer()
  private var knownParentMessageIDs: Set<UUID> = []
  private var messagesPrimed = false
  private var policyBanner: NSPanel?
  func start() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(active), name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(inactive), name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(inactive), name: NSWorkspace.willSleepNotification, object: nil)
    center.addObserver(
      self, selector: #selector(active), name: NSWorkspace.didWakeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(applicationsChanged),
      name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    center.addObserver(
      self, selector: #selector(applicationsChanged),
      name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    center.addObserver(
      self, selector: #selector(applicationsChanged),
      name: NSWorkspace.didActivateApplicationNotification, object: nil)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(chatReceived),
      name: Notification.Name("com.bilalalissa.ParentalControlAgent.chat-received"), object: nil)
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      policyWakeCallback,
      EndpointPolicyWake.name as CFString,
      nil,
      .deliverImmediately)
    report(.active)
    reportApplications()
    primeMessages()
    claimPolicyEvents()
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      guard let self else { return }
      report(currentState)
      claimPolicyEvents()
    }
  }
  deinit {
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      CFNotificationName(EndpointPolicyWake.name as CFString),
      nil)
  }

  fileprivate func policyEventsAvailable() {
    DispatchQueue.main.async { [weak self] in self?.claimPolicyEvents() }
  }
  @objc private func active() {
    currentState = .active
    report(currentState)
  }
  @objc private func inactive() {
    currentState = .inactive
    report(currentState)
  }
  @objc private func applicationsChanged() { reportApplications() }
  @objc private func chatReceived() {
    // A raw LaunchAgent has no application bundle registration for UserNotifications. Calling
    // UNUserNotificationCenter.current() here asserts on macOS and makes launchd crash-loop the
    // helper. Use the ordinary sound-effects path; the visible child app owns notification UI.
    NSSound.beep()
    speakNewAnnouncements()
  }
  private func claimPolicyEvents() {
    client.claimPolicyEvents { [weak self] result in
      guard case .success(let events) = result else { return }
      DispatchQueue.main.async { [weak self] in
        for event in events { self?.handlePolicyEvent(event) }
      }
    }
  }

  @MainActor private func handlePolicyEvent(_ event: EndpointPolicyEvent) {
    NSSound.beep()
    switch event {
    case .warning(let minutes, let action, let explanation):
      showPolicyBanner(
        title: "Time warning",
        message:
          "\(minutes) minute\(minutes == 1 ? "" : "s") until \(action.rawValue). \(explanation)")
    case .enforce(let action, _):
      perform(action.rawValue)
    case .clockChangeDetected:
      showPolicyBanner(
        title: "Time settings changed",
        message: "Reconnect to the parent controller to refresh the signed schedule.")
    case .bonusGranted(let minutes, let until):
      showPolicyBanner(
        title: "More time approved",
        message:
          "\(minutes) minute\(minutes == 1 ? "" : "s") approved, until \(until.formatted(date: .omitted, time: .shortened))."
      )
    }
  }

  @MainActor private func showPolicyBanner(title: String, message: String) {
    policyBanner?.orderOut(nil)
    NSApplication.shared.setActivationPolicy(.accessory)
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 390, height: 116),
      styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = title
    panel.level = .floating
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .boldSystemFont(ofSize: 15)
    let messageLabel = NSTextField(wrappingLabelWithString: message)
    messageLabel.font = .systemFont(ofSize: 13)
    messageLabel.maximumNumberOfLines = 3
    let stack = NSStackView(views: [titleLabel, messageLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    let content = NSView()
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
    ])
    panel.contentView = content
    if let frame = NSScreen.main?.visibleFrame {
      panel.setFrameOrigin(
        NSPoint(x: frame.maxX - panel.frame.width - 18, y: frame.maxY - panel.frame.height - 18))
    }
    policyBanner = panel
    panel.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak panel] in
      guard let self, let panel, self.policyBanner === panel else { return }
      panel.orderOut(nil)
      self.policyBanner = nil
      NSApplication.shared.setActivationPolicy(.prohibited)
    }
  }

  private func perform(_ action: String) {
    switch action {
    case "warningOnly":
      return
    case "lock":
      // macOS has no general public Lock Screen API. Starting the system screen saver preserves
      // the user's password-delay setting and never terminates apps or risks unsaved work.
      let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
      NSWorkspace.shared.openApplication(at: url, configuration: .init())
    case "logoff":
      sendLoginWindowEvent(AEEventID(kAELogOut))
    case "restart":
      sendLoginWindowEvent(AEEventID(kAEShowRestartDialog))
    case "shutdown":
      sendLoginWindowEvent(AEEventID(kAEShowShutdownDialog))
    default:
      return
    }
  }

  private func sendLoginWindowEvent(_ eventID: AEEventID) {
    let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kCoreEventClass), eventID: eventID,
      targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    _ = try? event.sendEvent(options: [.defaultOptions, .alwaysInteract], timeout: 30)
  }
  private func primeMessages() {
    client.fetchDashboard { [weak self] result in
      guard let self, case .success(let dashboard) = result else { return }
      knownParentMessageIDs = Set(dashboard.messages.filter(\.isFromParent).map(\.id))
      messagesPrimed = true
    }
  }
  private func speakNewAnnouncements() {
    client.fetchDashboard { [weak self] result in
      guard let self, case .success(let dashboard) = result else { return }
      let parentMessages = dashboard.messages.filter { $0.isFromParent }
      let candidates: [EndpointChatMessage]
      if messagesPrimed {
        candidates = parentMessages.filter { !knownParentMessageIDs.contains($0.id) }
      } else {
        candidates = parentMessages.filter { Date().timeIntervalSince($0.sentAt) < 30 }
      }
      knownParentMessageIDs.formUnion(parentMessages.map(\.id))
      messagesPrimed = true
      for message in candidates where message.audience == .announcement && message.deletedAt == nil
      {
        let utterance = AVSpeechUtterance(string: message.text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
      }
    }
  }
  private func report(_ state: EndpointSessionState) {
    client.updateSession(
      SessionUpdate(state: state, consoleUser: DeviceSnapshotCollector.consoleUser())
    ) { _ in }
  }
  private func reportApplications() {
    client.fetchStatus { [weak self] result in
      guard let self, case .success(let status) = result, status.activityCollectionEnabled else {
        return
      }
      let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      let applications = NSWorkspace.shared.runningApplications.compactMap {
        application -> EndpointApplicationActivity? in
        guard application.activationPolicy == .regular,
          let bundleID = application.bundleIdentifier,
          let name = application.localizedName
        else { return nil }
        return EndpointApplicationActivity(
          bundleIdentifier: bundleID, applicationName: name,
          isForeground: bundleID == frontmost)
      }.sorted {
        if $0.isForeground != $1.isForeground { return $0.isForeground }
        return $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName)
          == .orderedAscending
      }.prefix(64).map { $0 }
      self.client.updateActivity(EndpointActivityUpdate(applications: applications)) { _ in }
    }
  }
}

let reporter = SessionReporter()
reporter.start()
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
