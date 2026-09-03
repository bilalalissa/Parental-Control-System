import AVFoundation
import AppKit
import CoreFoundation
import CoreServices
import EndpointCore
import Foundation
import HubCore

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
  private var countdownTimer: Timer?
  private var currentState: EndpointSessionState = .active
  private let speechSynthesizer = AVSpeechSynthesizer()
  private var knownParentMessageIDs: Set<UUID> = []
  private var messagesPrimed = false
  private var policyBanner: NSPanel?
  private var statusItem: NSStatusItem?
  private var countdownMenuItem: NSMenuItem?
  private var nextRestrictionAt: Date?
  private var nextAllowanceAt: Date?
  private var nextLimitingReason: String?
  private var currentDecision: PolicyDecisionKind?
  private var lastScheduleLockAttemptAt: Date?
  private static let screenSaverBundleIdentifier = "com.apple.ScreenSaver.Engine"
  @MainActor func start() {
    configureStatusItem()
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
      self, selector: #selector(applicationsChanged(_:)),
      name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    center.addObserver(
      self, selector: #selector(applicationsChanged(_:)),
      name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    center.addObserver(
      self, selector: #selector(applicationsChanged(_:)),
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
    report(.active, activationBoundary: true)
    reportApplications()
    primeMessages()
    claimPolicyEvents()
    refreshPolicyCountdown()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      guard let self else { return }
      report(currentState)
      claimPolicyEvents()
      refreshPolicyCountdown()
    }
    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.renderStatusItem() }
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
    DispatchQueue.main.async { [weak self] in
      self?.claimPolicyEvents()
      self?.refreshPolicyCountdown()
    }
  }
  @objc private func active() {
    currentState = .active
    report(currentState, activationBoundary: true)
  }
  @objc private func inactive() {
    currentState = .inactive
    report(currentState)
  }
  @objc private func applicationsChanged(_ notification: Notification) {
    reportApplications()
    guard notification.name == NSWorkspace.didTerminateApplicationNotification,
      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication,
      application.bundleIdentifier == Self.screenSaverBundleIdentifier
    else { return }
    currentState = .active
    report(currentState, activationBoundary: true)
  }
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
    case .timeRequestRejected(let minutes):
      showPolicyBanner(
        title: "More time not approved",
        message:
          "Your request for \(minutes) minutes was not approved. The current family schedule remains active."
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
    }
  }

  @MainActor private func configureStatusItem() {
    NSApplication.shared.setActivationPolicy(.accessory)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.image = NSImage(
      systemSymbolName: "checkmark.shield", accessibilityDescription: "Parental control active")
    item.button?.toolTip = "Parental control is active in the background"
    let menu = NSMenu()
    let active = NSMenuItem(title: "Parental control active", action: nil, keyEquivalent: "")
    active.isEnabled = false
    menu.addItem(active)
    let countdown = NSMenuItem(title: "Checking family schedule…", action: nil, keyEquivalent: "")
    countdown.isEnabled = false
    menu.addItem(countdown)
    menu.addItem(.separator())
    let open = NSMenuItem(
      title: "Open Parental Control", action: #selector(openChildApp), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    item.menu = menu
    countdownMenuItem = countdown
    statusItem = item
    renderStatusItem()
  }

  @objc private func openChildApp() {
    let appURL = URL(fileURLWithPath: "/Applications/Parental Control Child.app")
    NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
  }

  private func refreshPolicyCountdown() {
    client.fetchStatus { [weak self] result in
      guard let self, case .success(let status) = result else { return }
      DispatchQueue.main.async {
        self.nextRestrictionAt = status.policyNextRestrictionAt
        self.nextAllowanceAt = status.policyNextAllowanceAt
        self.nextLimitingReason = status.policyAllowanceSummary?.limitingReason
        self.currentDecision = status.policyDecision
        self.enforceBlockedScheduleIfNeeded(status, now: Date())
        self.renderStatusItem()
      }
    }
  }

  @MainActor private func renderStatusItem(now: Date = Date()) {
    guard let button = statusItem?.button else { return }
    if currentDecision == .block {
      button.image = NSImage(
        systemSymbolName: "lock.fill", accessibilityDescription: "Family restriction active")
      if let nextAllowanceAt, nextAllowanceAt > now {
        let remaining = Self.shortCountdown(until: nextAllowanceAt, now: now)
        button.title = " \(remaining)"
        button.toolTip = "Family restriction active; available in \(remaining)"
        countdownMenuItem?.title = "Available in \(remaining)"
      } else {
        button.title = " Restricted"
        button.toolTip = "A family restriction is active"
        countdownMenuItem?.title = "Restriction active"
      }
      return
    }
    guard let nextRestrictionAt, nextRestrictionAt > now else {
      button.image = NSImage(
        systemSymbolName: "checkmark.shield", accessibilityDescription: "Parental control active")
      button.title = ""
      button.toolTip = "Parental control is active in the background"
      countdownMenuItem?.title = "No restriction within 8 days"
      return
    }
    let remaining = Self.shortCountdown(until: nextRestrictionAt, now: now)
    let limit = nextLimitingReason.map { "; limited by \($0.lowercased())" } ?? ""
    button.image = NSImage(
      systemSymbolName: "hourglass", accessibilityDescription: "Time until family restriction")
    button.title = " \(remaining)"
    button.toolTip = "Effective time remaining \(remaining)\(limit)"
    countdownMenuItem?.title = "Effective time remaining \(remaining)\(limit)"
  }

  private static func shortCountdown(until date: Date, now: Date) -> String {
    let total = max(0, Int(date.timeIntervalSince(now).rounded(.down)))
    let days = total / 86_400
    let hours = (total % 86_400) / 3_600
    let minutes = (total % 3_600) / 60
    let seconds = total % 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
    return String(format: "%02d:%02d", minutes, seconds)
  }

  @MainActor private func perform(_ action: String) {
    switch action {
    case "warningOnly":
      return
    case "lock":
      // macOS has no general public Lock Screen API. Starting the system screen saver preserves
      // the user's password-delay setting and never terminates apps or risks unsaved work.
      requestScreenSaverLock()
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

  @MainActor private func enforceBlockedScheduleIfNeeded(
    _ status: EndpointStatus, now: Date
  ) {
    guard
      EndpointScheduleRelockGate.shouldRelock(
        status: status, sessionIsActive: currentState == .active,
        screenSaverIsForeground: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
          == Self.screenSaverBundleIdentifier,
        consoleUserPresent: DeviceSnapshotCollector.consoleUser() != nil, now: now,
        lastAttemptAt: lastScheduleLockAttemptAt)
    else { return }
    requestScreenSaverLock(now: now)
  }

  @MainActor private func requestScreenSaverLock(now: Date = Date()) {
    lastScheduleLockAttemptAt = now
    let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.addsToRecentItems = false
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration)
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
  private func report(_ state: EndpointSessionState, activationBoundary: Bool = false) {
    client.updateSession(
      SessionUpdate(
        state: state, consoleUser: DeviceSnapshotCollector.consoleUser(),
        activationBoundary: activationBoundary)
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
MainActor.assumeIsolated { reporter.start() }
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
