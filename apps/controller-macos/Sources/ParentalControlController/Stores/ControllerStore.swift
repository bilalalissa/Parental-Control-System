import Foundation
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

  private let database: ControllerDatabase

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
