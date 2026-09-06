import CryptoKit
import Darwin
import Foundation
import Security

public struct EndpointXPCClientRecord: Codable, Equatable, Sendable {
  public let identifier: String
  public let path: String
  public let sha256: String

  public init(identifier: String, path: String, sha256: String) {
    self.identifier = identifier
    self.path = path
    self.sha256 = sha256.lowercased()
  }
}

public struct EndpointXPCClientManifest: Codable, Equatable, Sendable {
  public static let fileName = "xpc-clients.plist"
  public let version: Int
  public let clients: [EndpointXPCClientRecord]

  public init(version: Int = 1, clients: [EndpointXPCClientRecord]) {
    self.version = version
    self.clients = clients
  }

  public func validatedRecords() throws -> [String: EndpointXPCClientRecord] {
    guard version == 1, clients.count == 5 else {
      throw EndpointXPCManifestError.invalidManifest
    }
    var result: [String: EndpointXPCClientRecord] = [:]
    for client in clients {
      guard XPCAuthorization.isRecognizedClient(client.identifier),
        XPCAuthorization.isExpectedInstalledPath(client.path, identifier: client.identifier),
        client.sha256.utf8.count == 64,
        client.sha256.utf8.allSatisfy({
          (48...57).contains($0) || (97...102).contains($0)
        }), result[client.path] == nil
      else { throw EndpointXPCManifestError.invalidManifest }
      result[client.path] = client
    }
    guard
      Set(clients.map(\.identifier))
        == Set([
          EndpointMachService.childIdentifier, EndpointMachService.helperIdentifier,
          EndpointMachService.controlIdentifier, EndpointMachService.browserHostIdentifier,
          EndpointMachService.safariExtensionIdentifier,
        ])
    else { throw EndpointXPCManifestError.invalidManifest }
    return result
  }
}

public enum EndpointXPCManifestError: Error, Equatable, CustomStringConvertible {
  case missingManifest
  case invalidManifest
  case unprotectedManifest
  case unprotectedClient(String)
  case clientHashMismatch(String)
  case invalidClientSignature(String)

  public var description: String {
    switch self {
    case .missingManifest: return "XPC client manifest is missing"
    case .invalidManifest: return "XPC client manifest is invalid"
    case .unprotectedManifest: return "XPC client manifest is not root protected"
    case .unprotectedClient(let identifier):
      return "XPC client is not root protected: \(identifier)"
    case .clientHashMismatch(let identifier):
      return "XPC client hash does not match the installed package: \(identifier)"
    case .invalidClientSignature(let identifier):
      return "XPC client signature is invalid: \(identifier)"
    }
  }
}

/// Verifies the root-owned package manifest and all fixed client executables once at daemon
/// startup. A connection is then mapped by its kernel-reported executable path to that exact
/// prevalidated record, avoiding the unreliable PID-to-SecCode lookup used by RC3.
public final class EndpointXPCClientVerifier: @unchecked Sendable {
  private let records: [String: EndpointXPCClientRecord]

  public init(manifestURL: URL, requireRootProtection: Bool = true) throws {
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw EndpointXPCManifestError.missingManifest
    }
    if requireRootProtection,
      !Self.isProtectedRegularFile(manifestURL.path, expectedOwnerID: 0)
    {
      throw EndpointXPCManifestError.unprotectedManifest
    }
    let manifest = try PropertyListDecoder().decode(
      EndpointXPCClientManifest.self, from: Data(contentsOf: manifestURL))
    let candidates = try manifest.validatedRecords()
    for candidate in candidates.values {
      if requireRootProtection, !XPCAuthorization.isRootProtected(candidate.path) {
        throw EndpointXPCManifestError.unprotectedClient(candidate.identifier)
      }
      guard try Self.sha256(path: candidate.path) == candidate.sha256 else {
        throw EndpointXPCManifestError.clientHashMismatch(candidate.identifier)
      }
      guard Self.validSigningIdentifier(path: candidate.path) == candidate.identifier else {
        throw EndpointXPCManifestError.invalidClientSignature(candidate.identifier)
      }
    }
    records = candidates
  }

  public func signingIdentifier(pid: pid_t, uid: uid_t) -> String? {
    guard uid != 0, let path = Self.processPath(pid: pid), let record = records[path] else {
      return nil
    }
    return record.identifier
  }

  public func diagnostic(pid: pid_t, uid: uid_t) -> String {
    let path = Self.processPath(pid: pid) ?? "unavailable"
    let identifier = records[path]?.identifier ?? "none"
    return "uid=\(uid) pid=\(pid) processPath=\(path) manifestIdentifier=\(identifier)"
  }

  private static func processPath(pid: pid_t) -> String? {
    // proc_pidpath permits up to four MAXPATHLEN units; the C macro is not imported into Swift.
    var buffer = [CChar](repeating: 0, count: 4_096)
    let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard count > 0 else { return nil }
    let bytes = buffer.prefix(Int(count)).prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
      .resolvingSymlinksInPath().path
  }

  private static func sha256(path: String) throws -> String {
    let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path)))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func validSigningIdentifier(path: String) -> String? {
    var staticCode: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
        == errSecSuccess,
      let staticCode,
      SecStaticCodeCheckValidity(
        staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
    else { return nil }
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let identifier = (information as? [CFString: Any])?[kSecCodeInfoIdentifier] as? String
    else { return nil }
    return identifier
  }

  private static func isProtectedRegularFile(_ path: String, expectedOwnerID: UInt32) -> Bool {
    guard
      let values = try? URL(fileURLWithPath: path).resourceValues(
        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
      values.isRegularFile == true, values.isSymbolicLink != true,
      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == expectedOwnerID,
      let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
      permissions & 0o077 == 0
    else { return false }
    return true
  }
}
