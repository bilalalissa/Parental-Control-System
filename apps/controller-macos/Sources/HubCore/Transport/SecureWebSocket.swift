import CryptoKit
import Foundation
import Network
import Security

public enum SecureWebSocketError: Error, CustomStringConvertible {
  case invalidCertificateFingerprint
  case listenerFailed(String)
  case connectionFailed(String)
  case oversizedMessage
  case handshakeFailed
  case protocolViolation

  public var description: String {
    switch self {
    case .invalidCertificateFingerprint: "The TLS certificate fingerprint is invalid"
    case .listenerFailed(let detail): "Secure WebSocket listener failed: \(detail)"
    case .connectionFailed(let detail): "Secure WebSocket connection failed: \(detail)"
    case .oversizedMessage: "Secure WebSocket message exceeded the 64 KiB limit"
    case .handshakeFailed: "The WebSocket upgrade handshake failed"
    case .protocolViolation: "The peer sent an invalid WebSocket frame"
    }
  }
}

public final class SecureWebSocketPeer: @unchecked Sendable {
  fileprivate enum Role {
    case server
    case client(host: String)
  }

  public let id = UUID()
  private let connection: NWConnection
  private let role: Role
  private let queue: DispatchQueue
  private let lock = NSLock()
  private var closed = false
  private var upgraded = false
  private var receiveBuffer = Data()
  private var clientHandshakeKey: String?

  public var onMessage: (@Sendable (Data) -> Void)?
  public var onState: (@Sendable (NWConnection.State) -> Void)?
  public var onDisconnect: (@Sendable () -> Void)?

  fileprivate init(connection: NWConnection, role: Role, label: String) {
    self.connection = connection
    self.role = role
    queue = DispatchQueue(label: label)
  }

