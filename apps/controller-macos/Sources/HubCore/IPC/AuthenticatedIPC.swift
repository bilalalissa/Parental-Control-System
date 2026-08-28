import CryptoKit
import Foundation
import Network

public enum IPCCommand: String, Codable, Sendable {
  case status
  case createPairing
  case revoke
  case unpair
  case sendChat
  case editChat
  case deleteChat
  case configureActivity
  case configureBrowser
  case markChatRead
  case acknowledgeTimeRequest
  case applyPolicy
  case sendAction
  case rotateAdultVerifier
  case shutdown
}

public struct IPCRequest: Codable, Equatable, Sendable {
  public let id: UUID
  public let sentAt: Date
  public let nonce: String
  public let command: IPCCommand
  public let deviceID: String?
  public let payload: [String: JSONValue]
  public let authentication: String

  public init(
    id: UUID = UUID(),
    sentAt: Date = Date(),
    nonce: String = UUID().uuidString,
    command: IPCCommand, deviceID: String? = nil, payload: [String: JSONValue] = [:],
    authentication: String
  ) {
    self.id = id
    self.sentAt = sentAt
    self.nonce = nonce
    self.command = command
    self.deviceID = deviceID
    self.payload = payload
    self.authentication = authentication
  }
}

public struct IPCResponse: Codable, Equatable, Sendable {
  public let requestID: UUID
  public let sentAt: Date
  public let status: LocalHubStatus?
  public let error: String?
  public let authentication: String

  public init(
    requestID: UUID,
    sentAt: Date = Date(),
    status: LocalHubStatus?,
    error: String?,
    authentication: String
  ) {
    self.requestID = requestID
    self.sentAt = sentAt
    self.status = status
    self.error = error
    self.authentication = authentication
  }
}

public enum AuthenticatedIPCError: Error, Equatable, CustomStringConvertible {
  case invalidAuthentication
  case replay
  case expired
  case oversizedMessage
  case timeout
  case malformedResponse
  case remote(String)

  public var description: String {
    switch self {
    case .invalidAuthentication: "Local IPC authentication failed"
    case .replay: "Local IPC request was replayed"
    case .expired: "Local IPC request timestamp expired"
    case .oversizedMessage: "Local IPC message exceeded 64 KiB"
    case .timeout: "The local hub did not respond in time"
    case .malformedResponse: "The local hub returned an invalid response"
    case .remote(let detail): detail
    }
  }
}

public final class IPCAuthenticator: @unchecked Sendable {
  public static let maximumRememberedNonces = 256

  private let key: SymmetricKey
  private let lock = NSLock()
  private var nonceOrder: [String] = []
  private var nonces: Set<String> = []

  public init(key: Data) {
    self.key = SymmetricKey(data: key)
  }

  public func request(
    command: IPCCommand, deviceID: String? = nil, payload: [String: JSONValue] = [:],
    now: Date = Date()
  ) throws
    -> IPCRequest
  {
    let request = IPCRequest(
      sentAt: now, command: command, deviceID: deviceID, payload: payload, authentication: "")
    return IPCRequest(
      id: request.id,
      sentAt: request.sentAt,
      nonce: request.nonce,
      command: request.command,
      deviceID: request.deviceID,
      payload: request.payload,
      authentication: authenticate(requestSigningData(request)))
  }

  public func verify(_ request: IPCRequest, now: Date = Date()) throws {
    guard abs(request.sentAt.timeIntervalSince(now)) <= 30 else {
      throw AuthenticatedIPCError.expired
    }
    guard
      constantTimeEqual(
        authenticate(requestSigningData(request)), request.authentication)
    else { throw AuthenticatedIPCError.invalidAuthentication }
    lock.lock()
    defer { lock.unlock() }
    guard !nonces.contains(request.nonce) else { throw AuthenticatedIPCError.replay }
    nonces.insert(request.nonce)
    nonceOrder.append(request.nonce)
    if nonceOrder.count > Self.maximumRememberedNonces {
      let removalCount = nonceOrder.count - Self.maximumRememberedNonces
      let removed = Array(nonceOrder.prefix(removalCount))
      nonceOrder.removeFirst(removalCount)
      nonces.subtract(removed)
    }
  }

