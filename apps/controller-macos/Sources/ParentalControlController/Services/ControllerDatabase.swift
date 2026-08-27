import Foundation
import SQLite3

enum DatabaseError: Error, CustomStringConvertible, Equatable {
  case open(String)
  case execute(String)
  case prepare(String)
  case bind(String)
  case step(String)
  case decode(String)

  var description: String {
    switch self {
    case .open(let message): "Could not open the local database: \(message)"
    case .execute(let message): "Database command failed: \(message)"
    case .prepare(let message): "Database statement could not be prepared: \(message)"
    case .bind(let message): "Database value could not be bound: \(message)"
    case .step(let message): "Database statement failed: \(message)"
    case .decode(let message): "Stored data could not be decoded: \(message)"
    }
  }
}

private enum SQLiteValue {
  case integer(Int64)
  case text(String)
  case null
}

final class ControllerDatabase {
  static let currentSchemaVersion = 3

  private let handle: OpaquePointer
  private let path: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(path: String) throws {
    self.path = path
    var database: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
      let message =
        database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
      if let database { sqlite3_close(database) }
      throw DatabaseError.open(message)
    }
    handle = database
    if path != ":memory:" {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
    sqlite3_busy_timeout(handle, 2_000)
    try execute("PRAGMA foreign_keys = ON;")
    try execute("PRAGMA journal_mode = WAL;")
  }

  deinit {
    sqlite3_close(handle)
  }

  static func applicationSupport() throws -> ControllerDatabase {
    let baseURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = baseURL.appendingPathComponent("ParentalControlController", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    return try ControllerDatabase(path: directory.appendingPathComponent("controller.sqlite3").path)
  }

  func migrate() throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS schema_migrations (
          version INTEGER PRIMARY KEY,
          applied_at TEXT NOT NULL
      );
      """
    )

    let migrations: [(Int, String)] = [
      (
        1,
        """
        CREATE TABLE IF NOT EXISTS devices (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            platform TEXT NOT NULL,
            model TEXT NOT NULL,
            operating_system TEXT NOT NULL,
            architecture TEXT NOT NULL,
            connection_state TEXT NOT NULL,
            last_seen REAL NOT NULL,
            current_allowance TEXT NOT NULL,
            capabilities_json TEXT NOT NULL,
            limitations_json TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
      ),
      (
        2,
        """
        CREATE TABLE IF NOT EXISTS audit_events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            title TEXT NOT NULL,
            detail TEXT NOT NULL,
            severity TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS audit_events_timestamp_idx
            ON audit_events(timestamp DESC);
        CREATE TABLE IF NOT EXISTS chat_messages (
            id TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            sent_at REAL NOT NULL,
            sender TEXT NOT NULL,
            body TEXT NOT NULL,
            delivery_state TEXT NOT NULL,
            is_from_parent INTEGER NOT NULL CHECK(is_from_parent IN (0, 1))
        );
        CREATE INDEX IF NOT EXISTS chat_messages_device_time_idx
            ON chat_messages(device_id, sent_at);
        """
      ),
      (
        3,
        """
        CREATE TABLE IF NOT EXISTS schedule_revisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            saved_at REAL NOT NULL,
            schedule_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS schedule_revisions_saved_at_idx
            ON schedule_revisions(saved_at DESC);
        """
      ),
    ]

