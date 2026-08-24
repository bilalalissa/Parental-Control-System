import Foundation
import Network

public enum LocalHubError: Error, CustomStringConvertible {
  case notStarted
  case malformedAnnouncement
  case unknownDevice
  case revokedDevice
  case identityMismatch
  case unexpectedMessage

  public var description: String {
    switch self {
    case .notStarted: "The local hub is not ready"
    case .malformedAnnouncement: "The capability announcement is incomplete"
    case .unknownDevice: "The device is not paired"
    case .revokedDevice: "The device was revoked"
    case .identityMismatch: "The device identity does not match the paired record"
    case .unexpectedMessage: "The message type is not valid in this context"
    }
  }
}

public struct LocalHubStatus: Codable, Equatable, Sendable {
  public let port: UInt16
  public let certificateFingerprint: String
  public let devices: [HubDeviceRecord]
  public let invitation: PairingInvitation?
  public let chatMessages: [HubChatMessage]
  public let activity: [HubAppActivity]
  public let activityConfigurations: [ActivityConfiguration]
  public let browserTabs: [HubBrowserTab]
  public let browserConfigurations: [BrowserConfiguration]
  public let moreTimeRequests: [MoreTimeRequestRecord]
  public let storage: HubStorageSummary

  public init(
    port: UInt16,
    certificateFingerprint: String,
    devices: [HubDeviceRecord],
    invitation: PairingInvitation?,
    chatMessages: [HubChatMessage] = [],
    activity: [HubAppActivity] = [],
    activityConfigurations: [ActivityConfiguration] = [],
    browserTabs: [HubBrowserTab] = [],
    browserConfigurations: [BrowserConfiguration] = [],
    moreTimeRequests: [MoreTimeRequestRecord] = [],
    storage: HubStorageSummary = HubStorageSummary(
      activityRecords: 0, chatMessages: 0, queuedEnvelopes: 0)
  ) {
    self.port = port
    self.certificateFingerprint = certificateFingerprint
    self.devices = devices
    self.invitation = invitation
    self.chatMessages = chatMessages
    self.activity = activity
    self.activityConfigurations = activityConfigurations
    self.browserTabs = browserTabs
    self.browserConfigurations = browserConfigurations
    self.moreTimeRequests = moreTimeRequests
    self.storage = storage
  }
}

public final class LocalHub: @unchecked Sendable {
  private let database: HubDatabase
  private let tlsIdentity: TLSCertificateIdentity
  private let controllerIdentity: Ed25519Identity
  private let pairing = PairingCoordinator()
  private let replay = ReplayProtector()
  private let heartbeat: AdaptiveHeartbeat
  private let listeningPort: UInt16
  private let lock = NSLock()
  private let timerQueue = DispatchQueue(label: "parental-control.hub.heartbeat")
  private var server: SecureWebSocketServer?
  private var timer: DispatchSourceTimer?
  private var port: UInt16 = 0
  private var invitation: PairingInvitation?
  private var devicePeers: [String: SecureWebSocketPeer] = [:]
  private var peerDevices: [UUID: String] = [:]
  private var controllerSequence: UInt64 = 0

  public var onStatusChange: (@Sendable (LocalHubStatus) -> Void)?
  public var onError: (@Sendable (Error) -> Void)?

  public init(
    database: HubDatabase,
    keychain: KeychainStore = KeychainStore(),
    tlsIdentity: TLSCertificateIdentity? = nil,
    controllerIdentity suppliedControllerIdentity: Ed25519Identity? = nil,
    heartbeat: AdaptiveHeartbeat = AdaptiveHeartbeat(),
    listeningPort: UInt16 = SecureWebSocketServer.parentControlPort
  ) throws {
    self.database = database
    self.tlsIdentity = try tlsIdentity ?? TLSCertificateIdentity.loadOrCreate()
    self.heartbeat = heartbeat
    self.listeningPort = listeningPort
    if let suppliedControllerIdentity {
      controllerIdentity = suppliedControllerIdentity
    } else {
      let signingKey = try keychain.loadOrCreateRandom(account: "controller-ed25519", byteCount: 32)
      controllerIdentity = try Ed25519Identity(
        keyID: "controller-local-authority", rawPrivateKey: signingKey)
    }
    for device in try database.devices(includeRevoked: true) {
      replay.seed(deviceID: device.id, sequence: device.lastSequence)
    }
  }

