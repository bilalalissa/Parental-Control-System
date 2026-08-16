import AppKit
import Foundation
import HubCore
import Observation
import UserNotifications

@MainActor
@Observable
final class ControllerStore {
  var selectedDeviceID: ManagedDevice.ID?
  var devices: [ManagedDevice]
  var auditEvents: [AuditEvent]
  var chatMessages: [ChatMessage]
  var schedule: ScheduleDraft
  var scheduleIssues: [ScheduleValidationIssue] = []
  var scheduleStatusMessage = "This is a local preview. No endpoint policy is sent in Stage 01."
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

  init(database: ControllerDatabase) throws {
    self.database = database
    try database.migrate()
    try database.seedSyntheticDataIfNeeded()
    devices = try database.loadDevices()
    auditEvents = try database.loadAuditEvents()
    chatMessages = try database.loadChatMessages()
    schedule = try database.latestSchedule() ?? .standard
    storageSnapshot = try database.storageSnapshot()
    selectedDeviceID = devices.first?.id
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

  var selectedDevice: ManagedDevice? {
    guard let selectedDeviceID else { return devices.first }
    return devices.first { $0.id == selectedDeviceID }
  }

  var onlineDeviceCount: Int { devices.filter(\.isOnline).count }
  var offlineDeviceCount: Int { devices.filter { $0.connectionState == .offline }.count }
  var approximateDeviceCount: Int { devices.filter { $0.connectionState == .approximate }.count }

  var unreadChatCount: Int {
    hubStatus?.chatMessages.filter(\.isUnreadForParent).count ?? 0
  }

  var pairedDevices: [HubDeviceRecord] {
    hubStatus?.devices.filter { !$0.isRevoked } ?? []
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
      }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { break }
        if let status = try? await hubClient.status() {
          // Presence is derived from lastSeen plus the current time. Publish every sample even
          // when the stored payload is equal so Online can age into Offline without a click.
          applyHubStatus(status)
          hubStatusMessage = "Local hub ready · TLS 1.3 · Authenticated IPC"
        }
      }
    }
  }

  func createPairingInvitation() {
    Task {
      do {
        applyHubStatus(try await hubClient.createPairing())
        pairingStatusMessage = "One-time code created. It expires in five minutes."
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
    hubStatus = status
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
      scheduleStatusMessage = "Saved locally as a preview. No endpoint policy was sent."
    } catch {
      scheduleStatusMessage = "The schedule could not be saved: \(error)"
    }
  }

  func refreshStorageSnapshot() {
    do {
      storageSnapshot = try database.storageSnapshot()
    } catch {
      databaseStatusMessage = "Storage totals are temporarily unavailable: \(error)"
    }
  }
}