    let applied = try appliedMigrationVersions()
    for (version, sql) in migrations where !applied.contains(version) {
      try execute("BEGIN IMMEDIATE;")
      do {
        try execute(sql)
        try run(
          "INSERT INTO schema_migrations(version, applied_at) VALUES(?, ?);",
          values: [.integer(Int64(version)), .text(ISO8601DateFormatter().string(from: Date()))]
        )
        try execute("COMMIT;")
      } catch {
        try? execute("ROLLBACK;")
        throw error
      }
    }
  }

  func appliedMigrationVersions() throws -> Set<Int> {
    var statement: OpaquePointer?
    try prepare("SELECT version FROM schema_migrations ORDER BY version;", statement: &statement)
    defer { sqlite3_finalize(statement) }
    var versions = Set<Int>()
    while sqlite3_step(statement) == SQLITE_ROW {
      versions.insert(Int(sqlite3_column_int(statement, 0)))
    }
    return versions
  }

  func seedSyntheticDataIfNeeded() throws {
    guard try scalarInt("SELECT COUNT(*) FROM devices;") == 0 else { return }
    try execute("BEGIN IMMEDIATE;")
    do {
      for device in Self.syntheticDevices {
        let capabilities =
          try String(
            data: encoder.encode(device.capabilities.sorted { $0.rawValue < $1.rawValue }),
            encoding: .utf8) ?? "[]"
        let limitations =
          try String(data: encoder.encode(device.limitations), encoding: .utf8) ?? "[]"
        try run(
          """
          INSERT INTO devices(
              id, name, platform, model, operating_system, architecture,
              connection_state, last_seen, current_allowance,
              capabilities_json, limitations_json
          ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
          """,
          values: [
            .text(device.id.uuidString), .text(device.name), .text(device.platform.rawValue),
            .text(device.model), .text(device.operatingSystem), .text(device.architecture),
            .text(device.connectionState.rawValue),
            .integer(Int64(device.lastSeen.timeIntervalSince1970)),
            .text(device.currentAllowance), .text(capabilities), .text(limitations),
          ]
        )
      }
      for event in Self.syntheticAuditEvents {
        try run(
          "INSERT INTO audit_events(id, timestamp, title, detail, severity) VALUES(?, ?, ?, ?, ?);",
          values: [
            .text(event.id.uuidString), .integer(Int64(event.timestamp.timeIntervalSince1970)),
            .text(event.title), .text(event.detail), .text(event.severity.rawValue),
          ]
        )
      }
      for message in Self.syntheticMessages {
        try run(
          """
          INSERT INTO chat_messages(
              id, device_id, sent_at, sender, body, delivery_state, is_from_parent
          ) VALUES(?, ?, ?, ?, ?, ?, ?);
          """,
          values: [
            .text(message.id.uuidString), .text(message.deviceID.uuidString),
            .integer(Int64(message.sentAt.timeIntervalSince1970)), .text(message.sender),
            .text(message.text), .text(message.state.rawValue),
            .integer(message.isFromParent ? 1 : 0),
          ]
        )
      }
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  /// Stage 01 preview rows used fixed IDs and never represented paired endpoints. Remove only
  /// those exact fixtures when a production controller opens an older local database.
  func removeLegacySyntheticPreviewData() throws {
    let deviceIDs = [Self.studyMacID, Self.familyPCID, Self.schoolIPadID].map(\.uuidString)
    let auditIDs = Self.syntheticAuditEvents.map { $0.id.uuidString }
    let messageIDs = Self.syntheticMessages.map { $0.id.uuidString }
    for id in messageIDs {
      try run("DELETE FROM chat_messages WHERE id = ?;", values: [.text(id)])
    }
    for id in auditIDs {
      try run("DELETE FROM audit_events WHERE id = ?;", values: [.text(id)])
    }
    for id in deviceIDs {
      try run("DELETE FROM devices WHERE id = ?;", values: [.text(id)])
    }
  }

  func loadDevices() throws -> [ManagedDevice] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT id, name, platform, model, operating_system, architecture,
             connection_state, last_seen, current_allowance,
             capabilities_json, limitations_json
      FROM devices ORDER BY name;
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    var devices: [ManagedDevice] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let id = UUID(uuidString: text(statement, 0)),
        let platform = DevicePlatform(rawValue: text(statement, 2)),
        let state = DeviceConnectionState(rawValue: text(statement, 6)),
        let capabilityData = text(statement, 9).data(using: .utf8),
        let limitationData = text(statement, 10).data(using: .utf8)
      else {
        throw DatabaseError.decode("A synthetic device row contained an unsupported value.")
      }
      let capabilities = try decoder.decode([DeviceCapability].self, from: capabilityData)
      let limitations = try decoder.decode([String].self, from: limitationData)
      devices.append(
        ManagedDevice(
          id: id,
          name: text(statement, 1),
          platform: platform,
          model: text(statement, 3),
          operatingSystem: text(statement, 4),
          architecture: text(statement, 5),
          connectionState: state,
          lastSeen: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
          currentAllowance: text(statement, 8),
          capabilities: Set(capabilities),
          limitations: limitations
        )
      )
    }
    return devices
  }

  func loadAuditEvents(limit: Int = 50) throws -> [AuditEvent] {
    var statement: OpaquePointer?
    try prepare(
      "SELECT id, timestamp, title, detail, severity FROM audit_events ORDER BY timestamp DESC LIMIT ?;",
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind(.integer(Int64(max(1, min(limit, 200)))), to: statement, at: 1)
    var events: [AuditEvent] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let id = UUID(uuidString: text(statement, 0)),
        let severity = AuditSeverity(rawValue: text(statement, 4))
      else { throw DatabaseError.decode("An audit row contained an unsupported value.") }
      events.append(
        AuditEvent(
          id: id,
          timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
          title: text(statement, 2),
          detail: text(statement, 3),
          severity: severity
        )
      )
    }
    return events
  }

  func loadChatMessages(limit: Int = 50) throws -> [ChatMessage] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT id, device_id, sent_at, sender, body, delivery_state, is_from_parent
      FROM chat_messages ORDER BY sent_at ASC LIMIT ?;
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind(.integer(Int64(max(1, min(limit, 200)))), to: statement, at: 1)
    var messages: [ChatMessage] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let id = UUID(uuidString: text(statement, 0)),
        let deviceID = UUID(uuidString: text(statement, 1)),
        let state = MessageDeliveryState(rawValue: text(statement, 5))
      else { throw DatabaseError.decode("A chat row contained an unsupported value.") }
      messages.append(
        ChatMessage(
          id: id,
          deviceID: deviceID,
          sentAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
          sender: text(statement, 3),
          text: text(statement, 4),
          state: state,
          isFromParent: sqlite3_column_int(statement, 6) == 1
        )
      )
    }
    return messages
  }

  func saveSchedule(_ schedule: ScheduleDraft) throws {
    let data = try encoder.encode(schedule)
    guard let json = String(data: data, encoding: .utf8) else {
      throw DatabaseError.decode("The schedule could not be encoded as UTF-8.")
    }
    try execute("BEGIN IMMEDIATE;")
    do {
      try run(
        "INSERT INTO schedule_revisions(saved_at, schedule_json) VALUES(?, ?);",
        values: [.integer(Int64(Date().timeIntervalSince1970)), .text(json)]
      )
      try execute(
        """
        DELETE FROM schedule_revisions
        WHERE id NOT IN (SELECT id FROM schedule_revisions ORDER BY saved_at DESC, id DESC LIMIT 20);
        """
      )
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  func latestSchedule() throws -> ScheduleDraft? {
    var statement: OpaquePointer?
    try prepare(
      "SELECT schedule_json FROM schedule_revisions ORDER BY saved_at DESC, id DESC LIMIT 1;",
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    guard let data = text(statement, 0).data(using: .utf8) else {
      throw DatabaseError.decode("The saved schedule was not UTF-8.")
    }
    return try decoder.decode(ScheduleDraft.self, from: data)
  }

  func storageSnapshot() throws -> StorageSnapshot {
    let bytes: Int64
    if path == ":memory:" {
      bytes = 0
    } else {
      let attributes = try? FileManager.default.attributesOfItem(atPath: path)
      bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
    return StorageSnapshot(
      databaseBytes: bytes,
      deviceCount: try scalarInt("SELECT COUNT(*) FROM devices;"),
      auditEventCount: try scalarInt("SELECT COUNT(*) FROM audit_events;"),
      chatMessageCount: try scalarInt("SELECT COUNT(*) FROM chat_messages;")
    )
  }

  private func execute(_ sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
      let message =
        errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
      sqlite3_free(errorMessage)
      throw DatabaseError.execute(message)
    }
  }

  private func run(_ sql: String, values: [SQLiteValue]) throws {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() {
      try bind(value, to: statement, at: Int32(offset + 1))
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw DatabaseError.step(String(cString: sqlite3_errmsg(handle)))
    }
  }

  private func scalarInt(_ sql: String) throws -> Int {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw DatabaseError.step(String(cString: sqlite3_errmsg(handle)))
    }
    return Int(sqlite3_column_int64(statement, 0))
  }

  private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw DatabaseError.prepare(String(cString: sqlite3_errmsg(handle)))
    }
  }

  private func bind(_ value: SQLiteValue, to statement: OpaquePointer?, at index: Int32) throws {
    let result: Int32
    switch value {
    case .integer(let value):
      result = sqlite3_bind_int64(statement, index, value)
    case .text(let value):
      result = sqlite3_bind_text(
        statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    case .null:
      result = sqlite3_bind_null(statement, index)
    }
    guard result == SQLITE_OK else {
      throw DatabaseError.bind(String(cString: sqlite3_errmsg(handle)))
    }
  }

  private func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
    guard let raw = sqlite3_column_text(statement, column) else { return "" }
    return String(cString: raw)
  }
}