  public func start(advertiseBonjour: Bool = true) throws {
    let server = try SecureWebSocketServer(
      identity: tlsIdentity, port: listeningPort, advertiseBonjour: advertiseBonjour)
    self.server = server
    server.onReady = { [weak self] port in
      guard let self else { return }
      self.lock.lock()
      self.port = port
      self.lock.unlock()
      self.startHeartbeatTimer()
      self.publishStatus()
    }
    server.onPeer = { [weak self] peer in
      peer.onMessage = { [weak self, weak peer] data in
        guard let self, let peer else { return }
        do { try self.handle(data: data, from: peer) } catch {
          try? self.database.appendAudit(
            HubAuditRecord(
              event: "message.rejected", deviceID: nil,
              detail: String(describing: error)))
          self.onError?(error)
        }
      }
      peer.onDisconnect = { [weak self, weak peer] in
        guard let self, let peer else { return }
        self.disconnect(peerID: peer.id)
      }
    }
    server.onFailure = { [weak self] error in self?.onError?(error) }
    server.start()
  }

  public func stop() {
    timer?.cancel()
    timer = nil
    server?.cancel()
    server = nil
    lock.lock()
    devicePeers.removeAll()
    peerDevices.removeAll()
    lock.unlock()
  }

  @discardableResult
  public func createPairingInvitation(
    now: Date = Date(), lifetime: TimeInterval = 300, code: String? = nil
  ) throws -> PairingInvitation {
    lock.lock()
    let currentPort = port
    lock.unlock()
    guard currentPort != 0 else { throw LocalHubError.notStarted }
    let created = pairing.create(
      host: ProcessInfo.processInfo.hostName,
      port: currentPort,
      certificateFingerprint: tlsIdentity.fingerprint,
      controllerPublicKey: controllerIdentity.publicKeyData,
      now: now,
      lifetime: lifetime,
      code: code)
    lock.lock()
    invitation = created
    lock.unlock()
    rescheduleHeartbeat()
    try database.appendAudit(
      HubAuditRecord(
        event: "pairing.opened", deviceID: nil,
        detail: "One-time invitation expires at \(created.expiresAt.formatted(.iso8601))"))
    publishStatus()
    return created
  }

  public func status(now: Date = Date()) throws -> LocalHubStatus {
    lock.lock()
    let currentPort = port
    let currentInvitation = invitation?.expiresAt ?? .distantPast > now ? invitation : nil
    lock.unlock()
    return LocalHubStatus(
      port: currentPort,
      certificateFingerprint: tlsIdentity.fingerprint,
      devices: try database.devices(includeRevoked: true),
      invitation: currentInvitation,
      chatMessages: try database.chatMessages(),
      activity: try database.activity(),
      activityConfigurations: try database.activityConfigurations(),
      browserTabs: try database.browserTabs(),
      browserConfigurations: try database.browserConfigurations(),
      moreTimeRequests: try database.moreTimeRequests(),
      storage: try database.storageSummary())
  }

