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

  public init(
    port: UInt16,
    certificateFingerprint: String,
    devices: [HubDeviceRecord],
    invitation: PairingInvitation?
  ) {
    self.port = port
    self.certificateFingerprint = certificateFingerprint
    self.devices = devices
    self.invitation = invitation
  }
}

public final class LocalHub: @unchecked Sendable {
  private let database: HubDatabase
  private let tlsIdentity: TLSCertificateIdentity
  private let controllerIdentity: Ed25519Identity
  private let pairing = PairingCoordinator()
  private let replay = ReplayProtector()
  private let heartbeat: AdaptiveHeartbeat
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
    heartbeat: AdaptiveHeartbeat = AdaptiveHeartbeat()
  ) throws {
    self.database = database
    self.tlsIdentity = try tlsIdentity ?? TLSCertificateIdentity.loadOrCreate()
    self.heartbeat = heartbeat
    let signingKey = try keychain.loadOrCreateRandom(account: "controller-ed25519", byteCount: 32)
    controllerIdentity = try Ed25519Identity(
      keyID: "controller-local-authority", rawPrivateKey: signingKey)
    for device in try database.devices(includeRevoked: true) {
      replay.seed(deviceID: device.id, sequence: device.lastSequence)
    }
  }

  public func start(advertiseBonjour: Bool = true) throws {
    let server = try SecureWebSocketServer(
      identity: tlsIdentity, advertiseBonjour: advertiseBonjour)
    self.server = server
    server.onReady = { [weak self] port in
      guard let self else { return }
      lock.lock()
      self.port = port
      lock.unlock()
      startHeartbeatTimer()
      publishStatus()
    }
    server.onPeer = { [weak self] peer in
      peer.onMessage = { [weak self, weak peer] data in
        guard let self, let peer else { return }
        do { try handle(data: data, from: peer) } catch {
          try? database.appendAudit(
            HubAuditRecord(
              event: "message.rejected", deviceID: nil,
              detail: String(describing: error)))
          onError?(error)
        }
      }
      peer.onDisconnect = { [weak self, weak peer] in
        guard let self, let peer else { return }
        disconnect(peerID: peer.id)
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
      invitation: currentInvitation)
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
    case .receipt:
      guard
        let originalText = envelope.payload["originalMessageId"]?.stringValue,
        let original = UUID(uuidString: originalText),
        let state = envelope.payload["state"]?.stringValue
      else { throw LocalHubError.unexpectedMessage }
      try database.appendReceipt(
        ReceiptRecord(deviceID: device.id, originalMessageID: original, state: state))
      try database.updateSeen(
        deviceID: device.id, sequence: envelope.sequence,
        snapshotVersion: device.snapshotVersion)
    case .chatMessage, .snapshotRequest:
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
