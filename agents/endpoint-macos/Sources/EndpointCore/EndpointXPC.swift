import Darwin
@preconcurrency import Foundation
import Security

public enum EndpointMachService {
  public static let name = "com.bilalalissa.ParentalControlAgent.xpc"
  public static let clientOptions: NSXPCConnection.Options = .privileged
  public static let childIdentifier = "com.bilalalissa.ParentalControlChild"
  public static let helperIdentifier = "com.bilalalissa.ParentalControlAgent.user"
  public static let controlIdentifier = "com.bilalalissa.ParentalControlAgent.ctl"
}

@objc public protocol EndpointXPCProtocol {
  func status(withReply reply: @escaping (Data?, String?) -> Void)
  func updateSession(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void)
}

public enum XPCAuthorization {
  public static func allows(uid: uid_t, signingIdentifier: String?, operation: String) -> Bool {
    guard operation == "status" || operation == "session-update" else { return false }
    guard uid != 0, let signingIdentifier else { return false }
    if operation == "status" {
      return signingIdentifier == EndpointMachService.childIdentifier
        || signingIdentifier == EndpointMachService.helperIdentifier
        || signingIdentifier == EndpointMachService.controlIdentifier
    }
    return signingIdentifier == EndpointMachService.helperIdentifier
  }

  public static func signingIdentifier(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 16_384)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    let executablePath = String(
      decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    let path = URL(fileURLWithPath: executablePath) as CFURL
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(path, [], &staticCode) == errSecSuccess, let staticCode
    else { return nil }
    guard
      SecStaticCodeCheckValidity(
        staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
    else { return nil }
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let dictionary = information as? [CFString: Any]
    else { return nil }
    guard let identifier = dictionary[kSecCodeInfoIdentifier] as? String,
      isExpectedInstalledPath(executablePath, identifier: identifier),
      isRootProtected(executablePath)
    else { return nil }
    return identifier
  }

  public static func isExpectedInstalledPath(_ path: String, identifier: String) -> Bool {
    let expected: String?
    switch identifier {
    case EndpointMachService.childIdentifier:
      expected = "/Applications/Parental Control Child.app/Contents/MacOS/ParentalControlChild"
    case EndpointMachService.helperIdentifier:
      expected =
        "/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlAgentUser"
    case EndpointMachService.controlIdentifier:
      expected = "/usr/local/bin/parental-control-agentctl"
    default: expected = nil
    }
    guard let expected else { return false }
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().path == expected
  }

  private static func isRootProtected(_ path: String) -> Bool {
    let application = "/Applications/Parental Control Child.app"
    for item in [path, application] {
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: item),
        (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
        permissions & 0o022 == 0
      else { return false }
    }
    return true
  }
}

public final class EndpointStatusRepository: @unchecked Sendable {
  private let lock = NSLock()
  private var value: EndpointStatus
  private var helperLastSeen: Date?
  public init(initial: EndpointStatus) { value = initial }
  public func status() -> EndpointStatus {
    lock.lock()
    defer { lock.unlock() }
    var current = value
    current.helperHealthy = helperLastSeen.map { Date().timeIntervalSince($0) <= 90 } ?? false
    return current
  }
  public func update(_ transform: (inout EndpointStatus) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    transform(&value)
  }
  public func applySession(_ update: SessionUpdate) {
    lock.lock()
    defer { lock.unlock() }
    value.sessionState = update.state
    value.consoleUser = update.consoleUser.map { String($0.prefix(128)) }
    value.helperHealthy = true
    value.collectedAt = Date()
    helperLastSeen = Date()
  }
}

private final class EndpointXPCObject: NSObject, EndpointXPCProtocol, @unchecked Sendable {
  let repository: EndpointStatusRepository
  let uid: uid_t
  let identifier: String
  init(repository: EndpointStatusRepository, uid: uid_t, identifier: String) {
    self.repository = repository
    self.uid = uid
    self.identifier = identifier
  }

  func status(withReply reply: @escaping (Data?, String?) -> Void) {
    guard XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "status")
    else {
      reply(nil, "unauthorized")
      return
    }
    do { reply(try JSONEncoder.endpoint.encode(repository.status()), nil) } catch {
      reply(nil, "encoding failed")
    }
  }

  func updateSession(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void) {
    guard
      XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "session-update")
    else {
      reply(false, "unauthorized")
      return
    }
    do {
      let update = try JSONDecoder.endpoint.decode(SessionUpdate.self, from: payload)
      guard abs(update.observedAt.timeIntervalSinceNow) <= 120 else {
        reply(false, "expired update")
        return
      }
      repository.applySession(update)
      reply(true, nil)
    } catch { reply(false, "invalid update") }
  }
}

public final class EndpointXPCService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  private let listener: NSXPCListener
  private let repository: EndpointStatusRepository
  public init(repository: EndpointStatusRepository) {
    self.repository = repository
    listener = NSXPCListener(machServiceName: EndpointMachService.name)
    super.init()
    listener.delegate = self
  }
  public func resume() { listener.resume() }
  public func invalidate() { listener.invalidate() }
  public func listener(
    _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    let uid = connection.effectiveUserIdentifier
    let identifier = XPCAuthorization.signingIdentifier(pid: connection.processIdentifier)
    guard let identifier,
      XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "status")
    else { return false }
    connection.exportedInterface = NSXPCInterface(with: EndpointXPCProtocol.self)
    connection.exportedObject = EndpointXPCObject(
      repository: repository, uid: uid, identifier: identifier)
    connection.resume()
    return true
  }
}

public final class EndpointXPCClient: @unchecked Sendable {
  private let connection: NSXPCConnection
  public init() {
    connection = NSXPCConnection(
      machServiceName: EndpointMachService.name, options: EndpointMachService.clientOptions)
    connection.remoteObjectInterface = NSXPCInterface(with: EndpointXPCProtocol.self)
    connection.resume()
  }
  deinit { connection.invalidate() }
  public func fetchStatus(completion: @escaping @Sendable (Result<EndpointStatus, Error>) -> Void) {
    let proxy =
      connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
      as? EndpointXPCProtocol
    proxy?.status { data, error in
      do {
        if let error { throw EndpointXPCError.remote(error) }
        guard let data else { throw EndpointXPCError.malformed }
        completion(.success(try JSONDecoder.endpoint.decode(EndpointStatus.self, from: data)))
      } catch { completion(.failure(error)) }
    }
  }
  public func updateSession(
    _ update: SessionUpdate, completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    do {
      let data = try JSONEncoder.endpoint.encode(update)
      let proxy =
        connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
        as? EndpointXPCProtocol
      proxy?.updateSession(data) { accepted, error in
        if accepted {
          completion(.success(()))
        } else {
          completion(.failure(EndpointXPCError.remote(error ?? "rejected")))
        }
      }
    } catch { completion(.failure(error)) }
  }
}

public enum EndpointXPCError: Error {
  case malformed
  case remote(String)
}