  public func start() {
    connection.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      if case .ready = state {
        if case .client(let host) = role { sendClientHandshake(host: host) }
      } else {
        onState?(state)
      }
      if case .failed = state { onDisconnect?() }
      if case .cancelled = state { onDisconnect?() }
    }
    connection.start(queue: queue)
    receiveNext()
  }

  public func send(_ data: Data, completion: (@Sendable (Error?) -> Void)? = nil) {
    guard data.count <= ProtocolCodec.maximumMessageBytes else {
      completion?(SecureWebSocketError.oversizedMessage)
      return
    }
    queue.async { [weak self] in
      guard let self, upgraded else {
        completion?(SecureWebSocketError.handshakeFailed)
        return
      }
      sendFrame(opcode: 0x2, payload: data, completion: completion)
    }
  }

  public func ping() {
    queue.async { [weak self] in
      guard let self, upgraded else { return }
      sendFrame(opcode: 0x9, payload: Data(), completion: nil)
    }
  }

  public func cancel() {
    lock.lock()
    let shouldCancel = !closed
    closed = true
    lock.unlock()
    if shouldCancel { connection.cancel() }
  }

  private func sendClientHandshake(host: String) {
    var nonce = Data(count: 16)
    guard
      nonce.withUnsafeMutableBytes({
        SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
      }) == errSecSuccess
    else {
      cancel()
      return
    }
    let key = nonce.base64EncodedString()
    clientHandshakeKey = key
    let request =
      "GET /hub HTTP/1.1\r\n"
      + "Host: \(host)\r\n"
      + "Upgrade: websocket\r\n"
      + "Connection: Upgrade\r\n"
      + "Sec-WebSocket-Key: \(key)\r\n"
      + "Sec-WebSocket-Version: 13\r\n"
      + "Sec-WebSocket-Protocol: parental-control.v1\r\n\r\n"
    connection.send(content: Data(request.utf8), completion: .idempotent)
  }

  private func receiveNext() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
      [weak self] data, _, isComplete, error in
      guard let self else { return }
      if let data, !data.isEmpty {
        receiveBuffer.append(data)
        processBuffer()
      }
      if error == nil, !isComplete, !isClosed {
        receiveNext()
      } else if error != nil || isComplete {
        cancel()
      }
    }
  }

  private func processBuffer() {
    if !upgraded {
      guard let boundary = receiveBuffer.range(of: Data("\r\n\r\n".utf8)) else {
        if receiveBuffer.count > 8 * 1024 { cancel() }
        return
      }
      let headerData = receiveBuffer[..<boundary.upperBound]
      receiveBuffer.removeSubrange(..<boundary.upperBound)
      guard let headers = String(data: headerData, encoding: .utf8), completeHandshake(headers)
      else {
        cancel()
        return
      }
      upgraded = true
      onState?(.ready)
    }
    while let frame = try? nextFrame(), let frame {
      switch frame.opcode {
      case 0x1, 0x2: onMessage?(frame.payload)
      case 0x8:
        cancel()
        return
      case 0x9: sendFrame(opcode: 0xA, payload: frame.payload, completion: nil)
      case 0xA: break
      default:
        cancel()
        return
      }
    }
  }

  private func completeHandshake(_ headerBlock: String) -> Bool {
    switch role {
    case .server:
      let headers = Self.parseHeaders(headerBlock)
      guard
        headerBlock.hasPrefix("GET /hub HTTP/1.1\r\n"),
        headers["upgrade"]?.lowercased() == "websocket",
        headers["connection"]?.lowercased().contains("upgrade") == true,
        headers["sec-websocket-version"] == "13",
        headers["sec-websocket-protocol"]?.split(separator: ",").map({
          $0.trimmingCharacters(in: .whitespaces)
        })
        .contains("parental-control.v1") == true,
        let key = headers["sec-websocket-key"]
      else { return false }
      let response =
        "HTTP/1.1 101 Switching Protocols\r\n"
        + "Upgrade: websocket\r\n"
        + "Connection: Upgrade\r\n"
        + "Sec-WebSocket-Accept: \(Self.acceptValue(for: key))\r\n"
        + "Sec-WebSocket-Protocol: parental-control.v1\r\n\r\n"
      connection.send(content: Data(response.utf8), completion: .idempotent)
      return true
    case .client:
      let headers = Self.parseHeaders(headerBlock)
      guard
        headerBlock.hasPrefix("HTTP/1.1 101 "),
        headers["upgrade"]?.lowercased() == "websocket",
        headers["sec-websocket-protocol"] == "parental-control.v1",
        let key = clientHandshakeKey,
        headers["sec-websocket-accept"] == Self.acceptValue(for: key)
      else { return false }
      return true
    }
  }

  private func nextFrame() throws -> (opcode: UInt8, payload: Data)?? {
    guard receiveBuffer.count >= 2 else { return nil }
    let first = receiveBuffer[receiveBuffer.startIndex]
    let second = receiveBuffer[receiveBuffer.index(after: receiveBuffer.startIndex)]
    guard first & 0x80 != 0, first & 0x70 == 0 else { throw SecureWebSocketError.protocolViolation }
    let opcode = first & 0x0F
    let masked = second & 0x80 != 0
    let expectsMask: Bool
    if case .server = role { expectsMask = true } else { expectsMask = false }
    guard masked == expectsMask else { throw SecureWebSocketError.protocolViolation }

    var offset = 2
    var payloadLength = Int(second & 0x7F)
    if payloadLength == 126 {
      guard receiveBuffer.count >= offset + 2 else { return nil }
      payloadLength = Int(receiveBuffer[offset]) << 8 | Int(receiveBuffer[offset + 1])
      offset += 2
    } else if payloadLength == 127 {
      guard receiveBuffer.count >= offset + 8 else { return nil }
      var length: UInt64 = 0
      for byte in receiveBuffer[offset..<(offset + 8)] { length = (length << 8) | UInt64(byte) }
      guard length <= UInt64(ProtocolCodec.maximumMessageBytes) else {
        throw SecureWebSocketError.oversizedMessage
      }
      payloadLength = Int(length)
      offset += 8
    }
    guard payloadLength <= ProtocolCodec.maximumMessageBytes else {
      throw SecureWebSocketError.oversizedMessage
    }
    let maskLength = masked ? 4 : 0
    guard receiveBuffer.count >= offset + maskLength + payloadLength else { return nil }
    let mask = masked ? Array(receiveBuffer[offset..<(offset + 4)]) : []
    offset += maskLength
    var payload = Data(receiveBuffer[offset..<(offset + payloadLength)])
    if masked {
      for index in payload.indices { payload[index] ^= mask[index % 4] }
    }
    receiveBuffer.removeSubrange(..<(offset + payloadLength))
    return (opcode, payload)
  }

  private func sendFrame(
    opcode: UInt8,
    payload: Data,
    completion: (@Sendable (Error?) -> Void)?
  ) {
    let shouldMask: Bool
    if case .client = role { shouldMask = true } else { shouldMask = false }
    var frame = Data([0x80 | opcode])
    let maskBit: UInt8 = shouldMask ? 0x80 : 0
    if payload.count < 126 {
      frame.append(maskBit | UInt8(payload.count))
    } else if payload.count <= Int(UInt16.max) {
      frame.append(maskBit | 126)
      frame.append(UInt8((payload.count >> 8) & 0xFF))
      frame.append(UInt8(payload.count & 0xFF))
    } else {
      frame.append(maskBit | 127)
      let length = UInt64(payload.count)
      for shift in stride(from: 56, through: 0, by: -8) {
        frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
      }
    }
    if shouldMask {
      var mask = Data(count: 4)
      guard
        mask.withUnsafeMutableBytes({
          SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }) == errSecSuccess
      else {
        completion?(SecureWebSocketError.protocolViolation)
        return
      }
      frame.append(mask)
      for (index, byte) in payload.enumerated() { frame.append(byte ^ mask[index % 4]) }
    } else {
      frame.append(payload)
    }
    connection.send(content: frame, completion: .contentProcessed { completion?($0) })
  }

  private static func parseHeaders(_ block: String) -> [String: String] {
    var result: [String: String] = [:]
    for line in block.components(separatedBy: "\r\n").dropFirst() {
      guard let separator = line.firstIndex(of: ":") else { continue }
      let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      result[name] = value
    }
    return result
  }

  private static func acceptValue(for key: String) -> String {
    let magic = Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)
    return Data(Insecure.SHA1.hash(data: magic)).base64EncodedString()
  }

  private var isClosed: Bool {
    lock.lock()
    defer { lock.unlock() }
    return closed
  }
}