extension ControllerDatabase {
  fileprivate static let studyMacID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
  fileprivate static let familyPCID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
  fileprivate static let schoolIPadID = UUID(uuidString: "10000000-0000-4000-8000-000000000003")!

  fileprivate static let syntheticDevices: [ManagedDevice] = [
    ManagedDevice(
      id: studyMacID,
      name: "Study Mac",
      platform: .macOS,
      model: "MacBook Air (synthetic)",
      operatingSystem: "macOS 15.6",
      architecture: "arm64",
      connectionState: .online,
      lastSeen: Date(timeIntervalSince1970: 1_786_639_140),
      currentAllowance: "Available until 8:00 PM",
      capabilities: [
        .presence, .sessionState, .appActivity, .browserTabs, .chat, .schedule, .lock, .logoff,
        .restart, .shutdown,
      ],
      limitations: [
        "Browser metadata requires a visible extension.",
        "An authorized administrator can remove the endpoint.",
      ]
    ),
    ManagedDevice(
      id: familyPCID,
      name: "Family PC",
      platform: .windows,
      model: "Desktop PC (synthetic)",
      operatingSystem: "Windows 11",
      architecture: "x86_64",
      connectionState: .offline,
      lastSeen: Date(timeIntervalSince1970: 1_786_584_600),
      currentAllowance: "Offline — last seen shown below",
      capabilities: [
        .presence, .sessionState, .appActivity, .browserTabs, .chat, .schedule, .lock, .logoff,
        .restart, .shutdown,
      ],
      limitations: [
        "Offline does not mean powered off.", "Current actions are unavailable until reconnect.",
      ]
    ),
    ManagedDevice(
      id: schoolIPadID,
      name: "School iPad",
      platform: .iPadOS,
      model: "iPad Pro (synthetic)",
      operatingSystem: "iPadOS 18.6",
      architecture: "arm64",
      connectionState: .approximate,
      lastSeen: Date(timeIntervalSince1970: 1_786_635_600),
      currentAllowance: "Family Controls schedule active",
      capabilities: [.approximatePresence, .chat, .schedule],
      limitations: [
        "Presence is approximate, not continuous.",
        "Foreground apps, browser tabs, MAC address, reliable uptime, login state, global logout, restart, and shutdown are unavailable to a standard iPad app.",
      ]
    ),
  ]

