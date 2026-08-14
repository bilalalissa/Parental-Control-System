import Foundation
import HubCore
import Testing

@testable import EndpointCore

@Suite("macOS endpoint foundation", .serialized)
struct EndpointCoreTests {
  @Test("real endpoint pairs, heartbeats, and observes controller revocation")
  func pairingIntegration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let tlsLabel = "com.bilalalissa.ParentalControlController.stage03.test.\(UUID().uuidString)"
    let tls = try TLSCertificateIdentity.loadOrCreate(label: tlsLabel)
    defer { TLSCertificateIdentity.delete(label: tlsLabel) }
    let database = try HubDatabase(path: root.appendingPathComponent("hub.sqlite3").path)
    let controllerIdentity = try Ed25519Identity(keyID: "controller-local-authority")
    let hub = try LocalHub(
      database: database, tlsIdentity: tls, controllerIdentity: controllerIdentity,
      heartbeat: AdaptiveHeartbeat(activeInterval: 1, idleInterval: 2, offlineAfter: 4))
    defer { hub.stop() }
    let ready = DispatchSemaphore(value: 0)
    let paired = DispatchSemaphore(value: 0)
    hub.onStatusChange = { status in
      if status.port != 0 { ready.signal() }
      if status.devices.contains(where: { $0.id.hasPrefix("synthetic") }) { paired.signal() }
    }
    hub.onError = { error in print("integration hub error: \(error)") }
    try hub.start(advertiseBonjour: false)
    #expect(ready.wait(timeout: .now() + 5) == .success)
    let issued = try hub.createPairingInvitation(code: "314159")
    let invitation = PairingInvitation(
      code: issued.code, expiresAt: issued.expiresAt, host: "127.0.0.1", port: issued.port,
      certificateFingerprint: issued.certificateFingerprint,
      controllerPublicKey: issued.controllerPublicKey)
    let store = ProtectedConfigurationStore(root: root.appendingPathComponent("endpoint"))
    var configuration = EndpointConfiguration(deviceID: "synthetic-macos-endpoint")
    configuration.invitation = invitation
    try store.save(configuration)
    let repository = EndpointStatusRepository(
      initial: DeviceSnapshotCollector.collect(deviceID: configuration.deviceID))
    let logDirectory = root.appendingPathComponent("logs")
    let agent = try EndpointAgent(
      store: store, repository: repository,
      log: BoundedLog(directory: logDirectory),
      suppliedIdentity: Ed25519Identity(keyID: "device-\(configuration.deviceID)"))
    defer { agent.stop() }
    try agent.start()
    let pairingResult = paired.wait(timeout: .now() + 8)
    if pairingResult != .success,
      let log = try? String(
        contentsOf: logDirectory.appendingPathComponent("agent.log"), encoding: .utf8)
    {
      print("integration agent log: \(log)")
    }
    #expect(pairingResult == .success)
    #expect(try database.device(id: configuration.deviceID) != nil)
    let pairingDeadline = Date().addingTimeInterval(2)
    while try store.load().invitation != nil, Date() < pairingDeadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    #expect(try store.load().invitation == nil)
    try hub.revoke(deviceID: configuration.deviceID)
    #expect(try database.device(id: configuration.deviceID)?.isRevoked == true)
  }

  @Test("device snapshots are bounded and contain truthful platform data")
  func snapshot() {
    let value = DeviceSnapshotCollector.collect(deviceID: "synthetic-device")
    #expect(value.deviceID == "synthetic-device")
    #expect(!value.operatingSystem.isEmpty)
    #expect(!value.architecture.isEmpty)
    #expect(value.networks.count <= 16)
    #expect(value.networks.allSatisfy { $0.addresses.count <= 8 })
  }

  @Test("protected configuration is mode 0700 with mode 0600 contents")
  func protectedConfiguration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProtectedConfigurationStore(root: root)
    _ = try store.load()
    let rootMode = try #require(
      (try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?
        .intValue)
    let file = root.appendingPathComponent("configuration.json")
    let fileMode = try #require(
      (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?
        .intValue)
    #expect(rootMode & 0o777 == 0o700)
    #expect(fileMode & 0o777 == 0o600)
    #expect(try store.nextSequence() == 1)
    #expect(try store.nextSequence() == 2)
  }

  @Test("pairing invitation expiry fails closed")
  func invitationExpiry() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let expired = PairingInvitation(
      code: "123456", expiresAt: Date().addingTimeInterval(-1), host: "localhost", port: 1,
      certificateFingerprint: "AA", controllerPublicKey: Data(repeating: 1, count: 32))
    #expect(throws: ConfigurationError.self) {
      try ProtectedConfigurationStore(root: root).installPairingInvitation(expired)
    }
  }

  @Test("XPC operations enforce helper and visible-app identities")
  func xpcAuthorization() {
    #expect(
      XPCAuthorization.allows(
        uid: 501, signingIdentifier: EndpointMachService.childIdentifier, operation: "status"))
    #expect(
      !XPCAuthorization.allows(
        uid: 501, signingIdentifier: EndpointMachService.childIdentifier,
        operation: "session-update"))
    #expect(
      XPCAuthorization.allows(
        uid: 501, signingIdentifier: EndpointMachService.helperIdentifier,
        operation: "session-update"))
    #expect(
      !XPCAuthorization.allows(
        uid: 0, signingIdentifier: EndpointMachService.helperIdentifier, operation: "status"))
    #expect(!XPCAuthorization.allows(uid: 501, signingIdentifier: "untrusted", operation: "status"))
    #expect(
      XPCAuthorization.isExpectedInstalledPath(
        "/Applications/Parental Control Child.app/Contents/MacOS/ParentalControlChild",
        identifier: EndpointMachService.childIdentifier))
    #expect(
      !XPCAuthorization.isExpectedInstalledPath(
        "/tmp/ParentalControlChild", identifier: EndpointMachService.childIdentifier))
    #expect(
      XPCAuthorization.allows(
        uid: 501, signingIdentifier: EndpointMachService.controlIdentifier, operation: "status"))
    #expect(
      !XPCAuthorization.allows(
        uid: 501, signingIdentifier: EndpointMachService.controlIdentifier,
        operation: "session-update"))
    #expect(
      XPCAuthorization.isExpectedInstalledPath(
        "/usr/local/bin/parental-control-agentctl",
        identifier: EndpointMachService.controlIdentifier))
  }

  @Test("bounded log rotates and redacts pairing-like secrets")
  func boundedLog() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = BoundedLog(directory: root, maximumBytes: 80, generations: 3)
    for index in 0..<12 {
      log.write(event: "test", detail: "token=secret-\(index) ordinary detail")
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.fileSizeKey])
    #expect(files.count <= 3)
    for file in files {
      let text = try String(contentsOf: file, encoding: .utf8)
      #expect(!text.contains("secret-"))
    }
  }
}
