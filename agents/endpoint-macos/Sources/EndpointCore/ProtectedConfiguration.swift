import CryptoKit
import Foundation
import HubCore

public struct EndpointConfiguration: Codable, Equatable, Sendable {
  public var deviceID: String
  public var invitation: PairingInvitation?
  public var pairedController: PairingInvitation?
  public var sequence: UInt64
  public var activityCollectionEnabled: Bool
  public var activityRetentionDays: Int
  public var browserCollectionEnabled: Bool
  public var browserRetentionDays: Int
  public var websitePolicy: BrowserWebsitePolicy?

  public init(
    deviceID: String = UUID().uuidString.lowercased(), invitation: PairingInvitation? = nil,
    pairedController: PairingInvitation? = nil, sequence: UInt64 = 0,
    activityCollectionEnabled: Bool = true, activityRetentionDays: Int = 7,
    browserCollectionEnabled: Bool = false, browserRetentionDays: Int = 7
  ) {
    self.deviceID = deviceID
    self.invitation = invitation
    self.pairedController = pairedController
    self.sequence = sequence
    self.activityCollectionEnabled = activityCollectionEnabled
    self.activityRetentionDays = max(1, min(activityRetentionDays, 30))
    self.browserCollectionEnabled = browserCollectionEnabled
    self.browserRetentionDays = max(1, min(browserRetentionDays, 30))
  }

  private enum CodingKeys: String, CodingKey {
    case deviceID, invitation, pairedController, sequence
    case activityCollectionEnabled, activityRetentionDays
    case browserCollectionEnabled, browserRetentionDays
    case websitePolicy
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    deviceID = try values.decode(String.self, forKey: .deviceID)
    invitation = try values.decodeIfPresent(PairingInvitation.self, forKey: .invitation)
    pairedController = try values.decodeIfPresent(PairingInvitation.self, forKey: .pairedController)
    sequence = try values.decodeIfPresent(UInt64.self, forKey: .sequence) ?? 0
    activityCollectionEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .activityCollectionEnabled) ?? true
    activityRetentionDays = max(
      1, min(try values.decodeIfPresent(Int.self, forKey: .activityRetentionDays) ?? 7, 30))
    browserCollectionEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .browserCollectionEnabled) ?? false
    websitePolicy = try values.decodeIfPresent(BrowserWebsitePolicy.self, forKey: .websitePolicy)?
      .validated()
    browserRetentionDays = max(
      1, min(try values.decodeIfPresent(Int.self, forKey: .browserRetentionDays) ?? 7, 30))
  }
}

public final class ProtectedConfigurationStore: @unchecked Sendable {
  public let root: URL
  private let lock = NSLock()
  public init(root: URL) { self.root = root }

  public static var systemRoot: URL {
    URL(fileURLWithPath: "/Library/Application Support/ParentalControlAgent", isDirectory: true)
  }

  public func load() throws -> EndpointConfiguration {
    lock.lock()
    defer { lock.unlock() }
    let url = root.appendingPathComponent("configuration.json")
    guard FileManager.default.fileExists(atPath: url.path) else {
      let initial = EndpointConfiguration()
      try writeLocked(initial, to: url)
      return initial
    }
    return try JSONDecoder.endpoint.decode(EndpointConfiguration.self, from: Data(contentsOf: url))
  }

  public func save(_ value: EndpointConfiguration) throws {
    lock.lock()
    defer { lock.unlock() }
    try writeLocked(value, to: root.appendingPathComponent("configuration.json"))
  }

  public func installPairingInvitation(_ invitation: PairingInvitation) throws {
    guard invitation.expiresAt > Date(), !invitation.controllerPublicKey.isEmpty else {
      throw ConfigurationError.invalidInvitation
    }
    var value = try load()
    value.invitation = invitation
    try save(value)
  }

  public func installPairingToken(_ token: String) throws {
    guard let data = Data(base64Encoded: token),
      let invitation = try? JSONDecoder.endpoint.decode(PairingInvitation.self, from: data)
    else { throw ConfigurationError.invalidInvitation }
    try installPairingInvitation(invitation)
  }

