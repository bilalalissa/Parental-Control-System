import AppKit
import Foundation
import HubCore
import Network

public final class EndpointAgent: @unchecked Sendable {
  private let store: ProtectedConfigurationStore
  private let repository: EndpointStatusRepository
  private let log: BoundedLog
  private let identity: Ed25519Identity
  private var replay = ReplayProtector()
  private let delta = DeltaSnapshotTracker()
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "parental-control.endpoint.heartbeat")
  private var peer: SecureWebSocketPeer?
  private var timer: DispatchSourceTimer?
  private var activeInterval: TimeInterval = 30
  private var idleInterval: TimeInterval = 120
  private var pendingPairingMessage: UUID?
  private var lastSentApplications: [EndpointApplicationActivity] = []

  public init(
    store: ProtectedConfigurationStore, repository: EndpointStatusRepository, log: BoundedLog,
    keychain: KeychainStore = KeychainStore(service: "com.bilalalissa.ParentalControlAgent.device"),
    suppliedIdentity: Ed25519Identity? = nil
  ) throws {
    self.store = store
    self.repository = repository
    self.log = log
    let configuration = try store.load()
    repository.configureActivity(
      enabled: configuration.activityCollectionEnabled,
      retentionDays: configuration.activityRetentionDays)
    if let suppliedIdentity {
      identity = suppliedIdentity
    } else {
      let key = try keychain.loadOrCreateRandom(
        account: "device-\(configuration.deviceID)", byteCount: 32)
      identity = try Ed25519Identity(keyID: "device-\(configuration.deviceID)", rawPrivateKey: key)
    }
  }

  public func start() throws {
    let configuration = try store.load()
    guard let target = configuration.invitation ?? configuration.pairedController else {
      repository.update { $0.connectionState = .unpaired }
      log.write(event: "connection.unpaired", detail: "Waiting for administrator pairing")
      return
    }
    repository.update { $0.connectionState = .connecting }
    lock.lock()
    replay = ReplayProtector()
    lock.unlock()
    let connection = try SecureWebSocketClient.connect(
      host: target.host, port: target.port, certificateFingerprint: target.certificateFingerprint)
    peer = connection
    connection.onState = { [weak self] state in self?.connectionChanged(state) }
    connection.onMessage = { [weak self] data in
      self?.receive(data, controllerKey: target.controllerPublicKey)
    }
    connection.onDisconnect = { [weak self] in self?.disconnected() }
    connection.start()
  }

  public func stop() {
    timer?.cancel()
    timer = nil
    peer?.cancel()
    peer = nil
  }

  private func connectionChanged(_ state: NWConnection.State) {
    switch state {
    case .ready:
      do { try announce() } catch { fail(error) }
    case .failed(let error): fail(error)
    default: break
    }
  }

  private func announce() throws {
    let configuration = try store.load()
    var payload: [String: JSONValue] = [
      "name": .string(repository.status().deviceName),
      "platform": .string("macOS"),
      "publicKey": .string(identity.publicKeyData.base64EncodedString()),
      "capabilities": .array([
        .string("presence"), .string("device-info"), .string("uptime"), .string("session-state"),
        .string("network-metadata"), .string("health"), .string("delta-snapshot"),
        .string("receipt"), .string("app-activity"), .string("chat"),
        .string("request-more-time"), .string("notifications"),
      ]),
    ]
    if let code = configuration.invitation?.code, !code.isEmpty {
      payload["pairingCode"] = .string(code)
    }
    let envelope = try identity.sign(
      deviceID: configuration.deviceID, sequence: store.nextSequence(), type: .capabilityAnnounce,
      payload: payload)
    pendingPairingMessage = configuration.invitation == nil ? nil : envelope.id
    try send(envelope)
    log.write(event: "connection.announce", detail: "Capability announcement sent")
  }

  private func receive(_ data: Data, controllerKey: Data) {
    do {
      let envelope = try ProtocolCodec.decode(data)
      try replay.verify(envelope, publicKey: controllerKey)
      switch envelope.type {
      case .receipt:
        let completedPairing =
          envelope.payload["originalMessageId"]?.stringValue == pendingPairingMessage?.uuidString
        if completedPairing {
          try store.markPaired()
          pendingPairingMessage = nil
        }
        if let active = envelope.payload["heartbeatActiveSeconds"]?.integerValue {
          activeInterval = max(15, TimeInterval(active))
        }
        if let idle = envelope.payload["heartbeatIdleSeconds"]?.integerValue {
          idleInterval = max(activeInterval, TimeInterval(idle))
        }
        if let originalText = envelope.payload["originalMessageId"]?.stringValue,
          let original = UUID(uuidString: originalText),
          let stateText = envelope.payload["state"]?.stringValue,
          let state = ChatDeliveryState(rawValue: stateText)
        {
          repository.updateMessageState(original, state: state)
        }
        repository.update {
          $0.connectionState = .online
          $0.lastControllerContact = Date()
        }
        if completedPairing { try sendSnapshot(reason: "paired") }
        try flushOutbound()
        scheduleHeartbeat(active: true)
      case .snapshotRequest:
        repository.update { $0.lastControllerContact = Date() }
        try sendSnapshot(reason: "controller-request")
        try flushOutbound()
        scheduleHeartbeat(active: true)
      case .chatMessage:
        try receiveChat(envelope)
      case .activityConfiguration:
        try receiveActivityConfiguration(envelope)
      case .activityUpdate, .requestMoreTime, .capabilityAnnounce, .snapshotResponse:
        break
      }
    } catch { fail(error) }
  }

  private func sendSnapshot(reason: String) throws {
    let configuration = try store.load()
    let former = repository.status()
    var refreshed = DeviceSnapshotCollector.collect(
      deviceID: configuration.deviceID,
      session: SessionUpdate(state: former.sessionState, consoleUser: former.consoleUser))
    refreshed.connectionState = .online
    refreshed.lastControllerContact = former.lastControllerContact
    refreshed.helperHealthy = former.helperHealthy
    refreshed.activityCollectionEnabled = former.activityCollectionEnabled
    refreshed.activityRetentionDays = former.activityRetentionDays
    refreshed.applications = former.applications
    repository.update { $0 = refreshed }
    let networks: [JSONValue] = refreshed.networks.map { network in
      .object([
        "interface": .string(network.interface),
        "addresses": .array(network.addresses.map(JSONValue.string)),
        "macAddress": network.macAddress.map(JSONValue.string) ?? .null,
      ])
    }
    let snapshot: [String: JSONValue] = [
      "state": .string("online"), "deviceName": .string(refreshed.deviceName),
      "model": .string(refreshed.model),
      "operatingSystem": .string(refreshed.operatingSystem),
      "architecture": .string(refreshed.architecture),
      "uptimeSeconds": .integer(Int64(clamping: refreshed.uptimeSeconds)),
      "bootTime": .string(ISO8601DateFormatter().string(from: refreshed.bootTime)),
      "sessionState": .string(refreshed.sessionState.rawValue),
      "consoleUser": refreshed.consoleUser.map(JSONValue.string) ?? .null,
      "networks": .array(networks), "daemonHealthy": .bool(true),
      "helperHealthy": .bool(refreshed.helperHealthy),
    ]
    let update = delta.delta(for: snapshot)
    let envelope = try identity.sign(
      deviceID: configuration.deviceID, sequence: store.nextSequence(), type: .snapshotResponse,
      payload: [
        "snapshotVersion": .integer(Int64(clamping: update.version)),
        "changed": .object(update.changed), "reason": .string(reason),
      ])
    try send(envelope)
    try sendActivityIfChanged(configuration: configuration, status: refreshed)
    try flushOutbound()
  }

  private func sendActivityIfChanged(
    configuration: EndpointConfiguration, status: EndpointStatus
  ) throws {
    let applications = status.activityCollectionEnabled ? Array(status.applications.prefix(64)) : []
    lock.lock()
    let changed = applications != lastSentApplications
    if changed { lastSentApplications = applications }
    lock.unlock()
    guard changed else { return }
    let values: [JSONValue] = applications.map { application in
      .object([
        "bundleIdentifier": .string(application.bundleIdentifier),
        "applicationName": .string(application.applicationName),
        "isForeground": .bool(application.isForeground),
        "observedAt": .string(ISO8601DateFormatter().string(from: application.observedAt)),
      ])
    }
    let envelope = try identity.sign(
      deviceID: configuration.deviceID, sequence: store.nextSequence(),
      type: .activityUpdate, payload: ["applications": .array(values)])
    try send(envelope)
  }

  private func receiveChat(_ envelope: ProtocolEnvelope) throws {
    let configuration = try store.load()
    guard envelope.payload["targetDeviceId"]?.stringValue == configuration.deviceID,
      let text = envelope.payload["text"]?.stringValue,
      let audienceText = envelope.payload["audience"]?.stringValue,
      let audience = ChatAudience(rawValue: audienceText)
    else { throw EndpointAgentError.invalidMessage }
    let threadID =
      envelope.payload["threadId"]?.stringValue.flatMap(UUID.init(uuidString:))
      ?? UUID()
    repository.receiveChat(
      EndpointChatMessage(
        id: envelope.id, threadID: threadID, sentAt: envelope.sentAt, sender: "Parent",
        text: text, audience: audience, state: .delivered, isFromParent: true))
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("com.bilalalissa.ParentalControlAgent.chat-received"), object: nil,
      userInfo: nil, deliverImmediately: true)
    try sendReceipt(for: envelope.id, state: .delivered)
    try flushOutbound()
    log.write(event: "chat.received", detail: "Message metadata received; content omitted")
  }

  private func receiveActivityConfiguration(_ envelope: ProtocolEnvelope) throws {
    let configuration = try store.load()
    guard envelope.payload["targetDeviceId"]?.stringValue == configuration.deviceID,
      let enabled = envelope.payload["enabled"]?.boolValue
    else { throw EndpointAgentError.invalidMessage }
    let retention = Int(envelope.payload["retentionDays"]?.integerValue ?? 7)
    try store.setActivityCollection(enabled: enabled, retentionDays: retention)
    repository.configureActivity(enabled: enabled, retentionDays: retention)
    try sendReceipt(for: envelope.id, state: .delivered)
    log.write(
      event: "activity.configuration",
      detail: enabled
        ? "Collection enabled with \(max(1, min(retention, 30))) day retention"
        : "Collection disabled")
  }

  private func sendReceipt(for originalID: UUID, state: ChatDeliveryState) throws {
    let configuration = try store.load()
    let receipt = try identity.sign(
      deviceID: configuration.deviceID, sequence: store.nextSequence(), type: .receipt,
      payload: [
        "originalMessageId": .string(originalID.uuidString), "state": .string(state.rawValue),
      ])
    try send(receipt)
  }

  private func flushOutbound() throws {
    let configuration = try store.load()
    let items = repository.drainOutbound()
    for (index, item) in items.enumerated() {
      do {
        let type: ProtocolMessageType
        switch item.kind {
        case .chat: type = .chatMessage
        case .requestMoreTime: type = .requestMoreTime
        case .receipt: type = .receipt
        }
        let envelope = try identity.sign(
          deviceID: configuration.deviceID, sequence: store.nextSequence(), type: type,
          payload: item.payload, id: item.id)
        try send(envelope)
        if item.kind == .chat { repository.markSent(item.id) }
      } catch {
        repository.requeue(Array(items[index...]))
        throw error
      }
    }
  }

  private func send(_ envelope: ProtocolEnvelope) throws {
    guard let peer else { throw EndpointAgentError.notConnected }
    peer.send(try ProtocolCodec.encode(envelope)) { [weak self] error in
      if let error { self?.fail(error) }
    }
  }

  private func scheduleHeartbeat(active: Bool) {
    let interval = active ? activeInterval : idleInterval
    if let timer {
      timer.schedule(deadline: .now() + interval, repeating: interval)
      return
    }
    let created = DispatchSource.makeTimerSource(queue: queue)
    created.schedule(deadline: .now() + interval, repeating: interval)
    created.setEventHandler { [weak self] in
      guard let self else { return }
      do {
        try sendSnapshot(reason: "adaptive-heartbeat")
        scheduleHeartbeat(active: false)
      } catch { fail(error) }
    }
    timer = created
    created.resume()
  }

  private func disconnected() {
    repository.update { if $0.connectionState != .unpaired { $0.connectionState = .offline } }
    log.write(event: "connection.offline", detail: "Controller connection closed")
  }
  private func fail(_ error: Error) {
    repository.update { $0.connectionState = .offline }
    log.write(event: "connection.error", detail: String(describing: error))
  }
}

public enum EndpointAgentError: Error {
  case notConnected
  case invalidMessage
}