  @discardableResult
  public func sendChat(
    deviceID: String, text: String, audience: ChatAudience = .direct,
    threadID: UUID = UUID(), now: Date = Date()
  ) throws -> UUID {
    guard let device = try database.device(id: deviceID), !device.isRevoked else {
      throw LocalHubError.unknownDevice
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw LocalHubError.unexpectedMessage }
    let messageID = UUID()
    let envelope = try controllerIdentity.sign(
      deviceID: "controller", sequence: nextControllerSequence(), type: .chatMessage,
      payload: [
        "targetDeviceId": .string(deviceID), "text": .string(String(trimmed.prefix(2_000))),
        "sender": .string("Parent"), "audience": .string(audience.rawValue),
        "threadId": .string(threadID.uuidString),
      ], now: now, lifetime: 30 * 86_400, id: messageID)
    let data = try ProtocolCodec.encode(envelope)
    lock.lock()
    let peer = devicePeers[deviceID]
    lock.unlock()
    let initialState: ChatDeliveryState = peer == nil ? .queued : .sent
    try database.saveChatMessage(
      HubChatMessage(
        id: messageID, deviceID: deviceID, threadID: threadID, sentAt: now,
        sender: "Parent", text: trimmed, state: initialState, audience: audience,
        isFromParent: true))
    if let peer {
      peer.send(data) { [weak self] error in
        guard let self else { return }
        if error != nil {
          try? database.updateChatState(id: messageID, state: .failed)
          try? database.enqueue(
            QueuedEnvelope(
              deviceID: deviceID, expiresAt: now.addingTimeInterval(30 * 86_400),
              envelope: data))
        }
        publishStatus()
      }
    } else {
      try database.enqueue(
        QueuedEnvelope(
          deviceID: deviceID, expiresAt: now.addingTimeInterval(30 * 86_400), envelope: data))
    }
    try database.appendAudit(
      HubAuditRecord(
        event: "chat.outbound", deviceID: deviceID,
        detail: "Queued message metadata for \(audience.rawValue); content omitted"))
    publishStatus()
    return messageID
  }

  public func configureActivity(_ configuration: ActivityConfiguration) throws {
    guard let device = try database.device(id: configuration.deviceID), !device.isRevoked else {
      throw LocalHubError.unknownDevice
    }
    try database.saveActivityConfiguration(configuration)
    let envelope = try controllerIdentity.sign(
      deviceID: "controller", sequence: nextControllerSequence(),
      type: .activityConfiguration,
      payload: [
        "targetDeviceId": .string(configuration.deviceID),
        "enabled": .bool(configuration.enabled),
        "retentionDays": .integer(Int64(configuration.retentionDays)),
      ], lifetime: 7 * 86_400)
    try sendOrQueue(
      envelope, deviceID: configuration.deviceID, lifetime: 7 * 86_400)
    try database.appendAudit(
      HubAuditRecord(
        event: "activity.configuration", deviceID: configuration.deviceID,
        detail: configuration.enabled
          ? "App activity enabled; \(configuration.retentionDays)-day retention"
          : "App activity disabled and retained records removed"))
    publishStatus()
  }

  public func configureBrowser(_ configuration: BrowserConfiguration) throws {
    guard let device = try database.device(id: configuration.deviceID), !device.isRevoked else {
      throw LocalHubError.unknownDevice
    }
    try database.saveBrowserConfiguration(configuration)
    let envelope = try controllerIdentity.sign(
      deviceID: "controller", sequence: nextControllerSequence(), type: .browserConfiguration,
      payload: [
        "targetDeviceId": .string(configuration.deviceID),
        "enabled": .bool(configuration.enabled),
        "retentionDays": .integer(Int64(configuration.retentionDays)),
      ], lifetime: 7 * 86_400)
    try sendOrQueue(envelope, deviceID: configuration.deviceID, lifetime: 7 * 86_400)
    try database.appendAudit(
      HubAuditRecord(
        event: "browser.configuration", deviceID: configuration.deviceID,
        detail: configuration.enabled
          ? "Browser title/origin sharing enabled; \(configuration.retentionDays)-day retention"
          : "Browser sharing disabled and retained tab metadata removed"))
    publishStatus()
  }