  public func response(
    requestID: UUID,
    status: LocalHubStatus?,
    error: String?,
    now: Date = Date()
  ) throws -> IPCResponse {
    let response = IPCResponse(
      requestID: requestID, sentAt: now, status: status, error: error, authentication: "")
    return IPCResponse(
      requestID: requestID,
      sentAt: now,
      status: status,
      error: error,
      authentication: authenticate(responseSigningData(response)))
  }

  public func verify(_ response: IPCResponse, requestID: UUID, now: Date = Date()) throws {
    guard response.requestID == requestID else { throw AuthenticatedIPCError.malformedResponse }
    guard abs(response.sentAt.timeIntervalSince(now)) <= 30 else {
      throw AuthenticatedIPCError.expired
    }
    guard
      constantTimeEqual(
        authenticate(responseSigningData(response)), response.authentication)
    else { throw AuthenticatedIPCError.invalidAuthentication }
    if let error = response.error { throw AuthenticatedIPCError.remote(error) }
  }

  private func requestSigningData(_ request: IPCRequest) -> Data {
    let device = request.deviceID ?? ""
    let payloadData = (try? ProtocolCodec.encoder().encode(request.payload)) ?? Data()
    let payloadDigest = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()
    return Data(
      "request|\(request.id.uuidString)|\(milliseconds(request.sentAt))|\(request.nonce)|\(request.command.rawValue)|\(device)|\(payloadDigest)"
        .utf8)
  }

  private func responseSigningData(_ response: IPCResponse) -> Data {
    let statusData = (try? IPCCodec.encoder().encode(response.status)) ?? Data()
    let statusDigest = SHA256.hash(data: statusData).map { String(format: "%02x", $0) }.joined()
    return Data(
      "response|\(response.requestID.uuidString)|\(milliseconds(response.sentAt))|\(statusDigest)|\(response.error ?? "")"
        .utf8)
  }

  private func authenticate(_ data: Data) -> String {
    Data(HMAC<SHA256>.authenticationCode(for: data, using: key)).base64EncodedString()
  }

  private func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private func constantTimeEqual(_ expected: String, _ actual: String) -> Bool {
    let lhs = Array(expected.utf8)
    let rhs = Array(actual.utf8)
    var difference = lhs.count ^ rhs.count
    for index in 0..<max(lhs.count, rhs.count) {
      difference |= Int((index < lhs.count ? lhs[index] : 0) ^ (index < rhs.count ? rhs[index] : 0))
    }
    return difference == 0
  }
}

public enum IPCCodec {
  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }
}

public final class AuthenticatedIPCServer: @unchecked Sendable {
  private let listener: NWListener
  private let authenticator: IPCAuthenticator
  private let handler: @Sendable (IPCRequest) throws -> LocalHubStatus?
  private let queue = DispatchQueue(label: "parental-control.hub.ipc")

  public var onReady: (@Sendable (UInt16) -> Void)?
  public var onFailure: (@Sendable (Error) -> Void)?

  public init(
    key: Data,
    handler: @escaping @Sendable (IPCRequest) throws -> LocalHubStatus?
  ) throws {
    authenticator = IPCAuthenticator(key: key)
    self.handler = handler
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
  }

