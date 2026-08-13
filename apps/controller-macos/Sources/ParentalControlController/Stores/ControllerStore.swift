import Foundation
import HubCore
import Observation

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

  private let database: ControllerDatabase
  private let hubClient = HubClient()
  private var hubRefreshTask: Task<Void, Never>?

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
        hubStatus = try await hubClient.status()
        hubStatusMessage = "Local hub ready · TLS 1.3 · Authenticated IPC"
      } catch {
        hubStatusMessage = "Local hub unavailable: \(error)"
      }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { break }
        if let status = try? await hubClient.status() {
          hubStatus = status
          hubStatusMessage = "Local hub ready · TLS 1.3 · Authenticated IPC"
        }
      }
    }
  }

  func createPairingInvitation() {
    Task {
      do {
        hubStatus = try await hubClient.createPairing()
        pairingStatusMessage = "One-time code created. It expires in five minutes."
      } catch {
        pairingStatusMessage = "Could not create pairing code: \(error)"
      }
    }
  }

  func revokePairedDevice(_ id: String) {
    Task {
      do {
        hubStatus = try await hubClient.revoke(deviceID: id)
        pairingStatusMessage = "Device revoked. Its active connection was closed."
      } catch {
        pairingStatusMessage = "Could not revoke device: \(error)"
      }
    }
  }

  func unpairDevice(_ id: String) {
    Task {
      do {
        hubStatus = try await hubClient.unpair(deviceID: id)
        pairingStatusMessage = "Device pairing record removed."
      } catch {
        pairingStatusMessage = "Could not unpair device: \(error)"
      }
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
