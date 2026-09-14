import Foundation
import Testing

@testable import EndpointCore

@Suite("ad-hoc endpoint identity recovery", .serialized)
struct EndpointIdentityRecoveryTests {
  @Test("file identity is stable, private, and rejects corruption")
  func fileIdentity() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = EndpointIdentityFileStore(root: root, expectedOwnerID: nil)

    let first = try store.loadOrCreateRandom()
    let second = try store.loadOrCreateRandom()
    #expect(first.count == 32)
    #expect(first == second)
    let permissions = try #require(
      (try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions]
        as? NSNumber)?.intValue)
    #expect(permissions & 0o777 == 0o600)

    try Data(repeating: 1, count: 31).write(to: store.url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: store.url.path)
    #expect(throws: EndpointIdentityFileError.invalidLength) {
      try store.loadOrCreateRandom()
    }
  }

  @Test("installer marker is bounded, private, and consumed once")
  func installerMarker() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let url = root.appendingPathComponent(EndpointInstallerMaintenanceMarker.fileName)
    let marker = EndpointInstallerMaintenanceMarker(
      issuedAt: now, expiresAt: now.addingTimeInterval(600))
    try PropertyListEncoder().encode(marker).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

    #expect(
      EndpointInstallerMaintenanceMarker.consume(
        root: root, now: now, expectedOwnerID: nil) == now.addingTimeInterval(600))
    #expect(
      EndpointInstallerMaintenanceMarker.consume(
        root: root, now: now, expectedOwnerID: nil) == nil)

    let excessive = EndpointInstallerMaintenanceMarker(
      issuedAt: now, expiresAt: now.addingTimeInterval(601))
    try PropertyListEncoder().encode(excessive).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    #expect(
      EndpointInstallerMaintenanceMarker.consume(
        root: root, now: now, expectedOwnerID: nil) == nil)
  }

  @Test("XPC manifest requires the five exact installed clients")
  func xpcManifestValidation() throws {
    let hash = String(repeating: "a", count: 64)
    let clients = [
      EndpointXPCClientRecord(
        identifier: EndpointMachService.childIdentifier,
        path: "/Applications/Parental Control Child.app/Contents/MacOS/ParentalControlChild",
        sha256: hash),
      EndpointXPCClientRecord(
        identifier: EndpointMachService.helperIdentifier,
        path:
          "/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlAgentUser",
        sha256: hash),
      EndpointXPCClientRecord(
        identifier: EndpointMachService.controlIdentifier,
        path: "/usr/local/bin/parental-control-agentctl", sha256: hash),
      EndpointXPCClientRecord(
        identifier: EndpointMachService.browserHostIdentifier,
        path:
          "/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlBrowserHost",
        sha256: hash),
      EndpointXPCClientRecord(
        identifier: EndpointMachService.safariExtensionIdentifier,
        path:
          "/Applications/Parental Control Safari.app/Contents/PlugIns/Parental Control Safari Extension.appex/Contents/MacOS/Parental Control Safari Extension",
        sha256: hash),
    ]
    #expect(try EndpointXPCClientManifest(clients: clients).validatedRecords().count == 5)

    let wrongPath =
      clients.dropLast(2) + [
        EndpointXPCClientRecord(
          identifier: EndpointMachService.browserHostIdentifier,
          path: "/tmp/ParentalControlBrowserHost", sha256: hash),
        clients.last!,
      ]
    #expect(throws: EndpointXPCManifestError.invalidManifest) {
      try EndpointXPCClientManifest(clients: Array(wrongPath)).validatedRecords()
    }
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "parental-control-identity-tests-\(UUID().uuidString)", isDirectory: true)
  }
}