  public func start() {
    listener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      switch state {
      case .ready:
        if let port = listener.port { onReady?(port.rawValue) }
      case .failed(let error): onFailure?(error)
      default: break
      }
    }
    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    listener.start(queue: queue)
  }

  public func cancel() { listener.cancel() }

  private func accept(_ connection: NWConnection) {
    connection.start(queue: queue)
    receiveLine(connection: connection, buffer: Data())
  }

  private func receiveLine(connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) {
      [weak self] data, _, complete, error in
      guard let self else { return }
      var updated = buffer
      if let data { updated.append(data) }
      if updated.count > ProtocolCodec.maximumMessageBytes {
        connection.cancel()
        return
      }
      if let newline = updated.firstIndex(of: 0x0A) {
        process(Data(updated[..<newline]), connection: connection)
      } else if error == nil, !complete {
        receiveLine(connection: connection, buffer: updated)
      } else {
        connection.cancel()
      }
    }
  }

  private func process(_ data: Data, connection: NWConnection) {
    let request: IPCRequest
    do {
      request = try IPCCodec.decoder().decode(IPCRequest.self, from: data)
      try authenticator.verify(request)
    } catch {
      connection.cancel()
      return
    }
    let status: LocalHubStatus?
    let errorText: String?
    do {
      status = try handler(request)
      errorText = nil
    } catch {
      status = nil
      errorText = String(describing: error)
    }
    guard
      let response = try? authenticator.response(
        requestID: request.id, status: status, error: errorText),
      var payload = try? IPCCodec.encoder().encode(response)
    else {
      connection.cancel()
      return
    }
    payload.append(0x0A)
    connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
  }
}

public enum AuthenticatedIPCClient {
  public static func send(
    command: IPCCommand,
    deviceID: String? = nil,
    payload: [String: JSONValue] = [:],
    port: UInt16,
    key: Data,
    timeout: TimeInterval = 3
  ) throws -> LocalHubStatus? {
    let authenticator = IPCAuthenticator(key: key)
    let request = try authenticator.request(command: command, deviceID: deviceID, payload: payload)
    var encodedRequest = try IPCCodec.encoder().encode(request)
    encodedRequest.append(0x0A)
    let payload = encodedRequest
    guard let networkPort = NWEndpoint.Port(rawValue: port) else {
      throw AuthenticatedIPCError.malformedResponse
    }
    let connection = NWConnection(host: "127.0.0.1", port: networkPort, using: .tcp)
    let queue = DispatchQueue(label: "parental-control.controller.ipc")
    let result = IPCResultBox()
    let signal = DispatchSemaphore(value: 0)
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready:
        connection.send(
          content: payload,
          completion: .contentProcessed { error in
            if let error {
              result.set(.failure(error))
              signal.signal()
            } else {
              receiveResponse(
                connection: connection, buffer: Data(), request: request,
                authenticator: authenticator, result: result, signal: signal)
            }
          })
      case .failed(let error):
        result.set(.failure(error))
        signal.signal()
      default: break
      }
    }
    connection.start(queue: queue)
    guard signal.wait(timeout: .now() + timeout) == .success else {
      connection.cancel()
      throw AuthenticatedIPCError.timeout
    }
    connection.cancel()
    return try result.get().get()
  }

  private static func receiveResponse(
    connection: NWConnection,
    buffer: Data,
    request: IPCRequest,
    authenticator: IPCAuthenticator,
    result: IPCResultBox,
    signal: DispatchSemaphore
  ) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) {
      data, _, complete, error in
      var updated = buffer
      if let data { updated.append(data) }
      if updated.count > ProtocolCodec.maximumMessageBytes {
        result.set(.failure(AuthenticatedIPCError.oversizedMessage))
        signal.signal()
      } else if let newline = updated.firstIndex(of: 0x0A) {
        do {
          let response = try IPCCodec.decoder().decode(
            IPCResponse.self, from: Data(updated[..<newline]))
          try authenticator.verify(response, requestID: request.id)
          result.set(.success(response.status))
        } catch {
          result.set(.failure(error))
        }
        signal.signal()
      } else if error == nil, !complete {
        receiveResponse(
          connection: connection, buffer: updated, request: request,
          authenticator: authenticator, result: result, signal: signal)
      } else {
        result.set(.failure(error ?? AuthenticatedIPCError.malformedResponse))
        signal.signal()
      }
    }
  }
}

private final class IPCResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Result<LocalHubStatus?, Error>?

  func set(_ result: Result<LocalHubStatus?, Error>) {
    lock.lock()
    if value == nil { value = result }
    lock.unlock()
  }

  func get() -> Result<LocalHubStatus?, Error> {
    lock.lock()
    defer { lock.unlock() }
    return value ?? .failure(AuthenticatedIPCError.malformedResponse)
  }
}
