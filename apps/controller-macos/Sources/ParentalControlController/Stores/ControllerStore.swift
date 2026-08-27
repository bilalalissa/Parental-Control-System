import AppKit
import CryptoKit
import Foundation
import HubCore
import Observation
import Security
import UserNotifications

@MainActor
@Observable
final class ControllerStore {
  var selectedDeviceID: String?
  var auditEvents: [AuditEvent]
  var chatMessages: [ChatMessage]
  var schedule: ScheduleDraft
  var scheduleIssues: [ScheduleValidationIssue] = []
  var scheduleStatusMessage = "Choose a paired macOS device, then sign and apply its schedule."
  var adultOverrideCode: String?
  var policyActionStatusMessage: String?
  var databaseStatusMessage: String?
  var storageSnapshot: StorageSnapshot
  var hubStatus: LocalHubStatus?
  var hubStatusMessage = "Starting the authenticated local hub…"
  var pairingStatusMessage: String?
  var chatStatusMessage: String?
  var activityStatusMessage: String?
  var browserStatusMessage: String?

  private let database: ControllerDatabase
  private let hubClient = HubClient()
  private var hubRefreshTask: Task<Void, Never>?
  private var knownInboundMessageIDs: Set<UUID> = []
  private var loadedInitialHubStatus = false
  private var activityAlertTracker = HubActivityAlertTracker()

  init(database: ControllerDatabase) throws {
    self.database = database
    try database.migrate()
    try database.removeLegacySyntheticPreviewData()
    auditEvents = try database.loadAuditEvents()
    chatMessages = try database.loadChatMessages()
    schedule = try database.latestSchedule() ?? .standard
    storageSnapshot = try database.storageSnapshot()
  }

  static func live() -> ControllerStore {
    do {
      return try ControllerStore(database: ControllerDatabase.applicationSupport())
    } catch {
      do {
        let fallback = try ControllerStore(database: ControllerDatabase(path: ":memory:"))
        fallback.databaseStatusMessage =
          "Persistent storage is unavailable. Using an in-memory preview: \(error)"
        return fallback
      } catch {
        preconditionFailure(
          "The controller could not initialize its local preview database: \(error)")
      }
    }
  }

  var selectedPairedDevice: HubDeviceRecord? {
    guard let selectedDeviceID else { return pairedDevices.first }
    return pairedDevices.first { $0.id == selectedDeviceID }
  }

  var onlineDeviceCount: Int { pairedDevices.filter { $0.state() == .online }.count }
  var offlineDeviceCount: Int { pairedDevices.filter { $0.state() == .offline }.count }

  var unreadChatCount: Int {
    hubStatus?.chatMessages.filter(\.isUnreadForParent).count ?? 0
  }

  var pairedDevices: [HubDeviceRecord] {
    hubStatus?.devices.filter { !$0.isRevoked } ?? []
  }

  var displayedAuditEvents: [AuditEvent] {
    let hubEvents = (hubStatus?.auditRecords ?? []).map { record in
      let severity: AuditSeverity =
        record.event.contains("rejected") || record.event.contains("shutdown")
        ? .warning
        : (record.event.contains("action") || record.event.contains("policy")
          ? .notice : .information)
      return AuditEvent(
        id: record.id, timestamp: record.timestamp,
        title: record.event.replacingOccurrences(of: ".", with: " ").capitalized,
        detail: record.detail, severity: severity)
    }
    return Array((hubEvents + auditEvents).sorted { $0.timestamp > $1.timestamp }.prefix(50))
  }

  var pairingInvitationToken: String? {
    guard
      let invitation = hubStatus?.invitation,
      let data = try? IPCCodec.encoder().encode(invitation)
    else { return nil }
    return data.base64EncodedString()
  }