  public func nextSequence() throws -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    let url = root.appendingPathComponent("configuration.json")
    var value: EndpointConfiguration
    if FileManager.default.fileExists(atPath: url.path) {
      value = try JSONDecoder.endpoint.decode(
        EndpointConfiguration.self, from: Data(contentsOf: url))
    } else {
      value = EndpointConfiguration()
    }
    value.sequence += 1
    try writeLocked(value, to: url)
    return value.sequence
  }

  public func markPaired() throws {
    var value = try load()
    if let invitation = value.invitation {
      value.pairedController = PairingInvitation(
        code: "", expiresAt: .distantFuture, host: invitation.host, port: invitation.port,
        certificateFingerprint: invitation.certificateFingerprint,
        controllerPublicKey: invitation.controllerPublicKey)
    }
    value.invitation = nil
    try save(value)
  }

  public func setActivityCollection(enabled: Bool, retentionDays: Int) throws {
    var value = try load()
    value.activityCollectionEnabled = enabled
    value.activityRetentionDays = max(1, min(retentionDays, 30))
    try save(value)
  }

  public func setBrowserCollection(
    enabled: Bool, retentionDays: Int, websitePolicy: BrowserWebsitePolicy? = nil
  ) throws {
    var value = try load()
    if let websitePolicy {
      let validated = try websitePolicy.validated()
      if let previous = value.websitePolicy,
        validated.version < previous.version
          || (validated.version == previous.version && validated != previous)
      {
        throw BrowserPolicyError.stalePolicy
      }
      value.websitePolicy = validated
    }
    value.browserCollectionEnabled = enabled
    value.browserRetentionDays = max(1, min(retentionDays, 30))
    try save(value)
  }

  private func writeLocked(_ value: EndpointConfiguration, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    try JSONEncoder.endpoint.encode(value).write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

public enum ConfigurationError: Error { case invalidInvitation }

extension JSONEncoder {
  public static var endpoint: JSONEncoder {
    let value = JSONEncoder()
    value.dateEncodingStrategy = .millisecondsSince1970
    value.outputFormatting = [.sortedKeys]
    return value
  }
}
extension JSONDecoder {
  public static var endpoint: JSONDecoder {
    let value = JSONDecoder()
    value.dateDecodingStrategy = .millisecondsSince1970
    return value
  }
}

public final class BoundedLog: @unchecked Sendable {
  public let directory: URL
  public let maximumBytes: Int
  public let generations: Int
  private let lock = NSLock()
  public init(directory: URL, maximumBytes: Int = 2 * 1_024 * 1_024, generations: Int = 3) {
    self.directory = directory
    self.maximumBytes = maximumBytes
    self.generations = generations
  }
  public func write(event: String, detail: String) {
    lock.lock()
    defer { lock.unlock() }
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let current = directory.appendingPathComponent("agent.log")
      let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      if size >= maximumBytes { try rotate(current) }
      let safe = detail.replacingOccurrences(
        of: #"(?i)(code|token|password)=[^\s]+"#, with: "$1=<redacted>", options: .regularExpression
      )
      let line =
        "\(ISO8601DateFormatter().string(from: Date())) \(String(event.prefix(80))) \(String(safe.prefix(800)))\n"
      if !FileManager.default.fileExists(atPath: current.path) {
        FileManager.default.createFile(atPath: current.path, contents: nil)
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o600], ofItemAtPath: current.path)
      }
      let handle = try FileHandle(forWritingTo: current)
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(line.utf8))
      try handle.close()
    } catch {}
  }
  private func rotate(_ current: URL) throws {
    if generations < 2 {
      try? FileManager.default.removeItem(at: current)
      return
    }
    for index in stride(from: generations - 1, through: 1, by: -1) {
      let destination = directory.appendingPathComponent("agent.log.\(index)")
      let source = index == 1 ? current : directory.appendingPathComponent("agent.log.\(index - 1)")
      try? FileManager.default.removeItem(at: destination)
      if FileManager.default.fileExists(atPath: source.path) {
        try FileManager.default.moveItem(at: source, to: destination)
      }
    }
  }
}
