import AVFoundation
import AppKit
import EndpointCore
import Foundation
import UserNotifications

final class SessionReporter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  private let client = EndpointXPCClient()
  private var timer: Timer?
  private var currentState: EndpointSessionState = .active
  private let speechSynthesizer = AVSpeechSynthesizer()
  private var knownParentMessageIDs: Set<UUID> = []
  private var messagesPrimed = false
  func start() {
    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.delegate = self
    Task {
      _ = try? await notificationCenter.requestAuthorization(options: [.alert, .sound])
    }
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(active), name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil)
    center.addObserver(
      self, selector: #selector(inactive), name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil)
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
    report(.active)
    reportApplications()
    primeMessages()
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
  @objc private func applicationsChanged() { reportApplications() }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
  @objc private func chatReceived() {
    // This direct sound-effects fallback is still subordinate to the Mac's output volume/mute.
    NSSound.beep()
    let content = UNMutableNotificationContent()
    content.title = "Message from your parent"
    content.body = "Open Parental Control to read it."
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    speakNewAnnouncements()
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
