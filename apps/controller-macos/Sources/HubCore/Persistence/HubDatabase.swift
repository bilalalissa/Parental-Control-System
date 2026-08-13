import Foundation
import SQLite3

public enum HubDatabaseError: Error, CustomStringConvertible {
  case sqlite(String)
  case decode(String)

  public var description: String {
    switch self {
    case .sqlite(let message): "Hub database failed: \(message)"
    case .decode(let message): "Hub database value was invalid: \(message)"
    }
  }
}

private enum HubSQLiteValue {
  case integer(Int64)
  case text(String)
  case null
}

public final class HubDatabase: @unchecked Sendable {
  public static let maximumAuditRecords = 200
  public static let maximumQueuedEnvelopesPerDevice = 100
  public static let maximumReceipts = 500

  private let handle: OpaquePointer
  private let lock = NSRecursiveLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(path: String) throws {
    var database: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
      if let database { sqlite3_close(database) }
      throw HubDatabaseError.sqlite("could not open \(path)")
    }
    handle = database
    sqlite3_busy_timeout(handle, 2_000)
    try execute("PRAGMA foreign_keys = ON;")
    try execute("PRAGMA journal_mode = WAL;")
    try migrate()
  }

  deinit { sqlite3_close(handle) }

  public static func applicationSupport() throws -> HubDatabase {
    let baseURL = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = baseURL.appendingPathComponent("ParentalControlController", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try HubDatabase(path: directory.appendingPathComponent("hub.sqlite3").path)
  }

  public func migrate() throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS hub_schema_migrations(
          version INTEGER PRIMARY KEY,
          applied_at REAL NOT NULL
      );
      CREATE TABLE IF NOT EXISTS paired_devices(
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          platform TEXT NOT NULL,
          key_id TEXT NOT NULL UNIQUE,
          public_key TEXT NOT NULL,
          capabilities_json TEXT NOT NULL,
          paired_at REAL NOT NULL,
          last_seen REAL NOT NULL,
          last_sequence INTEGER NOT NULL DEFAULT 0,
          snapshot_version INTEGER NOT NULL DEFAULT 0,
          revoked INTEGER NOT NULL DEFAULT 0 CHECK(revoked IN (0, 1))
      );
      CREATE TABLE IF NOT EXISTS hub_audit(
          id TEXT PRIMARY KEY,
          timestamp REAL NOT NULL,
          event TEXT NOT NULL,
          device_id TEXT,
          detail TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS hub_audit_time_idx ON hub_audit(timestamp DESC);
      CREATE TABLE IF NOT EXISTS outbound_queue(
          id TEXT PRIMARY KEY,
          device_id TEXT NOT NULL,
          created_at REAL NOT NULL,
          expires_at REAL NOT NULL,
          envelope TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS outbound_device_time_idx
          ON outbound_queue(device_id, created_at ASC);
      CREATE TABLE IF NOT EXISTS receipts(
          id TEXT PRIMARY KEY,
          device_id TEXT NOT NULL,
          original_message_id TEXT NOT NULL,
          state TEXT NOT NULL,
          timestamp REAL NOT NULL
      );
      CREATE INDEX IF NOT EXISTS receipts_time_idx ON receipts(timestamp DESC);
      INSERT OR IGNORE INTO hub_schema_migrations(version, applied_at)
          VALUES(1, strftime('%s','now'));
      """)
  }

  public func upsertDevice(_ device: HubDeviceRecord) throws {
    let capabilities = try json(device.capabilities)
    try run(
      """
      INSERT INTO paired_devices(
          id, name, platform, key_id, public_key, capabilities_json,
          paired_at, last_seen, last_sequence, snapshot_version, revoked
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
          name=excluded.name,
          platform=excluded.platform,
          key_id=excluded.key_id,
          public_key=excluded.public_key,
          capabilities_json=excluded.capabilities_json,
          last_seen=excluded.last_seen,
          last_sequence=MAX(paired_devices.last_sequence, excluded.last_sequence),
          snapshot_version=MAX(paired_devices.snapshot_version, excluded.snapshot_version),
          revoked=excluded.revoked;
      """,
      [
        .text(device.id), .text(device.name), .text(device.platform), .text(device.keyID),
        .text(device.publicKey.base64EncodedString()), .text(capabilities),
        .integer(Int64(device.pairedAt.timeIntervalSince1970)),
        .integer(Int64(device.lastSeen.timeIntervalSince1970)),
        .integer(Int64(clamping: device.lastSequence)),
        .integer(Int64(clamping: device.snapshotVersion)),
        .integer(device.isRevoked ? 1 : 0),
      ])
  }

  public func device(id: String) throws -> HubDeviceRecord? {
    try devices(includeRevoked: true).first { $0.id == id }
  }

  public func devices(includeRevoked: Bool = false) throws -> [HubDeviceRecord] {
    lock.lock()
    defer { lock.unlock() }
    var statement: OpaquePointer?
    let sql =
      """
      SELECT id, name, platform, key_id, public_key, capabilities_json,
             paired_at, last_seen, last_sequence, snapshot_version, revoked
      FROM paired_devices
      \(includeRevoked ? "" : "WHERE revoked = 0")
      ORDER BY name;
      """
    try prepare(sql, &statement)
    defer { sqlite3_finalize(statement) }
    var result: [HubDeviceRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let publicKey = Data(base64Encoded: text(statement, 4)),
        let capabilityData = text(statement, 5).data(using: .utf8)
      else { throw HubDatabaseError.decode("device key or capabilities") }
      let capabilities = try decoder.decode([String].self, from: capabilityData)
      result.append(
        HubDeviceRecord(
          id: text(statement, 0),
          name: text(statement, 1),
          platform: text(statement, 2),
          keyID: text(statement, 3),
          publicKey: publicKey,
          capabilities: capabilities,
          pairedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
          lastSeen: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
          lastSequence: UInt64(max(0, sqlite3_column_int64(statement, 8))),
          snapshotVersion: UInt64(max(0, sqlite3_column_int64(statement, 9))),
          isRevoked: sqlite3_column_int(statement, 10) == 1
        ))
    }
    return result
  }

  public func updateSeen(
    deviceID: String,
    sequence: UInt64,
    snapshotVersion: UInt64,
    now: Date = Date()
  ) throws {
    try run(
      """
      UPDATE paired_devices
      SET last_seen = ?, last_sequence = MAX(last_sequence, ?),
          snapshot_version = MAX(snapshot_version, ?)
      WHERE id = ? AND revoked = 0;
      """,
      [
        .integer(Int64(now.timeIntervalSince1970)), .integer(Int64(clamping: sequence)),
        .integer(Int64(clamping: snapshotVersion)), .text(deviceID),
      ])
  }

  public func revoke(deviceID: String) throws {
    try run("UPDATE paired_devices SET revoked = 1 WHERE id = ?;", [.text(deviceID)])
    try run("DELETE FROM outbound_queue WHERE device_id = ?;", [.text(deviceID)])
  }

  public func unpair(deviceID: String) throws {
    try run("DELETE FROM outbound_queue WHERE device_id = ?;", [.text(deviceID)])
    try run("DELETE FROM receipts WHERE device_id = ?;", [.text(deviceID)])
    try run("DELETE FROM paired_devices WHERE id = ?;", [.text(deviceID)])
  }

  public func appendAudit(_ record: HubAuditRecord) throws {
    try run(
      "INSERT INTO hub_audit(id, timestamp, event, device_id, detail) VALUES(?, ?, ?, ?, ?);",
      [
        .text(record.id.uuidString), .integer(Int64(record.timestamp.timeIntervalSince1970)),
        .text(record.event), record.deviceID.map(HubSQLiteValue.text) ?? .null,
        .text(String(record.detail.prefix(512))),
      ])
    try execute(
      """
      DELETE FROM hub_audit WHERE id NOT IN(
          SELECT id FROM hub_audit ORDER BY timestamp DESC, rowid DESC
          LIMIT \(Self.maximumAuditRecords)
      );
      """)
  }

  public func audit(limit: Int = 50) throws -> [HubAuditRecord] {
    lock.lock()
    defer { lock.unlock() }
    var statement: OpaquePointer?
    try prepare(
      "SELECT id, timestamp, event, device_id, detail FROM hub_audit ORDER BY timestamp DESC LIMIT ?;",
      &statement)
    defer { sqlite3_finalize(statement) }
    try bind(.integer(Int64(max(1, min(limit, Self.maximumAuditRecords)))), statement, 1)
    var result: [HubAuditRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let id = UUID(uuidString: text(statement, 0)) else {
        throw HubDatabaseError.decode("audit ID")
      }
      result.append(
        HubAuditRecord(
          id: id,
          timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
          event: text(statement, 2),
          deviceID: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : text(statement, 3),
          detail: text(statement, 4)
        ))
    }
    return result
  }

  public func enqueue(_ item: QueuedEnvelope) throws {
    try run(
      "INSERT INTO outbound_queue(id, device_id, created_at, expires_at, envelope) VALUES(?, ?, ?, ?, ?);",
      [
        .text(item.id.uuidString), .text(item.deviceID),
        .integer(Int64(item.createdAt.timeIntervalSince1970)),
        .integer(Int64(item.expiresAt.timeIntervalSince1970)),
        .text(item.envelope.base64EncodedString()),
      ])
    try run(
      "DELETE FROM outbound_queue WHERE expires_at < ?;",
      [.integer(Int64(Date().timeIntervalSince1970))])
    try run(
      """
      DELETE FROM outbound_queue WHERE device_id = ? AND id NOT IN(
          SELECT id FROM outbound_queue WHERE device_id = ?
          ORDER BY created_at DESC, rowid DESC LIMIT \(Self.maximumQueuedEnvelopesPerDevice)
      );
      """,
      [.text(item.deviceID), .text(item.deviceID)])
  }

  public func queued(deviceID: String, now: Date = Date()) throws -> [QueuedEnvelope] {
    try run(
      "DELETE FROM outbound_queue WHERE expires_at < ?;",
      [.integer(Int64(now.timeIntervalSince1970))])
    lock.lock()
    defer { lock.unlock() }
    var statement: OpaquePointer?
    try prepare(
      "SELECT id, created_at, expires_at, envelope FROM outbound_queue WHERE device_id = ? ORDER BY created_at;",
      &statement)
    defer { sqlite3_finalize(statement) }
    try bind(.text(deviceID), statement, 1)
    var result: [QueuedEnvelope] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let id = UUID(uuidString: text(statement, 0)),
        let data = Data(base64Encoded: text(statement, 3))
      else { throw HubDatabaseError.decode("queued envelope") }
      result.append(
        QueuedEnvelope(
          id: id,
          deviceID: deviceID,
          createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
          expiresAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
          envelope: data
        ))
    }
    return result
  }

  public func removeQueued(id: UUID) throws {
    try run("DELETE FROM outbound_queue WHERE id = ?;", [.text(id.uuidString)])
  }

  public func appendReceipt(_ receipt: ReceiptRecord) throws {
    try run(
      "INSERT INTO receipts(id, device_id, original_message_id, state, timestamp) VALUES(?, ?, ?, ?, ?);",
      [
        .text(receipt.id.uuidString), .text(receipt.deviceID),
        .text(receipt.originalMessageID.uuidString), .text(receipt.state),
        .integer(Int64(receipt.timestamp.timeIntervalSince1970)),
      ])
    try execute(
      """
      DELETE FROM receipts WHERE id NOT IN(
          SELECT id FROM receipts ORDER BY timestamp DESC, rowid DESC
          LIMIT \(Self.maximumReceipts)
      );
      """)
  }

  public func counts() throws -> (devices: Int, audit: Int, queued: Int, receipts: Int) {
    (
      try scalar("SELECT COUNT(*) FROM paired_devices WHERE revoked = 0;"),
      try scalar("SELECT COUNT(*) FROM hub_audit;"),
      try scalar("SELECT COUNT(*) FROM outbound_queue;"),
      try scalar("SELECT COUNT(*) FROM receipts;")
    )
  }

  private func json<T: Encodable>(_ value: T) throws -> String {
    guard let string = String(data: try encoder.encode(value), encoding: .utf8) else {
      throw HubDatabaseError.decode("JSON was not UTF-8")
    }
    return string
  }

  private func execute(_ sql: String) throws {
    lock.lock()
    defer { lock.unlock() }
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
      let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
      sqlite3_free(error)
      throw HubDatabaseError.sqlite(message)
    }
  }

  private func run(_ sql: String, _ values: [HubSQLiteValue]) throws {
    lock.lock()
    defer { lock.unlock() }
    var statement: OpaquePointer?
    try prepare(sql, &statement)
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() {
      try bind(value, statement, Int32(offset + 1))
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw HubDatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
    }
  }

  private func scalar(_ sql: String) throws -> Int {
    lock.lock()
    defer { lock.unlock() }
    var statement: OpaquePointer?
    try prepare(sql, &statement)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw HubDatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
    }
    return Int(sqlite3_column_int64(statement, 0))
  }

  private func prepare(_ sql: String, _ statement: inout OpaquePointer?) throws {
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw HubDatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
    }
  }

  private func bind(_ value: HubSQLiteValue, _ statement: OpaquePointer?, _ index: Int32) throws {
    let status: Int32
    switch value {
    case .integer(let integer): status = sqlite3_bind_int64(statement, index, integer)
    case .text(let string):
      status = sqlite3_bind_text(
        statement, index, string, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    case .null: status = sqlite3_bind_null(statement, index)
    }
    guard status == SQLITE_OK else {
      throw HubDatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
    }
  }

  private func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
    guard let value = sqlite3_column_text(statement, column) else { return "" }
    return String(cString: value)
  }
}