public final class SecureWebSocketServer: @unchecked Sendable {
  public static let serviceType = "_parental-control._tcp"
  // Pairing persists this LAN port. Keeping it stable lets already-paired endpoints reconnect
  // after the parent controller or hub restarts without weakening certificate pinning.
  public static let parentControlPort: UInt16 = 49_171

  private let listener: NWListener
  private let queue = DispatchQueue(label: "parental-control.hub.websocket")
  private let lock = NSLock()
  private var peers: [UUID: SecureWebSocketPeer] = [:]

  public var onReady: (@Sendable (UInt16) -> Void)?
  public var onPeer: (@Sendable (SecureWebSocketPeer) -> Void)?
  public var onFailure: (@Sendable (Error) -> Void)?

  public init(
    identity: TLSCertificateIdentity,
    port: UInt16 = 0,
    advertiseBonjour: Bool = true
  ) throws {
    listener = try NWListener(
      using: SecureWebSocketParameters.server(identity: identity),
      on: NWEndpoint.Port(rawValue: port) ?? .any)
    if advertiseBonjour {
      listener.service = NWListener.Service(
        name: "Parental Control Hub", type: Self.serviceType,
        txtRecord: NWTXTRecord(["protocol": "1.0"]))
    }
  }

  public func start() {
    listener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        if let port = listener.port { onReady?(port.rawValue) }
      case .failed(let error):
        onFailure?(SecureWebSocketError.listenerFailed(error.localizedDescription))
      default: break
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else {
        connection.cancel()
        return
      }
      let peer = SecureWebSocketPeer(
        connection: connection, role: .server,
        label: "parental-control.hub.peer.\(UUID().uuidString)")
      lock.lock()
      peers[peer.id] = peer
      lock.unlock()
      peer.onState = { [weak self, weak peer] state in
        guard let self, let peer else { return }
        if case .cancelled = state { remove(peer.id) }
        if case .failed = state { remove(peer.id) }
      }
      onPeer?(peer)
      peer.start()
    }
    listener.start(queue: queue)
  }

  public func cancel() {
    listener.cancel()
    lock.lock()
    let current = Array(peers.values)
    peers.removeAll()
    lock.unlock()
    for peer in current { peer.cancel() }
  }

  private func remove(_ id: UUID) {
    lock.lock()
    peers.removeValue(forKey: id)
    lock.unlock()
  }
}

public enum SecureWebSocketClient {
  public static func connect(
    host: String,
    port: UInt16,
    certificateFingerprint: String
  ) throws -> SecureWebSocketPeer {
    let parameters = try SecureWebSocketParameters.client(
      certificateFingerprint: certificateFingerprint)
    guard let networkPort = NWEndpoint.Port(rawValue: port) else {
      throw SecureWebSocketError.connectionFailed("invalid port")
    }
    let connection = NWConnection(host: NWEndpoint.Host(host), port: networkPort, using: parameters)
    return SecureWebSocketPeer(
      connection: connection, role: .client(host: host),
      label: "parental-control.mock.websocket")
  }
}

private enum SecureWebSocketParameters {
  static func server(identity: TLSCertificateIdentity) -> NWParameters {
    let tls = NWProtocolTLS.Options()
    sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
    sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
    sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, false)
    guard let localIdentity = sec_identity_create(identity.identity) else {
      preconditionFailure("SecIdentity could not be bridged to the TLS stack")
    }
    sec_protocol_options_set_local_identity(tls.securityProtocolOptions, localIdentity)
    return parameters(tls: tls)
  }

  static func client(certificateFingerprint: String) throws -> NWParameters {
    let normalized = certificateFingerprint.replacingOccurrences(of: ":", with: "").uppercased()
    guard normalized.count == SHA256.byteCount * 2 else {
      throw SecureWebSocketError.invalidCertificateFingerprint
    }
    let tls = NWProtocolTLS.Options()
    sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
    sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
    sec_protocol_options_set_peer_authentication_required(tls.securityProtocolOptions, true)
    sec_protocol_options_set_verify_block(
      tls.securityProtocolOptions,
      { _, trust, complete in
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard
          let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
          let certificate = chain.first
        else {
          complete(false)
          return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        let actual = digest.map { String(format: "%02X", $0) }.joined()
        complete(actual == normalized)
      },
      DispatchQueue(label: "parental-control.tls.pin-verification")
    )
    return parameters(tls: tls)
  }

  private static func parameters(tls: NWProtocolTLS.Options) -> NWParameters {
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    let parameters = NWParameters(tls: tls, tcp: tcp)
    parameters.includePeerToPeer = true
    return parameters
  }
}
