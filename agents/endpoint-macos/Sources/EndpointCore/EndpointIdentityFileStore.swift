import Foundation
import Security

public enum EndpointIdentityFileError: Error, Equatable, CustomStringConvertible {
  case invalidDirectory
  case invalidFile
  case invalidLength
  case randomFailure(OSStatus)

  public var description: String {
    switch self {
    case .invalidDirectory:
      return "Endpoint identity directory is not private and root protected"
    case .invalidFile:
      return "Endpoint identity file is not a private regular file"
    case .invalidLength:
      return "Endpoint identity file has an invalid length"
    case .randomFailure(let status):
      return "Endpoint identity randomness failed with status \(status)"
    }
  }
}

/// Ad-hoc test-build identity storage. The standard child account cannot read or replace this
/// file because both its parent directory and the file are owned by root and are not accessible
/// to group/other users. Production Developer-ID builds must migrate this value to Keychain.
public final class EndpointIdentityFileStore: @unchecked Sendable {
  public static let fileName = "endpoint-identity.key"

  public let url: URL
  private let expectedOwnerID: UInt32?
  private let lock = NSLock()

  public init(root: URL, expectedOwnerID: UInt32? = 0) {
    url = root.appendingPathComponent(Self.fileName, isDirectory: false)
    self.expectedOwnerID = expectedOwnerID
  }

  public func loadOrCreateRandom(byteCount: Int = 32) throws -> Data {
    precondition(byteCount > 0 && byteCount <= 4_096)
    lock.lock()
    defer { lock.unlock() }

    try prepareDirectory()
    if FileManager.default.fileExists(atPath: url.path) {
      return try load(expectedByteCount: byteCount)
    }

    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw EndpointIdentityFileError.randomFailure(status)
    }

    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".\(Self.fileName).\(UUID().uuidString.lowercased()).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard
      FileManager.default.createFile(
        atPath: temporary.path, contents: Data(bytes),
        attributes: [.posixPermissions: 0o600])
    else { throw EndpointIdentityFileError.invalidFile }
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: temporary.path)

    // The directory is private and this daemon is its only writer. Never overwrite an identity
    // that appeared between the existence check and the move.
    if FileManager.default.fileExists(atPath: url.path) {
      return try load(expectedByteCount: byteCount)
    }
    try FileManager.default.moveItem(at: temporary, to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    return try load(expectedByteCount: byteCount)
  }

  private func prepareDirectory() throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    guard values.isDirectory == true, values.isSymbolicLink != true,
      expectedOwnerID.map({ owner == $0 }) ?? true,
      permissions.map({ $0 & 0o077 == 0 }) == true
    else { throw EndpointIdentityFileError.invalidDirectory }
  }

  private func load(expectedByteCount: Int) throws -> Data {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      expectedOwnerID.map({ owner == $0 }) ?? true,
      permissions.map({ $0 & 0o077 == 0 }) == true
    else { throw EndpointIdentityFileError.invalidFile }
    let value = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard value.count == expectedByteCount else {
      throw EndpointIdentityFileError.invalidLength
    }
    return value
  }
}

public struct EndpointInstallerMaintenanceMarker: Codable, Equatable, Sendable {
  public static let fileName = ".installer-maintenance.plist"
  public static let maximumDuration: TimeInterval = 10 * 60

  public let issuedAtEpoch: Int64
  public let expiresAtEpoch: Int64

  public init(issuedAt: Date, expiresAt: Date) {
    issuedAtEpoch = Int64(issuedAt.timeIntervalSince1970.rounded(.down))
    expiresAtEpoch = Int64(expiresAt.timeIntervalSince1970.rounded(.down))
  }

  public func validatedUntil(now: Date = Date()) -> Date? {
    let issuedAt = Date(timeIntervalSince1970: TimeInterval(issuedAtEpoch))
    let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtEpoch))
    guard issuedAt <= now.addingTimeInterval(60),
      now.timeIntervalSince(issuedAt) <= Self.maximumDuration,
      expiresAt > now, expiresAt.timeIntervalSince(issuedAt) > 0,
      expiresAt.timeIntervalSince(issuedAt) <= Self.maximumDuration
    else { return nil }
    return expiresAt
  }

  public static func consume(
    root: URL, now: Date = Date(), expectedOwnerID: UInt32? = 0
  ) -> Date? {
    let url = root.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    defer { try? FileManager.default.removeItem(at: url) }
    guard
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
      values.isRegularFile == true, values.isSymbolicLink != true,
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      expectedOwnerID.map({ (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == $0 })
        ?? true,
      let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
      permissions & 0o077 == 0,
      let data = try? Data(contentsOf: url),
      let marker = try? PropertyListDecoder().decode(Self.self, from: data)
    else { return nil }
    return marker.validatedUntil(now: now)
  }
}