  public func markChatRead(deviceID: String, audience: ChatAudience) throws {
    let messages = try database.chatMessages(limit: 2_000).filter {
      $0.deviceID == deviceID && !$0.isFromParent && $0.audience == audience
        && $0.state != .read
    }
    for message in messages {
      try database.updateChatState(id: message.id, state: .read)
      let receipt = try controllerIdentity.sign(
        deviceID: "controller", sequence: nextControllerSequence(), type: .receipt,
        payload: [
          "originalMessageId": .string(message.id.uuidString),
          "state": .string(ChatDeliveryState.read.rawValue),
        ], lifetime: 30 * 86_400)
      try sendOrQueue(receipt, deviceID: deviceID, lifetime: 30 * 86_400)
    }
    if !messages.isEmpty {
      try database.appendAudit(
        HubAuditRecord(
          event: "chat.read", deviceID: deviceID,
          detail: "Marked \(messages.count) message receipt(s) read; content omitted"))
      publishStatus()
    }
  }

  public func editParentChatMessage(id: UUID, text: String, now: Date = Date()) throws {
    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
    guard !trimmed.isEmpty else { throw LocalHubError.unexpectedMessage }
    try mutateParentChatMessage(id: id, action: "edit", text: trimmed, now: now)
  }

  public func deleteParentChatMessage(id: UUID, now: Date = Date()) throws {
    try mutateParentChatMessage(id: id, action: "delete", text: "", now: now)
  }

  private func mutateParentChatMessage(
    id: UUID, action: String, text: String, now: Date
  ) throws {
    guard
      let message = try database.chatMessages(limit: 2_000).first(where: { $0.id == id }),
      message.isFromParent, message.deletedAt == nil,
      let device = try database.device(id: message.deviceID), !device.isRevoked
    else { throw LocalHubError.unexpectedMessage }
    let isDelete = action == "delete"
    try database.mutateParentChatMessage(
      id: id, text: isDelete ? "" : text, editedAt: isDelete ? message.editedAt : now,
      deletedAt: isDelete ? now : nil)
    var payload: [String: JSONValue] = [
      "targetDeviceId": .string(message.deviceID),
      "originalMessageId": .string(id.uuidString),
      "action": .string(action),
      "mutatedAt": .string(ISO8601DateFormatter().string(from: now)),
    ]
    if !isDelete { payload["text"] = .string(text) }
    let envelope = try controllerIdentity.sign(
      deviceID: "controller", sequence: nextControllerSequence(), type: .chatMutation,
      payload: payload, now: now, lifetime: 30 * 86_400)
    try sendOrQueue(envelope, deviceID: message.deviceID, lifetime: 30 * 86_400)
    try database.appendAudit(
      HubAuditRecord(
        event: isDelete ? "chat.deleted" : "chat.edited", deviceID: message.deviceID,
        detail: "Parent message metadata changed; content omitted"))
    publishStatus()
  }

  public func revoke(deviceID: String) throws {
    try database.revoke(deviceID: deviceID)
    lock.lock()
    let peer = devicePeers.removeValue(forKey: deviceID)
    if let peer { peerDevices.removeValue(forKey: peer.id) }
    lock.unlock()
    peer?.cancel()
    try database.appendAudit(
      HubAuditRecord(event: "device.revoked", deviceID: deviceID, detail: "Pairing revoked"))
    publishStatus()
  }

  public func unpair(deviceID: String) throws {
    lock.lock()
    let peer = devicePeers.removeValue(forKey: deviceID)
    if let peer { peerDevices.removeValue(forKey: peer.id) }
    lock.unlock()
    peer?.cancel()
    try database.appendAudit(
      HubAuditRecord(event: "device.unpaired", deviceID: deviceID, detail: "Device removed"))
    try database.unpair(deviceID: deviceID)
    publishStatus()
  }

  private func handle(data: Data, from peer: SecureWebSocketPeer) throws {
    let envelope = try ProtocolCodec.decode(data)
    if let existing = try database.device(id: envelope.deviceID) {
      guard !existing.isRevoked else { throw LocalHubError.revokedDevice }
      guard existing.keyID == envelope.auth.keyID else { throw LocalHubError.identityMismatch }
      try replay.verify(envelope, publicKey: existing.publicKey)
      bind(peer: peer, deviceID: existing.id)
      try accept(envelope, device: existing, peer: peer)
    } else {
      try acceptInitialPairing(envelope, peer: peer)
    }
    publishStatus()
  }