  fileprivate static let syntheticAuditEvents: [AuditEvent] = [
    AuditEvent(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
      timestamp: Date(timeIntervalSince1970: 1_786_639_080),
      title: "Synthetic device connected",
      detail: "Study Mac reported a mock heartbeat on the local preview.",
      severity: .information
    ),
    AuditEvent(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
      timestamp: Date(timeIntervalSince1970: 1_786_584_600),
      title: "Synthetic device offline",
      detail: "Family PC is offline; power state was not inferred.",
      severity: .notice
    ),
    AuditEvent(
      id: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
      timestamp: Date(timeIntervalSince1970: 1_786_553_400),
      title: "Schedule preview updated",
      detail: "A local mock schedule was validated. No endpoint policy was sent.",
      severity: .information
    ),
  ]

  fileprivate static let syntheticMessages: [ChatMessage] = [
    ChatMessage(
      id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
      deviceID: studyMacID,
      sentAt: Date(timeIntervalSince1970: 1_786_638_300),
      sender: "Parent preview",
      text: "Dinner is in fifteen minutes.",
      state: .read,
      isFromParent: true
    ),
    ChatMessage(
      id: UUID(uuidString: "30000000-0000-4000-8000-000000000002")!,
      deviceID: studyMacID,
      sentAt: Date(timeIntervalSince1970: 1_786_638_480),
      sender: "Child preview",
      text: "Okay — I will save my work.",
      state: .delivered,
      isFromParent: false
    ),
  ]
}
