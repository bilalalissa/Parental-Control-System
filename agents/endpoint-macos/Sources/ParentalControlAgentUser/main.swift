import AVFoundation
import AppKit
import CoreFoundation
import CoreServices
import Darwin
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
  private var currentPolicyAction: PolicyAction?
  private var lastScheduleLockAttemptAt: Date?
  private var secureLockReadiness: EndpointSecureLockReadiness = .unknown
  private var secureLockReadinessCheckedAt: Date?
  private var secureLockConfirmation: EndpointSecureLockConfirmation = .notRequested
  private var secureLockConfirmedAt: Date?
  private var pendingLockRequestedAt: Date?
  private var pendingApplicationLockFallback:
    (processIdentifier: Int32, bundleIdentifier: String, policyVersion: Int64)?
  private var deferredEnforcementEvents: [EndpointPolicyEvent] = []
  private var codeIdentityCache: [pid_t: ApplicationCodeIdentity] = [:]
  private var applicationRestrictionGate = ApplicationRestrictionAttemptGate()
  private static let screenSaverBundleIdentifier = "com.apple.ScreenSaver.Engine"
  @MainActor func start() {
    configureStatusItem()
    refreshSecureLockReadiness(force: true)
    currentState =
      EndpointConsoleSession.isCurrentStandardUser(uid: getuid())
        && NSWorkspace.shared.frontmostApplication?.bundleIdentifier
          != Self.screenSaverBundleIdentifier
      ? .active : .inactive
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(sessionBecameActive),
      name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(sessionResignedActive),
      name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
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
    if currentState == .active {
      report(.active, activationBoundary: true)
    } else {
      report(.inactive)
    }
    reportApplications()
    primeMessages()
    claimPolicyEvents()
    refreshPolicyCountdown()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.refreshSecureLockReadiness()
        self.report(self.currentState)
        self.claimPolicyEvents()
        self.processDeferredEnforcementEvents()
        self.refreshPolicyCountdown()
        self.enforceCurrentApplicationRestrictions()
      }
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
      self?.enforceCurrentApplicationRestrictions()
    }
  }
  @MainActor @objc private func sessionBecameActive() {
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else {
      currentState = .inactive
      return
    }
    currentState = .active
    pendingLockRequestedAt = nil
    cancelPendingApplicationFallback()
    pendingApplicationLockFallback = nil
    secureLockConfirmation = .notRequested
    refreshSecureLockReadiness(force: true)
    report(currentState, activationBoundary: true)
    processDeferredEnforcementEvents()
  }
  @MainActor @objc private func sessionResignedActive() {
    if secureLockConfirmation == .pending, secureLockReadiness == .ready,
      EndpointConsoleSession.isCurrentStandardUser(uid: getuid())
    {
      confirmSecureLock()
    } else {
      currentState = .inactive
      pendingLockRequestedAt = nil
      cancelPendingApplicationFallback()
      pendingApplicationLockFallback = nil
      secureLockConfirmation = .notRequested
      report(currentState)
    }
  }
  @MainActor @objc private func systemWillSleep() {
    currentState = .inactive
    pendingLockRequestedAt = nil
    cancelPendingApplicationFallback()
    pendingApplicationLockFallback = nil
    secureLockConfirmation = .notRequested
    report(currentState)
  }
  @MainActor @objc private func systemDidWake() {
    // Waking the machine does not prove that the GUI session is unlocked. Remain inactive until
    // NSWorkspace emits the separate sessionDidBecomeActive notification.
    currentState = .inactive
    refreshSecureLockReadiness(force: true)
    report(currentState)
    refreshPolicyCountdown()
  }
  @MainActor @objc private func applicationsChanged(_ notification: Notification) {
    reportApplications()
    if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
      as? NSRunningApplication,
      application.bundleIdentifier == Self.screenSaverBundleIdentifier
    {
      if notification.name == NSWorkspace.didLaunchApplicationNotification
        || notification.name == NSWorkspace.didActivateApplicationNotification
      {
        confirmSecureLockIfReady()
      } else if notification.name == NSWorkspace.didTerminateApplicationNotification {
        sessionBecameActive()
      }
      return
    }
    if notification.name == NSWorkspace.didLaunchApplicationNotification,
      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication
    {
      enforceApplicationRestriction(for: application)
    }
    guard notification.name == NSWorkspace.didTerminateApplicationNotification,
      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication
    else { return }
    applicationRestrictionGate.processDidTerminate(application.processIdentifier)
    codeIdentityCache.removeValue(forKey: application.processIdentifier)
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
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else {
      deferEnforcementEvent(event)
      return
    }
    NSSound.beep()
    switch event {
    case .warning(let minutes, let action, let explanation):
      showPolicyBanner(
        title: "Time warning",
        message:
          "\(minutes) minute\(minutes == 1 ? "" : "s") until \(action.rawValue). \(explanation)")
    case .enforce:
      // RC7 persisted enforcement events have no policy version or expiry and are intentionally
      // discarded by the daemon. Keep this decode-only branch fail closed.
      return
    case .enforcePolicy(let action, _, let policyVersion, let restrictionID):
      client.fetchStatus { [weak self] result in
        guard case .success(let status) = result else {
          DispatchQueue.main.async { self?.deferEnforcementEvent(event) }
          return
        }
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else {
            self.deferEnforcementEvent(event)
            return
          }
          guard status.policyVersion == policyVersion, status.policyDecision == .block,
            status.policyAction == action, status.policyRestrictionID == restrictionID
          else { return }
          if !self.perform(action.rawValue) { self.deferEnforcementEvent(event) }
        }
      }
    case .enforceImmediate(let action, _, let expiresAt):
      guard expiresAt > Date() else { return }
      if !perform(action.rawValue) { deferEnforcementEvent(event) }
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

  @MainActor private func deferEnforcementEvent(_ event: EndpointPolicyEvent) {
    switch event {
    case .enforcePolicy, .enforceImmediate:
      guard !deferredEnforcementEvents.contains(event) else { return }
      deferredEnforcementEvents.append(event)
      deferredEnforcementEvents = Array(deferredEnforcementEvents.suffix(16))
    default:
      return
    }
  }

  @MainActor private func processDeferredEnforcementEvents() {
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()),
      !deferredEnforcementEvents.isEmpty
    else { return }
    let pending = deferredEnforcementEvents
    deferredEnforcementEvents.removeAll(keepingCapacity: true)
    for event in pending { handlePolicyEvent(event) }
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
        self.currentPolicyAction = status.policyAction
        self.enforceBlockedScheduleIfNeeded(status, now: Date())
        self.renderStatusItem()
      }
    }
  }

  private func enforceCurrentApplicationRestrictions() {
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else { return }
    for application in NSWorkspace.shared.runningApplications
    where application.activationPolicy == .regular {
      enforceApplicationRestriction(for: application)
    }
  }

  private func enforceApplicationRestriction(for application: NSRunningApplication) {
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else { return }
    guard let bundleIdentifier = application.bundleIdentifier,
      !ApplicationRestrictionRule.isProtected(bundleIdentifier),
      let bundleURL = application.bundleURL
    else { return }
    let candidate = ApplicationRestrictionProcessCandidate(
      processIdentifier: application.processIdentifier, bundleIdentifier: bundleIdentifier,
      bundleURL: bundleURL)
    client.fetchStatus { [weak self] result in
      guard let self, case .success(let status) = result,
        status.applicationRestrictionPolicy?.rule(for: bundleIdentifier) != nil
      else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self,
          let application = NSRunningApplication(
            processIdentifier: candidate.processIdentifier),
          !application.isTerminated,
          candidate.matchesLiveProcess(
            bundleIdentifier: application.bundleIdentifier, bundleURL: application.bundleURL),
          let liveBundleURL = application.bundleURL,
          // Enforcement deliberately bypasses the activity-reporting cache: an app can update at
          // the same path, so each action must validate the currently running signed bundle.
          let identity = ApplicationCodeIdentity.validated(
            processIdentifier: candidate.processIdentifier, at: liveBundleURL),
          let rule = ApplicationRestrictionEvaluator.matches(
            bundleIdentifier: bundleIdentifier, identity: identity,
            policy: status.applicationRestrictionPolicy)
        else { return }
        let policyVersion = status.applicationRestrictionPolicy?.version ?? 0
        let processIdentifier = candidate.processIdentifier
        guard
          self.applicationRestrictionGate.begin(
            processIdentifier: processIdentifier, policyVersion: policyVersion)
        else { return }
        self.showPolicyBanner(
          title: "Application restricted",
          message:
            "\(rule.applicationName) is not available under the current family policy. It will now close."
        )
        _ = application.terminate()
        self.reportApplicationRestriction(
          bundleIdentifier: bundleIdentifier,
          policyVersion: policyVersion,
          outcome: .quitRequested)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
          self?.finishApplicationRestrictionFallback(
            candidate: candidate, bundleIdentifier: bundleIdentifier,
            policyVersion: policyVersion)
        }
      }
    }
  }

  private func finishApplicationRestrictionFallback(
    candidate: ApplicationRestrictionProcessCandidate, bundleIdentifier: String,
    policyVersion: Int64
  ) {
    let processIdentifier = candidate.processIdentifier
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else {
      applicationRestrictionGate.cancel(
        processIdentifier: processIdentifier, policyVersion: policyVersion)
      return
    }
    guard
      applicationRestrictionGate.isCurrent(
        processIdentifier: processIdentifier, policyVersion: policyVersion)
    else { return }
    guard
      let application = NSRunningApplication(processIdentifier: processIdentifier),
      candidate.matchesLiveProcess(
        bundleIdentifier: application.bundleIdentifier, bundleURL: application.bundleURL),
      !application.isTerminated
    else {
      applicationRestrictionGate.processDidTerminate(processIdentifier)
      reportApplicationRestriction(
        bundleIdentifier: bundleIdentifier, policyVersion: policyVersion, outcome: .closed)
      return
    }
    client.fetchStatus { [weak self] result in
      guard let self, case .success(let status) = result else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else {
          self.applicationRestrictionGate.cancel(
            processIdentifier: processIdentifier, policyVersion: policyVersion)
          return
        }
        guard
          self.applicationRestrictionGate.isCurrent(
            processIdentifier: processIdentifier, policyVersion: policyVersion),
          let currentPolicy = status.applicationRestrictionPolicy,
          let liveApplication = NSRunningApplication(processIdentifier: processIdentifier),
          candidate.matchesLiveProcess(
            bundleIdentifier: liveApplication.bundleIdentifier,
            bundleURL: liveApplication.bundleURL),
          !liveApplication.isTerminated,
          let liveBundleURL = liveApplication.bundleURL,
          let identity = ApplicationCodeIdentity.validated(
            processIdentifier: processIdentifier, at: liveBundleURL),
          ApplicationRestrictionEvaluator.matches(
            bundleIdentifier: bundleIdentifier, identity: identity, policy: currentPolicy,
            expectedPolicyVersion: policyVersion) != nil
        else {
          self.applicationRestrictionGate.processDidTerminate(processIdentifier)
          return
        }
        self.showPolicyBanner(
          title: "Application did not close",
          message:
            "The session will lock to protect open work. Ask a parent to change the app policy."
        )
        self.requestSecureSessionLock(
          applicationFallback: (processIdentifier, bundleIdentifier, policyVersion))
      }
    }
  }

  private func reportApplicationRestriction(
    bundleIdentifier: String, policyVersion: Int64,
    outcome: EndpointApplicationRestrictionOutcome
  ) {
    guard policyVersion > 0 else { return }
    client.reportApplicationRestriction(
      EndpointApplicationRestrictionEvent(
        bundleIdentifier: bundleIdentifier, policyVersion: policyVersion, outcome: outcome)
    ) { _ in }
  }

  private func codeIdentity(for application: NSRunningApplication) -> ApplicationCodeIdentity? {
    guard let bundleURL = application.bundleURL else { return nil }
    let processIdentifier = application.processIdentifier
    if let cached = codeIdentityCache[processIdentifier] { return cached }
    guard
      let identity = ApplicationCodeIdentity.validated(
        processIdentifier: processIdentifier, at: bundleURL)
    else { return nil }
    codeIdentityCache[processIdentifier] = identity
    return identity
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
    let prefix = currentPolicyAction == .warningOnly ? "Next policy warning" : "Restriction"
    button.toolTip = "\(prefix) in \(remaining)\(limit)"
    countdownMenuItem?.title = "\(prefix) in \(remaining)\(limit)"
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

  @MainActor @discardableResult private func perform(_ action: String) -> Bool {
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else { return false }
    switch action {
    case "warningOnly":
      return true
    case "lock":
      requestSecureSessionLock()
    case "logoff":
      sendLoginWindowEvent(AEEventID(kAELogOut))
    case "restart":
      sendLoginWindowEvent(AEEventID(kAEShowRestartDialog))
    case "shutdown":
      sendLoginWindowEvent(AEEventID(kAEShowShutdownDialog))
    default:
      return false
    }
    return true
  }

  @MainActor private func enforceBlockedScheduleIfNeeded(
    _ status: EndpointStatus, now: Date
  ) {
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else { return }
    guard
      EndpointScheduleRelockGate.shouldRelock(
        status: status, sessionIsActive: currentState == .active,
        screenSaverIsForeground: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
          == Self.screenSaverBundleIdentifier,
        consoleUserPresent: DeviceSnapshotCollector.consoleUser() != nil, now: now,
        lastAttemptAt: lastScheduleLockAttemptAt)
    else { return }
    requestSecureSessionLock(now: now)
  }

  @MainActor private func requestSecureSessionLock(
    now: Date = Date(),
    applicationFallback:
      (processIdentifier: Int32, bundleIdentifier: String, policyVersion: Int64)? = nil
  ) {
    guard EndpointConsoleSession.isCurrentStandardUser(uid: getuid()) else {
      if let applicationFallback {
        applicationRestrictionGate.cancel(
          processIdentifier: applicationFallback.processIdentifier,
          policyVersion: applicationFallback.policyVersion)
      }
      return
    }
    lastScheduleLockAttemptAt = now
    guard secureLockConfirmation != .pending else { return }
    refreshSecureLockReadiness(force: true)
    guard secureLockReadiness == .ready else {
      secureLockConfirmation = .notRequested
      report(currentState)
      showPolicyBanner(
        title: "Secure Lock unavailable",
        message:
          "Set System Settings > Lock Screen > Require password after screen saver begins to Immediately, then try again."
      )
      if let applicationFallback {
        reportApplicationRestriction(
          bundleIdentifier: applicationFallback.bundleIdentifier,
          policyVersion: applicationFallback.policyVersion,
          outcome: .lockUnavailable)
        applicationRestrictionGate.cancel(
          processIdentifier: applicationFallback.processIdentifier,
          policyVersion: applicationFallback.policyVersion)
      }
      return
    }
    pendingLockRequestedAt = now
    pendingApplicationLockFallback = applicationFallback
    secureLockConfirmation = .pending
    report(currentState)
    let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.addsToRecentItems = false
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
      [weak self] application, error in
      DispatchQueue.main.async {
        guard let self, self.pendingLockRequestedAt == now else { return }
        if error != nil || application == nil {
          self.failSecureLock(.launchFailed)
        } else if application?.isActive == true {
          self.confirmSecureLockIfReady()
        }
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
      guard let self, self.pendingLockRequestedAt == now,
        self.secureLockConfirmation == .pending
      else { return }
      self.failSecureLock(.timedOut)
    }
  }

  @MainActor private func refreshSecureLockReadiness(now: Date = Date(), force: Bool = false) {
    guard
      force
        || EndpointSecureLockVerifier.shouldRefresh(
          lastCheckedAt: secureLockReadinessCheckedAt, now: now)
    else { return }
    secureLockReadiness = EndpointSecureLockVerifier.current()
    secureLockReadinessCheckedAt = now
  }

  @MainActor private func confirmSecureLockIfReady() {
    guard secureLockConfirmation == .pending, secureLockReadiness == .ready else { return }
    confirmSecureLock()
  }

  @MainActor private func confirmSecureLock() {
    pendingLockRequestedAt = nil
    secureLockConfirmation = .confirmed
    secureLockConfirmedAt = Date()
    currentState = .locked
    if let fallback = pendingApplicationLockFallback {
      reportApplicationRestriction(
        bundleIdentifier: fallback.bundleIdentifier,
        policyVersion: fallback.policyVersion,
        outcome: .sessionLocked)
      applicationRestrictionGate.cancel(
        processIdentifier: fallback.processIdentifier, policyVersion: fallback.policyVersion)
    }
    pendingApplicationLockFallback = nil
    report(currentState)
  }

  @MainActor private func failSecureLock(_ result: EndpointSecureLockConfirmation) {
    pendingLockRequestedAt = nil
    secureLockConfirmation = result
    if let fallback = pendingApplicationLockFallback {
      reportApplicationRestriction(
        bundleIdentifier: fallback.bundleIdentifier,
        policyVersion: fallback.policyVersion,
        outcome: result == .timedOut ? .lockConfirmationTimedOut : .lockUnavailable)
      applicationRestrictionGate.cancel(
        processIdentifier: fallback.processIdentifier, policyVersion: fallback.policyVersion)
    }
    pendingApplicationLockFallback = nil
    report(currentState)
    showPolicyBanner(
      title: "Secure Lock not confirmed",
      message:
        "macOS did not confirm a password-protected screen within eight seconds. The request will not repeat rapidly."
    )
  }

  @MainActor private func cancelPendingApplicationFallback() {
    guard let fallback = pendingApplicationLockFallback else { return }
    applicationRestrictionGate.cancel(
      processIdentifier: fallback.processIdentifier, policyVersion: fallback.policyVersion)
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
        activationBoundary: activationBoundary,
        secureLockReadiness: secureLockReadiness,
        secureLockConfirmation: secureLockConfirmation,
        secureLockConfirmedAt: secureLockConfirmedAt)
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
          let name = application.localizedName,
          application.bundleURL != nil
        else { return nil }
        let identity = self.codeIdentity(for: application)
        return EndpointApplicationActivity(
          bundleIdentifier: bundleID, applicationName: name,
          signingIdentifier: identity?.signingIdentifier,
          teamIdentifier: identity?.teamIdentifier,
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
