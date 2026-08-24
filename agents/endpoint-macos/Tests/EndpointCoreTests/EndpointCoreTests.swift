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
      heartbeat: AdaptiveHeartbeat(activeInterval: 1, idleInterval: 2, offlineAfter: 4),
      listeningPort: 0)
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
    #expect(issued.port > 0)
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
    let deviceIdentity = try Ed25519Identity(keyID: "device-\(configuration.deviceID)")
    let agent = try EndpointAgent(
      store: store, repository: repository,
      log: BoundedLog(directory: logDirectory),
      suppliedIdentity: deviceIdentity)
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
    let familyThread = UUID()
    repository.queueChat(text: "Child reply", audience: .familyGroup, threadID: familyThread)
    repository.queueMoreTime(minutes: 20, note: "Finish homework")
    let parentMessageID = try hub.sendChat(
      deviceID: configuration.deviceID, text: "Family announcement", audience: .familyGroup,
      threadID: familyThread)
    let chatDeadline = Date().addingTimeInterval(5)
    while Date() < chatDeadline {
      let childReceived = repository.dashboard(markRead: false).messages.contains {
        $0.isFromParent && $0.text == "Family announcement"
      }
      let parentReceived = try database.chatMessages().contains {
        !$0.isFromParent && $0.text == "Child reply"
      }
      let requestReceived = try !database.moreTimeRequests().isEmpty
      if childReceived && parentReceived && requestReceived { break }
      Thread.sleep(forTimeInterval: 0.02)
    }
    #expect(
      repository.dashboard(markRead: false).messages.contains {
        $0.isFromParent && $0.text == "Family announcement"
      })
    #expect(try database.chatMessages().contains { !$0.isFromParent && $0.text == "Child reply" })
    #expect(try database.moreTimeRequests().first?.requestedMinutes == 20)
    try hub.editParentChatMessage(id: parentMessageID, text: "Corrected family announcement")
    let editDeadline = Date().addingTimeInterval(3)
    while Date() < editDeadline,
      repository.dashboard(markRead: false).messages.first(where: { $0.id == parentMessageID })?
        .text != "Corrected family announcement"
    {
      Thread.sleep(forTimeInterval: 0.02)
    }
    #expect(
      repository.dashboard(markRead: false).messages.first { $0.id == parentMessageID }?.editedAt
        != nil)
    try hub.deleteParentChatMessage(id: parentMessageID)
    let deleteDeadline = Date().addingTimeInterval(3)
    while Date() < deleteDeadline,
      repository.dashboard(markRead: false).messages.first(where: { $0.id == parentMessageID })?
        .deletedAt == nil
    {
      Thread.sleep(forTimeInterval: 0.02)
    }
    #expect(
      repository.dashboard(markRead: false).messages.first { $0.id == parentMessageID }?.displayText
        == "Message deleted")
    let deviceBeforeRestart = try database.device(id: configuration.deviceID)
    let sequenceBeforeRestart = try #require(deviceBeforeRestart).lastSequence
    agent.stop()
    hub.stop()
    Thread.sleep(forTimeInterval: 0.2)

    let restartedHub = try LocalHub(
      database: database, tlsIdentity: tls, controllerIdentity: controllerIdentity,
      heartbeat: AdaptiveHeartbeat(activeInterval: 1, idleInterval: 2, offlineAfter: 4),
      listeningPort: 0)
    defer { restartedHub.stop() }
    let restartedReady = DispatchSemaphore(value: 0)
    restartedHub.onStatusChange = { status in
      if status.port != 0 { restartedReady.signal() }
    }
    try restartedHub.start(advertiseBonjour: false)
    #expect(restartedReady.wait(timeout: .now() + 5) == .success)
    let restartedPort = try restartedHub.status().port
    #expect(restartedPort > 0)

    let restartedAgent = try EndpointAgent(
      store: store, repository: repository,
      log: BoundedLog(directory: logDirectory), suppliedIdentity: deviceIdentity,
      pairedControllerPort: restartedPort)
    defer { restartedAgent.stop() }
    try restartedAgent.start()
    let reconnectDeadline = Date().addingTimeInterval(5)
    while repository.status().connectionState != .online, Date() < reconnectDeadline {
      Thread.sleep(forTimeInterval: 0.02)
    }
    #expect(repository.status().connectionState == .online)
    let deviceAfterRestart = try database.device(id: configuration.deviceID)
    #expect(try #require(deviceAfterRestart).lastSequence > sequenceBeforeRestart)

    try restartedHub.revoke(deviceID: configuration.deviceID)
    #expect(try database.device(id: configuration.deviceID)?.isRevoked == true)
  }

  @Test("legacy paired endpoints migrate to the stable controller port")
  func stableReconnectPort() {
    let legacy = PairingInvitation(
      code: "", expiresAt: .distantFuture, host: "parent.local", port: 61_234,
      certificateFingerprint: String(repeating: "A", count: 64),
      controllerPublicKey: Data(repeating: 7, count: 32))
    let paired = EndpointConfiguration(pairedController: legacy)
    #expect(
      EndpointAgent.connectionPort(for: paired) == SecureWebSocketServer.parentControlPort)
    #expect(EndpointAgent.connectionPort(for: paired, pairedControllerPort: 61_235) == 61_235)

    let active = EndpointConfiguration(invitation: legacy)
    #expect(EndpointAgent.connectionPort(for: active) == 61_234)
    #expect(EndpointAgent.connectionPort(for: EndpointConfiguration()) == nil)
  }

  @Test("reconnects immediately after loss, then bounds short retries")
  func boundedWakeReconnect() {
    var policy = EndpointReconnectPolicy()

    #expect(policy.timerFired(connectionState: .online) == .wait(60))
    #expect(policy.establishedConnectionLost() == 0)
    #expect(policy.timerFired(connectionState: .offline) == .connect(retryAfter: 2))
    #expect(policy.timerFired(connectionState: .connecting) == .connect(retryAfter: 2))
    #expect(policy.timerFired(connectionState: .offline) == .connect(retryAfter: 2))
    #expect(policy.timerFired(connectionState: .offline) == .wait(60))
    #expect(policy.timerFired(connectionState: .offline) == .connect(retryAfter: 2))
    #expect(policy.timerFired(connectionState: .online) == .wait(60))
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
      EndpointMachService.clientOptions.rawValue
        == NSXPCConnection.Options.privileged.rawValue)
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
        "/Applications/Parental Control Child.app",
        identifier: EndpointMachService.childIdentifier))
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

  @Test("activity disclosure and child queues are bounded and disable immediately")
  func stage04RuntimeBounds() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let queueURL = directory.appendingPathComponent("runtime-queue.json")
    let repository = EndpointStatusRepository(
      initial: DeviceSnapshotCollector.collect(deviceID: "synthetic-stage04"),
      persistenceURL: queueURL)
    let applications = (0..<90).map { index in
      EndpointApplicationActivity(
        bundleIdentifier: "com.example.app\(index)", applicationName: "App \(index)",
        isForeground: index == 0)
    }
    repository.applyActivity(EndpointActivityUpdate(applications: applications))
    #expect(repository.status().applications.count == 64)
    repository.configureActivity(enabled: false, retentionDays: 3)
    #expect(repository.status().applications.isEmpty)
    #expect(repository.status().activityCollectionEnabled == false)
    repository.applyActivity(EndpointActivityUpdate(applications: applications))
    #expect(repository.status().applications.isEmpty)

    for index in 0..<130 {
      repository.queueChat(
        text: "Synthetic message \(index)", audience: .direct, threadID: UUID())
    }
    let outbound = repository.drainOutbound()
    #expect(outbound.count == 100)
    #expect(repository.dashboard(markRead: false).messages.count <= 200)
    repository.queueChat(text: "Survives restart", audience: .direct, threadID: UUID())
    let restored = EndpointStatusRepository(
      initial: DeviceSnapshotCollector.collect(deviceID: "synthetic-stage04"),
      persistenceURL: queueURL)
    #expect(restored.dashboard(markRead: false).messages.last?.text == "Survives restart")
    let queueMode =
      ((try? FileManager.default.attributesOfItem(atPath: queueURL.path)[.posixPermissions])
      as? NSNumber)?.intValue ?? 0
    #expect(queueMode & 0o777 == 0o600)
    repository.queueMoreTime(minutes: 9_999, note: String(repeating: "n", count: 900))
    let request = repository.drainOutbound().last
    #expect(request?.payload["minutes"] == .integer(240))
    #expect(request?.payload["note"]?.stringValue?.count == 500)
  }

  @Test("browser metadata is opt-in, bounded, sanitized, and host-authenticated")
  func stage05BrowserPrivacyBoundary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ProtectedConfigurationStore(root: root)
    #expect(try store.load().browserCollectionEnabled == false)
    try store.setBrowserCollection(enabled: true, retentionDays: 999)
    #expect(try store.load().browserCollectionEnabled == true)
    #expect(try store.load().browserRetentionDays == 30)

    let tabs = (0..<150).map { index in
      BrowserNativeTab(
        title: String(repeating: "T", count: 400),
        origin: index == 0
          ? "https://Example.COM:8443/private/path?token=secret#fragment"
          : "https://example(index).test/account?secret=value",
        active: index == 0)
    }
    let update = try #require(
      BrowserNativeRequest(type: "tabs.update", browser: "chrome", profile: "profile", tabs: tabs)
        .validatedUpdate(expectedBrowser: "chrome"))
    #expect(update.tabs.count == BrowserNativeMessaging.maximumTabs)
    #expect(update.tabs[0].title.count == 300)
    #expect(update.tabs[0].origin == "https://example.com:8443")
    #expect(update.tabs.allSatisfy { !$0.origin.contains("?") && !$0.origin.contains("#") })
    #expect(
      EndpointBrowserTab.sanitizedOrigin(
        "https://www.youtube.com/watch?v=private-video-id") == "https://www.youtube.com")
    #expect(
      EndpointBrowserTab.sanitizedOrigin(
        "https://games.example.test/play/session?token=secret")
        == "https://games.example.test")
    #expect(
      BrowserNativeRequest(
        type: "tabs.update", browser: "edge", profile: "profile", tabs: tabs
      ).validatedUpdate(expectedBrowser: "chrome") == nil)

    #expect(
      BrowserCallerAuthorization.expectedBrowser(
        origin: BrowserNativeMessaging.allowedOrigin,
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        signingIdentifier: "com.google.Chrome", teamIdentifier: "EQHXZ8M8AV",
        signatureValid: true) == "chrome")
    #expect(
      BrowserCallerAuthorization.expectedBrowser(
        origin: "chrome-extension://untrusted/",
        executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        signingIdentifier: "com.google.Chrome", teamIdentifier: "EQHXZ8M8AV",
        signatureValid: true) == nil)
    #expect(
      BrowserCallerAuthorization.expectedBrowser(
        origin: BrowserNativeMessaging.allowedOrigin,
        executablePath: "/tmp/Google Chrome", signingIdentifier: "com.google.Chrome",
        teamIdentifier: "EQHXZ8M8AV", signatureValid: true) == nil)
    #expect(
      BrowserCallerAuthorization.expectedBrowser(
        origin: BrowserNativeMessaging.allowedOrigin, executablePath: "/Applications/Arc.app",
        signingIdentifier: "company.thebrowser.Browser", teamIdentifier: "S6N382Y83G",
        signatureValid: true) == "arc")
    #expect(
      BrowserCallerAuthorization.expectedBrowser(
        origin: BrowserNativeMessaging.allowedOrigin,
        executablePath: "/Applications/Arc.app/Contents/Frameworks/Arc Helper.app",
        signingIdentifier: "company.thebrowser.Browser.helper", teamIdentifier: "UNTRUSTED",
        signatureValid: true) == nil)
    #expect(
      XPCAuthorization.allows(
        uid: 501, signingIdentifier: EndpointMachService.browserHostIdentifier,
        operation: "browser-update"))
    #expect(
      !XPCAuthorization.allows(
        uid: 501, signingIdentifier: EndpointMachService.browserHostIdentifier,
        operation: "send-chat"))
  }

  @Test("chat read receipts require explicit conversation visibility")
  func stage05ExplicitReadReceipt() {
    let repository = EndpointStatusRepository(
      initial: DeviceSnapshotCollector.collect(deviceID: "synthetic-stage05"))
    let message = EndpointChatMessage(
      sender: "Parent", text: "Synthetic message", state: .delivered, isFromParent: true)
    let outgoing = EndpointChatMessage(
      sender: "Child", text: "Synthetic reply", state: .delivered, isFromParent: false)
    #expect([message, outgoing].filter(\.isUnreadFromParent).count == 1)
    repository.receiveChat(message)
    #expect(repository.dashboard(markRead: false).messages.first?.state == .delivered)
    #expect(repository.drainOutbound().isEmpty)
    #expect(repository.markParentMessagesRead() == 1)
    #expect(repository.dashboard(markRead: false).messages.first?.state == .read)
    #expect(repository.dashboard(markRead: false).messages.filter(\.isUnreadFromParent).isEmpty)
    let receipt = repository.drainOutbound().first
    #expect(receipt?.kind == .receipt)
    #expect(receipt?.payload["originalMessageId"] == .string(message.id.uuidString))
    #expect(receipt?.payload["state"] == .string(ChatDeliveryState.read.rawValue))
    repository.updateMessageState(message.id, state: .delivered)
    #expect(repository.dashboard(markRead: false).messages.first?.state == .read)
    #expect(repository.markParentMessagesRead() == 0)

    #expect(
      repository.applyParentChatMutation(
        id: message.id, action: "edit", text: "Corrected", mutatedAt: Date()))
    #expect(repository.dashboard(markRead: false).messages.first?.text == "Corrected")
    #expect(repository.dashboard(markRead: false).messages.first?.editedAt != nil)
    #expect(
      repository.applyParentChatMutation(
        id: message.id, action: "delete", text: nil, mutatedAt: Date()))
    #expect(repository.dashboard(markRead: false).messages.first?.displayText == "Message deleted")
    #expect(repository.dashboard(markRead: false).messages.first?.text.isEmpty == true)
  }
}