  private func acceptInitialPairing(_ envelope: ProtocolEnvelope, peer: SecureWebSocketPeer) throws
  {
    guard
      envelope.type == .capabilityAnnounce,
      let code = envelope.payload["pairingCode"]?.stringValue,
      let name = envelope.payload["name"]?.stringValue,
      let platform = envelope.payload["platform"]?.stringValue,
      let publicKeyText = envelope.payload["publicKey"]?.stringValue,
      let publicKey = Data(base64Encoded: publicKeyText),
      case .array(let capabilityValues) = envelope.payload["capabilities"],
      capabilityValues.allSatisfy({ $0.stringValue != nil })
    else { throw LocalHubError.malformedAnnouncement }
    guard envelope.auth.keyID == "device-\(envelope.deviceID)" else {
      throw LocalHubError.identityMismatch
    }
    try replay.verify(envelope, publicKey: publicKey)
    try pairing.consume(code: code)
    let capabilities = capabilityValues.compactMap(\.stringValue)
    let device = HubDeviceRecord(
      id: envelope.deviceID,
      name: String(name.prefix(80)),
      platform: String(platform.prefix(40)),
      keyID: envelope.auth.keyID,
      publicKey: publicKey,
      capabilities: Array(capabilities.prefix(32)),
      pairedAt: Date(),
      lastSeen: Date(),
      lastSequence: envelope.sequence)
    try database.upsertDevice(device)
    lock.lock()
    invitation = nil
    lock.unlock()
    bind(peer: peer, deviceID: device.id)
    try database.appendAudit(
      HubAuditRecord(
        event: "device.paired", deviceID: device.id,
        detail: "Paired \(device.name) with \(device.capabilities.count) declared capabilities"))
    try sendReceipt(for: envelope, state: "accepted", to: peer, deviceID: device.id)
  }