  func startHub() {
    guard hubRefreshTask == nil else { return }
    hubRefreshTask = Task { [weak self] in
      guard let self else { return }
      do {
        applyHubStatus(try await hubClient.status())
        hubStatusMessage = "Local hub ready · TLS 1.3 · Authenticated IPC"
      } catch {
        hubStatusMessage = "Local hub unavailable: \(error)"
        hubRefreshTask = nil
        return
      }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { break }
        do {
          let status = try await hubClient.statusIfRunning()
          // Presence is derived from lastSeen plus the current time. Publish every sample even
          // when the stored payload is equal so Online can age into Offline without a click.
          applyHubStatus(status)
          hubStatusMessage = "Local hub ready · TLS 1.3 · Authenticated IPC"
        } catch {
          hubStatusMessage = "Local hub unavailable: \(error)"
          hubRefreshTask = nil
          return
        }
      }
    }
  }

  func createPairingInvitation() {
    pairingStatusMessage =
      "Starting the local hub. Approve one macOS Keychain request if it appears…"
    Task {
      do {
        applyHubStatus(try await hubClient.createPairing())
        pairingStatusMessage = "One-time code created. It expires in five minutes."
        if hubRefreshTask == nil { startHub() }
      } catch {
        pairingStatusMessage = "Could not create pairing code: \(error)"
      }
    }
  }

  func revokePairedDevice(_ id: String) {
    Task {
      do {
        applyHubStatus(try await hubClient.revoke(deviceID: id))
        pairingStatusMessage = "Device revoked. Its active connection was closed."
      } catch {
        pairingStatusMessage = "Could not revoke device: \(error)"
      }
    }
  }

  func unpairDevice(_ id: String) {
    Task {
      do {
        applyHubStatus(try await hubClient.unpair(deviceID: id))
        pairingStatusMessage = "Device pairing record removed."
      } catch {
        pairingStatusMessage = "Could not unpair device: \(error)"
      }
    }
  }

  func sendChat(text: String, audience: ChatAudienceMode, deviceIDs: [String]) {
    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
    guard !trimmed.isEmpty, !deviceIDs.isEmpty else { return }
    let threadID = UUID()
    chatStatusMessage = "Queuing for \(deviceIDs.count) device\(deviceIDs.count == 1 ? "" : "s")…"
    Task {
      var latest = hubStatus
      var failures = 0
      var accepted = 0
      for deviceID in deviceIDs {
        do {
          latest = try await hubClient.sendChat(
            deviceID: deviceID, text: trimmed, audience: audience.hubAudience,
            threadID: threadID)
          accepted += 1
        } catch {
          failures += 1
        }
      }
      if let latest { applyHubStatus(latest) }
      if accepted > 0 { NSSound.beep() }
      chatStatusMessage =
        failures == 0
        ? "Message secured locally for \(deviceIDs.count) device\(deviceIDs.count == 1 ? "" : "s")."
        : "Queued for \(deviceIDs.count - failures); \(failures) failed validation."
    }
  }

  func editParentChatMessage(id: UUID, text: String) {
    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
    guard !trimmed.isEmpty else { return }
    Task {
      do {
        applyHubStatus(try await hubClient.editChat(messageID: id, text: trimmed))
        chatStatusMessage = "Message edited securely."
      } catch {
        chatStatusMessage = "Message could not be edited: \(error)"
      }
    }
  }

  func deleteParentChatMessage(id: UUID) {
    Task {
      do {
        applyHubStatus(try await hubClient.deleteChat(messageID: id))
        chatStatusMessage = "Message deleted from the family conversation."
      } catch {
        chatStatusMessage = "Message could not be deleted: \(error)"
      }
    }
  }

  func configureActivity(deviceID: String, enabled: Bool, retentionDays: Int) {
    Task {
      do {
        applyHubStatus(
          try await hubClient.configureActivity(
            deviceID: deviceID, enabled: enabled, retentionDays: retentionDays)
        )
        activityStatusMessage =
          enabled
          ? "Application-name collection enabled with \(retentionDays)-day retention."
          : "Collection disabled; retained activity for this device was removed."
      } catch {
        activityStatusMessage = "Could not update activity collection: \(error)"
      }
    }
  }

  func configureBrowser(deviceID: String, enabled: Bool, retentionDays: Int) {
    Task {
      do {
        applyHubStatus(
          try await hubClient.configureBrowser(
            deviceID: deviceID, enabled: enabled, retentionDays: retentionDays))
        browserStatusMessage =
          enabled
          ? "Browser title/origin sharing enabled with \(retentionDays)-day retention."
          : "Browser sharing disabled; retained tab metadata was removed."
      } catch {
        browserStatusMessage = "Could not update browser sharing: \(error)"
      }
    }
  }

  func markChatRead(deviceIDs: [String], audience: ChatAudience) {
    guard !deviceIDs.isEmpty else { return }
    Task {
      var latest = hubStatus
      for deviceID in deviceIDs {
        if let status = try? await hubClient.markChatRead(deviceID: deviceID, audience: audience) {
          latest = status
        }
      }
      if let latest { applyHubStatus(latest) }
    }
  }

  private func applyHubStatus(_ status: LocalHubStatus?) {
    guard let status else { return }
    let inbound = status.chatMessages.filter { !$0.isFromParent }
    let inboundIDs = Set(inbound.map(\.id))
    if loadedInitialHubStatus {
      for message in inbound where !knownInboundMessageIDs.contains(message.id) {
        let content = UNMutableNotificationContent()
        content.title = "Message from a child device"
        content.body = "Open Parental Control to read it."
        content.sound = .default
        UNUserNotificationCenter.current().add(
          UNNotificationRequest(identifier: message.id.uuidString, content: content, trigger: nil))
      }
    }
    knownInboundMessageIDs = inboundIDs
    loadedInitialHubStatus = true
    for alert in activityAlertTracker.newlyAlertingObservations(
      activity: status.activity, tabs: status.browserTabs)
    {
      let content = UNMutableNotificationContent()
      content.title =
        alert.kind == .youtube ? "YouTube activity detected" : "Possible game activity detected"
      content.body = "Open Parental Control to review shared activity."
      content.sound = .default
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    hubStatus = status
    let availableIDs = Set(status.devices.filter { !$0.isRevoked }.map(\.id))
    if selectedDeviceID == nil || !availableIDs.contains(selectedDeviceID ?? "") {
      selectedDeviceID = status.devices.first { !$0.isRevoked }?.id
    }
  }

  func stopHub() {
    hubRefreshTask?.cancel()
    hubRefreshTask = nil
    hubClient.stop()
  }

  func validateAndSaveSchedule() {
    scheduleIssues = ScheduleValidator.validate(schedule)
    guard scheduleIssues.isEmpty else {
      scheduleStatusMessage = "Review the validation messages before saving."
      return
    }
    do {
      try database.saveSchedule(schedule)
      storageSnapshot = try database.storageSnapshot()
      guard let device = selectedPairedDevice else {
        scheduleStatusMessage = "Saved locally. Pair and select a macOS child device to apply it."
        return
      }
      scheduleStatusMessage = "Signing policy for \(device.name)…"
      publishPolicy(to: device.id)
    } catch {
      scheduleStatusMessage = "The schedule could not be saved: \(error)"
    }
  }

  func grantBonus(deviceID: String, minutes: Int) {
    schedule.approveRequestedTime(minutes: minutes)
    do { try database.saveSchedule(schedule) } catch {
      scheduleStatusMessage = "Bonus time could not be saved: \(error)"
      return
    }
    publishPolicy(to: deviceID)
  }

  func sendImmediateAction(deviceID: String, action: PolicyAction, confirmed: Bool) {
    policyActionStatusMessage = "Sending authenticated \(action.rawValue) request…"
    Task {
      do {
        applyHubStatus(
          try await hubClient.sendAction(
            deviceID: deviceID, action: action, confirmed: confirmed))
        policyActionStatusMessage =
          action == .lock
          ? "Lock request sent. Apps remain open and unsaved work is not discarded."
          : "\(action.rawValue.capitalized) request sent with a macOS confirmation dialog."
      } catch {
        policyActionStatusMessage = "Action was not sent: \(error)"
      }
    }
  }

  private func publishPolicy(to deviceID: String) {
    guard let policy = makePolicy(deviceID: deviceID) else {
      scheduleStatusMessage = "The schedule could not be converted to a signed policy."
      return
    }
    let code = generateAdultCode()
    let salt = UUID().uuidString
    let digest = Data(
      SHA256.hash(data: Data("adult-code|\(salt)|\(code)".utf8))
    ).base64EncodedString()
    Task {
      do {
        applyHubStatus(try await hubClient.applyPolicy(policy))
        applyHubStatus(
          try await hubClient.rotateAdultVerifier(
            deviceID: deviceID, salt: salt, digest: digest))
        adultOverrideCode = code
        scheduleStatusMessage =
          "Signed policy version \(policy.version) queued for the selected device."
      } catch {
        scheduleStatusMessage = "The signed policy could not be applied: \(error)"
      }
    }
  }

  private func makePolicy(deviceID: String) -> ParentalControlPolicy? {
    let windows = schedule.windows.filter(\.isEnabled).compactMap { window -> PolicyWeeklyWindow? in
      guard let day = PolicyWeekday(rawValue: window.day.title) else { return nil }
      return PolicyWeeklyWindow(day: day, start: window.startLabel, end: window.endLabel)
    }
    guard let action = PolicyAction(rawValue: schedule.action.rawValue), !windows.isEmpty else {
      return nil
    }
    let version = UInt64(max(1, (Date().timeIntervalSince1970 * 1_000).rounded()))
    return ParentalControlPolicy(
      version: version, deviceID: deviceID, timezone: schedule.timezone,
      effectiveAt: Date(), expiresAt: Date().addingTimeInterval(366 * 86_400),
      defaultAction: action,
      warningOffsetsMinutes: Array(Set([schedule.warningMinutes, 5, 1])).sorted(by: >),
      gracePeriodSeconds: schedule.gracePeriodSeconds, weeklyAllowed: windows,
      exceptions: schedule.bonusUntil.flatMap { until in
        until > Date()
          ? [
            PolicyException(
              start: Date().addingTimeInterval(-5), end: until, decision: .allow,
              reason: "Parent-approved time extension")
          ] : nil
      } ?? [],
      dailyQuotaMinutes: schedule.dailyQuotaMinutes, bonusMinutes: schedule.bonusMinutes,
      childExplanation: "Available during family-approved hours; ask a parent for more time.",
      signature: PolicySignature(keyID: "controller-local-authority", value: "unsigned"))
  }

  private func generateAdultCode() -> String {
    var random: UInt32 = 0
    if SecRandomCopyBytes(kSecRandomDefault, MemoryLayout.size(ofValue: random), &random)
      != errSecSuccess
    {
      random = UInt32(Date().timeIntervalSince1970) ^ UInt32.random(in: 0...UInt32.max)
    }
    return String(format: "%06u", random % 1_000_000)
  }

  func refreshStorageSnapshot() {
    do {
      storageSnapshot = try database.storageSnapshot()
    } catch {
      databaseStatusMessage = "Storage totals are temporarily unavailable: \(error)"
    }
  }
}