  private func accept(
    _ envelope: ProtocolEnvelope,
    device: HubDeviceRecord,
    peer: SecureWebSocketPeer
  ) throws {
    switch envelope.type {
    case .capabilityAnnounce:
      try database.updateSeen(
        deviceID: device.id, sequence: envelope.sequence,
        snapshotVersion: device.snapshotVersion)
    case .snapshotResponse:
      let version = UInt64(max(0, envelope.payload["snapshotVersion"]?.integerValue ?? 0))
      try database.updateSeen(
        deviceID: device.id, sequence: envelope.sequence, snapshotVersion: version)
      try database.appendAudit(
        HubAuditRecord(
          event: "snapshot.delta", deviceID: device.id,
          detail: "Accepted snapshot version \(version)"))
    case .activityUpdate:
      let enabled =
        try database.activityConfigurations().first { $0.deviceID == device.id }?
        .enabled ?? true
      if enabled, case .array(let values) = envelope.payload["applications"] {
        let records = values.prefix(64).compactMap { value -> HubAppActivity? in
          guard case .object(let item) = value,
            let bundleID = item["bundleIdentifier"]?.stringValue,
            let name = item["applicationName"]?.stringValue,
            let foreground = item["isForeground"]?.boolValue,
            let observedText = item["observedAt"]?.stringValue,
            let observed = ISO8601DateFormatter().date(from: observedText)
          else { return nil }
          return HubAppActivity(
            deviceID: device.id, bundleIdentifier: bundleID, applicationName: name,
            isForeground: foreground, observedAt: observed)
        }
        try database.saveActivity(records, for: device.id)
      }
      try database.updateSeen(
        deviceID: device.id, sequence: envelope.sequence,
        snapshotVersion: device.snapshotVersion)
      try database.appendAudit(
        HubAuditRecord(
          event: "activity.delta", deviceID: device.id,
          detail: "Accepted bounded app activity metadata; no command lines or content"))
    case .browserUpdate:
      let enabled =
        try database.browserConfigurations().first { $0.deviceID == device.id }?.enabled ?? false
      if enabled, case .array(let values) = envelope.payload["tabs"] {
        let records = values.prefix(128).compactMap { value -> HubBrowserTab? in
          guard case .object(let item) = value,
            let browser = item["browser"]?.stringValue,
            let profile = item["profile"]?.stringValue,
            let title = item["title"]?.stringValue,
            let originValue = item["origin"]?.stringValue,
            let origin = Self.sanitizedBrowserOrigin(originValue),
            let active = item["isActive"]?.boolValue,
            let observedText = item["observedAt"]?.stringValue,
            let observed = ISO8601DateFormatter().date(from: observedText)
          else { return nil }
          return HubBrowserTab(
            deviceID: device.id, browser: browser, profileID: profile, title: title,
            origin: origin, isActive: active, observedAt: observed)
        }
        try database.saveBrowserObservations(records, for: device.id)
      }
      try database.updateSeen(
        deviceID: device.id, sequence: envelope.sequence,
        snapshotVersion: device.snapshotVersion)
      try database.appendAudit(
        HubAuditRecord(
          event: "browser.delta", deviceID: device.id,
          detail: "Accepted bounded tab titles and query-free origins; content omitted"))
    case .chatMessage:
      guard let text = envelope.payload["text"]?.stringValue,
        let audienceText = envelope.payload["audience"]?.stringValue,
        let audience = ChatAudience(rawValue: audienceText)
      else { throw LocalHubError.unexpectedMessage }
      let threadID =
        envelope.payload["threadId"]?.stringValue.flatMap(UUID.init(uuidString:))
        ?? UUID()
      try database.saveChatMessage(
        HubChatMessage(
          id: envelope.id, deviceID: device.id, threadID: threadID,
          sentAt: envelope.sentAt, sender: String(device.name.prefix(80)), text: text,
          state: .delivered, audience: audience, isFromParent: false))
      try database.appendAudit(
        HubAuditRecord(
          event: "chat.inbound", deviceID: device.id,
          detail: "Received message metadata; content omitted"))
      try database.updateSeen(
        deviceID: device.id, sequence: envelope.sequence,
        snapshotVersion: device.snapshotVersion)
    case .chatMutation:
      throw LocalHubError.unexpectedMessage
    case .requestMoreTime:
      let minutes = Int(envelope.payload["minutes"]?.integerValue ?? 15)
      let note = envelope.payload["note"]?.stringValue ?? ""
      try database.appendMoreTimeRequest(
        MoreTimeRequestRecord(
          id: envelope.id, deviceID: device.id, requestedMinutes: minutes, note: note,
          createdAt: envelope.sentAt))
      try database.appendAudit(
        HubAuditRecord(
          event: "time.requested", deviceID: device.id,
          detail: "Requested \(max(5, min(minutes, 240))) minutes; note content omitted"))
      try database.updateSeen(
        deviceID: device.id, sequence: envelope.sequence,
        snapshotVersion: device.snapshotVersion)
    case .receipt:
      guard
        let originalText = envelope.payload["originalMessageId"]?.stringValue,
        let original = UUID(uuidString: originalText),
        let state = envelope.payload["state"]?.stringValue
      else { throw LocalHubError.unexpectedMessage }
      try database.appendReceipt(
        ReceiptRecord(deviceID: device.id, originalMessageID: original, state: state))
      if let deliveryState = ChatDeliveryState(rawValue: state) {
        try database.updateChatState(id: original, state: deliveryState)
      } else if state == "accepted" {
        try database.updateChatState(id: original, state: .delivered)
      }
      try database.updateSeen(
        deviceID: device.id, sequence: envelope.sequence,
        snapshotVersion: device.snapshotVersion)
    case .activityConfiguration, .browserConfiguration, .snapshotRequest:
      throw LocalHubError.unexpectedMessage
    }
    try sendReceipt(for: envelope, state: "accepted", to: peer, deviceID: device.id)
  }

  private func sendReceipt(
    for envelope: ProtocolEnvelope,
    state: String,
    to peer: SecureWebSocketPeer,
    deviceID: String
  ) throws {
    let receipt = try controllerIdentity.sign(
      deviceID: "controller",
      sequence: nextControllerSequence(),
      type: .receipt,
      payload: [
        "originalMessageId": .string(envelope.id.uuidString),
        "state": .string(state),
        "heartbeatActiveSeconds": .integer(Int64(heartbeat.activeInterval)),
        "heartbeatIdleSeconds": .integer(Int64(heartbeat.idleInterval)),
      ])
    let data = try ProtocolCodec.encode(receipt)
    peer.send(data) { [weak self] error in
      guard let self, error != nil else { return }
      try? database.enqueue(
        QueuedEnvelope(
          deviceID: deviceID,
          expiresAt: Date().addingTimeInterval(120),
          envelope: data))
    }
  }

  private static func sanitizedBrowserOrigin(_ value: String) -> String? {
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", let host = url.host?.lowercased(),
      url.query == nil, url.fragment == nil
    else { return nil }
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = url.port
    return components.url?.absoluteString
  }

  private func bind(peer: SecureWebSocketPeer, deviceID: String) {
    lock.lock()
    if let former = devicePeers.updateValue(peer, forKey: deviceID), former.id != peer.id {
      former.cancel()
    }
    peerDevices[peer.id] = deviceID
    lock.unlock()
    rescheduleHeartbeat()
    if let queued = try? database.queued(deviceID: deviceID) {
      for item in queued {
        peer.send(item.envelope) { [weak self] error in
          guard error == nil else { return }
          try? self?.database.removeQueued(id: item.id)
        }
      }
    }
  }

  private func sendOrQueue(
    _ envelope: ProtocolEnvelope, deviceID: String, lifetime: TimeInterval
  ) throws {
    let data = try ProtocolCodec.encode(envelope)
    lock.lock()
    let peer = devicePeers[deviceID]
    lock.unlock()
    if let peer {
      peer.send(data) { [weak self] error in
        guard let self, error != nil else { return }
        try? database.enqueue(
          QueuedEnvelope(
            deviceID: deviceID, expiresAt: Date().addingTimeInterval(lifetime), envelope: data))
      }
    } else {
      try database.enqueue(
        QueuedEnvelope(
          deviceID: deviceID, expiresAt: Date().addingTimeInterval(lifetime), envelope: data))
    }
  }

  private func disconnect(peerID: UUID) {
    lock.lock()
    if let deviceID = peerDevices.removeValue(forKey: peerID),
      devicePeers[deviceID]?.id == peerID
    {
      devicePeers.removeValue(forKey: deviceID)
    }
    lock.unlock()
    rescheduleHeartbeat()
    publishStatus()
  }

  private func startHeartbeatTimer() {
    let timer = DispatchSource.makeTimerSource(queue: timerQueue)
    timer.schedule(deadline: .now() + heartbeat.idleInterval, repeating: heartbeat.idleInterval)
    timer.setEventHandler { [weak self] in self?.requestSnapshots() }
    self.timer = timer
    timer.resume()
  }

  private func rescheduleHeartbeat() {
    lock.lock()
    let hasActivePeers = !devicePeers.isEmpty
    let currentTimer = timer
    lock.unlock()
    let interval = hasActivePeers ? heartbeat.activeInterval : heartbeat.idleInterval
    currentTimer?.schedule(deadline: .now() + interval, repeating: interval)
  }

  private func requestSnapshots() {
    lock.lock()
    let peers = devicePeers
    lock.unlock()
    for (deviceID, peer) in peers {
      do {
        let request = try controllerIdentity.sign(
          deviceID: "controller",
          sequence: nextControllerSequence(),
          type: .snapshotRequest,
          payload: ["targetDeviceId": .string(deviceID)])
        peer.ping()
        peer.send(try ProtocolCodec.encode(request))
      } catch { onError?(error) }
    }
    publishStatus()
  }

  private func nextControllerSequence() -> UInt64 {
    lock.lock()
    controllerSequence += 1
    let value = controllerSequence
    lock.unlock()
    return value
  }

  private func publishStatus() {
    guard let status = try? status() else { return }
    onStatusChange?(status)
  }
}
