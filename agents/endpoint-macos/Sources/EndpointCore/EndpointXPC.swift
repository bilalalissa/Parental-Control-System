import CoreFoundation
@preconcurrency import Foundation
import HubCore
import Security

public enum EndpointMachService {
  public static let name = "com.bilalalissa.ParentalControlAgent.xpc"
  public static let clientOptions: NSXPCConnection.Options = .privileged
  public static let childIdentifier = "com.bilalalissa.ParentalControlChild"
  public static let helperIdentifier = "com.bilalalissa.ParentalControlAgent.user"
  public static let controlIdentifier = "com.bilalalissa.ParentalControlAgent.ctl"
  public static let browserHostIdentifier = "com.bilalalissa.ParentalControlBrowserHost"
}

public enum EndpointPolicyWake {
  public static let name = "com.bilalalissa.ParentalControlAgent.policy-events"

  public static func post() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(name as CFString),
      nil,
      nil,
      true)
  }
}

@objc public protocol EndpointXPCProtocol {
  func status(withReply reply: @escaping (Data?, String?) -> Void)
  func dashboard(withReply reply: @escaping (Data?, String?) -> Void)
  func updateSession(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void)
  func updateActivity(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void)
  func browserConfiguration(withReply reply: @escaping (Data?, String?) -> Void)
  func updateBrowser(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void)
  func sendChat(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void)
  func markChatRead(withReply reply: @escaping (Bool, String?) -> Void)
  func requestMoreTime(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void)
  func submitAdultCode(_ payload: Data, withReply reply: @escaping (Data?, String?) -> Void)
  func claimPolicyEvents(withReply reply: @escaping (Data?, String?) -> Void)
}

public enum XPCAuthorization {
  public static func allows(uid: uid_t, signingIdentifier: String?, operation: String) -> Bool {
    guard
      [
        "status", "dashboard", "session-update", "activity-update", "browser-configuration",
        "browser-update", "send-chat", "mark-chat-read", "time-request", "adult-code",
        "policy-events",
      ]
      .contains(operation)
    else { return false }
    guard uid != 0, let signingIdentifier else { return false }
    if operation == "status" || operation == "dashboard" {
      return signingIdentifier == EndpointMachService.childIdentifier
        || signingIdentifier == EndpointMachService.helperIdentifier
        || signingIdentifier == EndpointMachService.controlIdentifier
    }
    if operation == "session-update" || operation == "activity-update" {
      return signingIdentifier == EndpointMachService.helperIdentifier
    }
    if operation == "policy-events" {
      return signingIdentifier == EndpointMachService.helperIdentifier
    }
    if operation == "browser-configuration" || operation == "browser-update" {
      return signingIdentifier == EndpointMachService.browserHostIdentifier
    }
    return signingIdentifier == EndpointMachService.childIdentifier
  }

  public static func isRecognizedClient(_ signingIdentifier: String?) -> Bool {
    guard let signingIdentifier else { return false }
    return [
      EndpointMachService.childIdentifier, EndpointMachService.helperIdentifier,
      EndpointMachService.controlIdentifier, EndpointMachService.browserHostIdentifier,
    ].contains(signingIdentifier)
  }

  public static func signingIdentifier(pid: pid_t) -> String? {
    guard let (staticCode, executablePath) = staticCode(pid: pid) else { return nil }
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

  public static func diagnostic(pid: pid_t) -> String {
    var dynamicCode: SecCode?
    let guestStatus = SecCodeCopyGuestWithAttributes(
      nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, [],
      &dynamicCode)
    guard guestStatus == errSecSuccess, let dynamicCode else {
      return "guest-code=\(guestStatus)"
    }
    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(dynamicCode, [], &staticCode)
    guard staticStatus == errSecSuccess, let staticCode else {
      return "guest-code=\(guestStatus) static-code=\(staticStatus)"
    }
    var path: CFURL?
    let pathStatus = SecCodeCopyPath(staticCode, [], &path)
    guard pathStatus == errSecSuccess, let executablePath = (path as URL?)?.path else {
      return
        "guest-code=\(guestStatus) static-code=\(staticStatus) code-path=\(pathStatus)"
    }
    let validityStatus = SecStaticCodeCheckValidity(
      staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil)
    var information: CFDictionary?
    let informationStatus = SecCodeCopySigningInformation(
      staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
    let identifier = (information as? [CFString: Any])?[kSecCodeInfoIdentifier] as? String
    let expected =
      identifier.map { isExpectedInstalledPath(executablePath, identifier: $0) } ?? false
    return
      "guest-code=\(guestStatus) static-code=\(staticStatus) code-path=\(pathStatus) path=\(executablePath) code-valid=\(validityStatus) signing-info=\(informationStatus) identifier=\(identifier ?? "none") expected-path=\(expected) root-protected=\(isRootProtected(executablePath))"
  }

  private static func staticCode(pid: pid_t) -> (SecStaticCode, String)? {
    var dynamicCode: SecCode?
    guard
      SecCodeCopyGuestWithAttributes(
        nil, [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary, [],
        &dynamicCode) == errSecSuccess,
      let dynamicCode
    else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess, let staticCode
    else {
      return nil
    }
    var path: CFURL?
    guard SecCodeCopyPath(staticCode, [], &path) == errSecSuccess,
      let executablePath = (path as URL?)?.path
    else { return nil }
    return (staticCode, executablePath)
  }

  public static func isExpectedInstalledPath(_ path: String, identifier: String) -> Bool {
    let expected: [String]
    switch identifier {
    case EndpointMachService.childIdentifier:
      expected = [
        "/Applications/Parental Control Child.app",
        "/Applications/Parental Control Child.app/Contents/MacOS/ParentalControlChild",
      ]
    case EndpointMachService.helperIdentifier:
      expected = [
        "/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlAgentUser"
      ]
    case EndpointMachService.controlIdentifier:
      expected = ["/usr/local/bin/parental-control-agentctl"]
    case EndpointMachService.browserHostIdentifier:
      expected = [
        "/Applications/Parental Control Child.app/Contents/Helpers/ParentalControlBrowserHost"
      ]
    default: expected = []
    }
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    return expected.contains(resolved)
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
  private var messages: [EndpointChatMessage] = []
  private var outbound: [EndpointOutboundItem] = []
  private var latestTimeRequest: EndpointTimeRequest?
  private let persistenceURL: URL?
  public init(initial: EndpointStatus, persistenceURL: URL? = nil) {
    value = initial
    self.persistenceURL = persistenceURL
    if let persistenceURL,
      let data = try? Data(contentsOf: persistenceURL),
      let persisted = try? JSONDecoder.endpoint.decode(EndpointRuntimeState.self, from: data)
    {
      messages = Array(persisted.messages.suffix(200))
      outbound = Array(persisted.outbound.suffix(100))
      latestTimeRequest = persisted.latestTimeRequest
    }
  }
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
  @discardableResult
  public func applySession(_ update: SessionUpdate) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let becameActive = update.state == .active && value.sessionState != .active
    value.sessionState = update.state
    value.consoleUser = update.consoleUser.map { String($0.prefix(128)) }
    value.helperHealthy = true
    value.collectedAt = Date()
    helperLastSeen = Date()
    return becameActive
  }

  public func applyActivity(_ update: EndpointActivityUpdate) {
    lock.lock()
    defer { lock.unlock() }
    helperLastSeen = Date()
    value.helperHealthy = true
    guard value.activityCollectionEnabled else {
      value.applications = []
      return
    }
    var current = Dictionary(
      uniqueKeysWithValues: value.applications.map { ($0.bundleIdentifier, $0) })
    for application in update.applications.prefix(64) {
      current[application.bundleIdentifier] = application
    }
    value.applications = current.values.sorted {
      if $0.isForeground != $1.isForeground { return $0.isForeground }
      return $0.observedAt > $1.observedAt
    }.prefix(64).map { $0 }
    value.collectedAt = update.observedAt
  }

  public func applyBrowser(_ update: EndpointBrowserUpdate) {
    lock.lock()
    defer { lock.unlock() }
    guard value.browserCollectionEnabled else {
      value.browserTabs = []
      return
    }
    value.browserTabs.removeAll {
      $0.browser == update.browser && $0.profileID == update.profileID
    }
    value.browserTabs.append(contentsOf: update.tabs.prefix(128))
    value.browserTabs = Array(value.browserTabs.suffix(128))
    value.collectedAt = update.observedAt
  }

  public func configureActivity(enabled: Bool, retentionDays: Int) {
    lock.lock()
    defer { lock.unlock() }
    value.activityCollectionEnabled = enabled
    value.activityRetentionDays = max(1, min(retentionDays, 30))
    if !enabled { value.applications = [] }
  }

  public func configureBrowser(enabled: Bool, retentionDays: Int) {
    lock.lock()
    defer { lock.unlock() }
    value.browserCollectionEnabled = enabled
    value.browserRetentionDays = max(1, min(retentionDays, 30))
    if !enabled { value.browserTabs = [] }
  }

  public func receiveChat(_ message: EndpointChatMessage) {
    lock.lock()
    defer { lock.unlock() }
    guard !messages.contains(where: { $0.id == message.id }) else { return }
    messages.append(message)
    if messages.count > 200 { messages.removeFirst(messages.count - 200) }
    persistLocked()
  }

  @discardableResult
  public func applyParentChatMutation(
    id: UUID, action: String, text: String?, mutatedAt: Date
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let index = messages.firstIndex(where: { $0.id == id && $0.isFromParent }),
      messages[index].deletedAt == nil
    else { return false }
    switch action {
    case "edit":
      guard let text else { return false }
      let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
      guard !trimmed.isEmpty else { return false }
      messages[index].text = trimmed
      messages[index].editedAt = mutatedAt
    case "delete":
      messages[index].text = ""
      messages[index].deletedAt = mutatedAt
    default:
      return false
    }
    persistLocked()
    return true
  }

  public func dashboard(markRead: Bool = false) -> EndpointDashboardSnapshot {
    lock.lock()
    defer { lock.unlock() }
    if markRead {
      for index in messages.indices
      where messages[index].isFromParent && messages[index].state != .read {
        messages[index].state = .read
        outbound.append(
          EndpointOutboundItem(
            kind: .receipt,
            payload: [
              "originalMessageId": .string(messages[index].id.uuidString),
              "state": .string(ChatDeliveryState.read.rawValue),
            ]))
      }
      trimOutbound()
      persistLocked()
    }
    var current = value
    current.helperHealthy = helperLastSeen.map { Date().timeIntervalSince($0) <= 90 } ?? false
    return EndpointDashboardSnapshot(
      status: current, messages: messages, latestTimeRequest: latestTimeRequest)
  }

  @discardableResult
  public func markParentMessagesRead() -> Int {
    lock.lock()
    defer { lock.unlock() }
    var count = 0
    for index in messages.indices
    where messages[index].isFromParent && messages[index].state != .read {
      messages[index].state = .read
      outbound.append(
        EndpointOutboundItem(
          kind: .receipt,
          payload: [
            "originalMessageId": .string(messages[index].id.uuidString),
            "state": .string(ChatDeliveryState.read.rawValue),
          ]))
      count += 1
    }
    trimOutbound()
    if count > 0 { persistLocked() }
    return count
  }

  public func queueChat(text: String, audience: ChatAudience, threadID: UUID) {
    lock.lock()
    defer { lock.unlock() }
    let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
    guard !trimmed.isEmpty else { return }
    let id = UUID()
    messages.append(
      EndpointChatMessage(
        id: id, threadID: threadID, sender: "Child", text: trimmed, audience: audience,
        state: .queued, isFromParent: false))
    outbound.append(
      EndpointOutboundItem(
        id: id, kind: .chat,
        payload: [
          "text": .string(trimmed), "sender": .string("Child"),
          "audience": .string(audience.rawValue), "threadId": .string(threadID.uuidString),
        ]))
    if messages.count > 200 { messages.removeFirst(messages.count - 200) }
    trimOutbound()
    persistLocked()
  }

  @discardableResult
  public func queueMoreTime(minutes: Int, note: String) -> UUID {
    lock.lock()
    defer { lock.unlock() }
    let request = EndpointTimeRequest(requestedMinutes: minutes, note: note)
    latestTimeRequest = request
    outbound.append(
      EndpointOutboundItem(
        id: request.id,
        kind: .requestMoreTime,
        payload: [
          "minutes": .integer(Int64(max(5, min(minutes, 240)))),
          "note": .string(String(note.prefix(500))),
        ]))
    trimOutbound()
    persistLocked()
    return request.id
  }

  @discardableResult
  public func resolveMoreTime(
    id: UUID, state: EndpointTimeRequestState, minutes: Int, resolvedAt: Date = Date()
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if latestTimeRequest == nil || latestTimeRequest?.state != .pending {
      latestTimeRequest = EndpointTimeRequest(
        id: id, requestedMinutes: minutes, note: "", createdAt: resolvedAt, state: state,
        resolvedAt: resolvedAt)
      persistLocked()
      return true
    }
    guard latestTimeRequest?.id == id else { return false }
    latestTimeRequest?.state = state
    latestTimeRequest?.resolvedAt = resolvedAt
    persistLocked()
    return true
  }

  public func drainOutbound() -> [EndpointOutboundItem] {
    lock.lock()
    defer { lock.unlock() }
    let items = outbound
    outbound.removeAll(keepingCapacity: true)
    persistLocked()
    return items
  }

  public func requeue(_ items: [EndpointOutboundItem]) {
    lock.lock()
    defer { lock.unlock() }
    outbound.insert(contentsOf: items, at: 0)
    trimOutbound()
    persistLocked()
  }

  public func markSent(_ id: UUID) {
    lock.lock()
    defer { lock.unlock() }
    if let index = messages.firstIndex(where: { $0.id == id }) {
      messages[index].state = messages[index].state.advanced(to: .sent)
      persistLocked()
    }
  }

  public func updateMessageState(_ id: UUID, state: ChatDeliveryState) {
    lock.lock()
    defer { lock.unlock() }
    if let index = messages.firstIndex(where: { $0.id == id }) {
      messages[index].state = messages[index].state.advanced(to: state)
      persistLocked()
    }
  }

  private func trimOutbound() {
    if outbound.count > 100 { outbound.removeFirst(outbound.count - 100) }
  }

  private func persistLocked() {
    guard let persistenceURL else { return }
    do {
      let directory = persistenceURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try JSONEncoder.endpoint.encode(
        EndpointRuntimeState(
          messages: messages, outbound: outbound, latestTimeRequest: latestTimeRequest)
      ).write(to: persistenceURL, options: [.atomic])
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: persistenceURL.path)
    } catch {}
  }
}

private final class EndpointXPCObject: NSObject, EndpointXPCProtocol, @unchecked Sendable {
  let repository: EndpointStatusRepository
  let policyRuntime: EndpointPolicyRuntime?
  let uid: uid_t
  let identifier: String
  init(
    repository: EndpointStatusRepository, policyRuntime: EndpointPolicyRuntime?, uid: uid_t,
    identifier: String
  ) {
    self.repository = repository
    self.policyRuntime = policyRuntime
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

  func dashboard(withReply reply: @escaping (Data?, String?) -> Void) {
    guard XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "dashboard")
    else {
      reply(nil, "unauthorized")
      return
    }
    do { reply(try JSONEncoder.endpoint.encode(repository.dashboard(markRead: false)), nil) } catch
    {
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
      let becameActive = repository.applySession(update)
      if becameActive, let policyRuntime {
        policyRuntime.rearmRestrictionForActiveSession()
        let events = policyRuntime.tick(now: update.observedAt, sessionActive: true)
        if !events.isEmpty { EndpointPolicyWake.post() }
      }
      reply(true, nil)
    } catch { reply(false, "invalid update") }
  }

  func updateActivity(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void) {
    guard
      XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "activity-update")
    else {
      reply(false, "unauthorized")
      return
    }
    do {
      let update = try JSONDecoder.endpoint.decode(EndpointActivityUpdate.self, from: payload)
      guard abs(update.observedAt.timeIntervalSinceNow) <= 120 else {
        reply(false, "expired update")
        return
      }
      repository.applyActivity(update)
      reply(true, nil)
    } catch { reply(false, "invalid update") }
  }

  func browserConfiguration(withReply reply: @escaping (Data?, String?) -> Void) {
    guard
      XPCAuthorization.allows(
        uid: uid, signingIdentifier: identifier, operation: "browser-configuration")
    else {
      reply(nil, "unauthorized")
      return
    }
    let status = repository.status()
    do {
      reply(
        try JSONEncoder.endpoint.encode(
          EndpointBrowserConfiguration(
            enabled: status.browserCollectionEnabled,
            retentionDays: status.browserRetentionDays)), nil)
    } catch { reply(nil, "encoding failed") }
  }

  func updateBrowser(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void) {
    guard
      XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "browser-update")
    else {
      reply(false, "unauthorized")
      return
    }
    do {
      let update = try JSONDecoder.endpoint.decode(EndpointBrowserUpdate.self, from: payload)
      guard abs(update.observedAt.timeIntervalSinceNow) <= 120 else {
        reply(false, "expired update")
        return
      }
      repository.applyBrowser(update)
      reply(true, nil)
    } catch { reply(false, "invalid browser update") }
  }

  func sendChat(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void) {
    guard XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "send-chat")
    else {
      reply(false, "unauthorized")
      return
    }
    do {
      let request = try JSONDecoder.endpoint.decode(EndpointChatRequest.self, from: payload)
      repository.queueChat(
        text: request.text, audience: request.audience, threadID: request.threadID)
      reply(true, nil)
    } catch { reply(false, "invalid chat request") }
  }

  func markChatRead(withReply reply: @escaping (Bool, String?) -> Void) {
    guard
      XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "mark-chat-read")
    else {
      reply(false, "unauthorized")
      return
    }
    _ = repository.markParentMessagesRead()
    reply(true, nil)
  }

  func requestMoreTime(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void) {
    guard
      XPCAuthorization.allows(uid: uid, signingIdentifier: identifier, operation: "time-request")
    else {
      reply(false, "unauthorized")
      return
    }
    do {
      let request = try JSONDecoder.endpoint.decode(EndpointMoreTimeRequest.self, from: payload)
      repository.queueMoreTime(minutes: request.minutes, note: request.note)
      reply(true, nil)
    } catch { reply(false, "invalid time request") }
  }

  func submitAdultCode(_ payload: Data, withReply reply: @escaping (Data?, String?) -> Void) {
    guard
      XPCAuthorization.allows(
        uid: uid, signingIdentifier: identifier, operation: "adult-code")
    else {
      reply(nil, "unauthorized")
      return
    }
    guard let policyRuntime else {
      reply(nil, "policy unavailable")
      return
    }
    do {
      let request = try JSONDecoder.endpoint.decode(
        EndpointAdultOverrideRequest.self, from: payload)
      let until = try policyRuntime.submitAdultCode(request.code, duration: request.minutes * 60)
      reply(try JSONEncoder.endpoint.encode(until), nil)
    } catch EndpointPolicyError.adultCodeLocked {
      reply(nil, "Too many attempts. Try again in five minutes.")
    } catch {
      reply(nil, "The adult code was not accepted.")
    }
  }

  func claimPolicyEvents(withReply reply: @escaping (Data?, String?) -> Void) {
    guard
      XPCAuthorization.allows(
        uid: uid, signingIdentifier: identifier, operation: "policy-events")
    else {
      reply(nil, "unauthorized")
      return
    }
    guard let policyRuntime else {
      reply(nil, "policy unavailable")
      return
    }
    do {
      reply(try JSONEncoder.endpoint.encode(policyRuntime.claimUserEvents()), nil)
    } catch {
      reply(nil, "encoding failed")
    }
  }
}

public struct EndpointChatRequest: Codable, Equatable, Sendable {
  public let text: String
  public let audience: ChatAudience
  public let threadID: UUID
  public init(text: String, audience: ChatAudience = .direct, threadID: UUID = UUID()) {
    self.text = text
    self.audience = audience
    self.threadID = threadID
  }
}

public struct EndpointMoreTimeRequest: Codable, Equatable, Sendable {
  public let minutes: Int
  public let note: String
  public init(minutes: Int, note: String = "") {
    self.minutes = max(5, min(minutes, 240))
    self.note = String(note.prefix(500))
  }
}

public final class EndpointXPCService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
  private let listener: NSXPCListener
  private let repository: EndpointStatusRepository
  private let policyRuntime: EndpointPolicyRuntime?
  private let rejectionHandler: @Sendable (String) -> Void
  public init(
    repository: EndpointStatusRepository, policyRuntime: EndpointPolicyRuntime? = nil,
    rejectionHandler: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.repository = repository
    self.policyRuntime = policyRuntime
    self.rejectionHandler = rejectionHandler
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
    guard let identifier, XPCAuthorization.isRecognizedClient(identifier)
    else {
      rejectionHandler(
        "uid=\(uid) pid=\(connection.processIdentifier) \(XPCAuthorization.diagnostic(pid: connection.processIdentifier))"
      )
      return false
    }
    connection.exportedInterface = NSXPCInterface(with: EndpointXPCProtocol.self)
    connection.exportedObject = EndpointXPCObject(
      repository: repository, policyRuntime: policyRuntime, uid: uid, identifier: identifier)
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
  public func fetchDashboard(
    completion: @escaping @Sendable (Result<EndpointDashboardSnapshot, Error>) -> Void
  ) {
    let proxy =
      connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
      as? EndpointXPCProtocol
    proxy?.dashboard { data, error in
      do {
        if let error { throw EndpointXPCError.remote(error) }
        guard let data else { throw EndpointXPCError.malformed }
        completion(
          .success(try JSONDecoder.endpoint.decode(EndpointDashboardSnapshot.self, from: data)))
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

  public func updateActivity(
    _ update: EndpointActivityUpdate,
    completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    do {
      let data = try JSONEncoder.endpoint.encode(update)
      let proxy =
        connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
        as? EndpointXPCProtocol
      proxy?.updateActivity(data) { accepted, error in
        accepted
          ? completion(.success(()))
          : completion(.failure(EndpointXPCError.remote(error ?? "rejected")))
      }
    } catch { completion(.failure(error)) }
  }

  public func fetchBrowserConfiguration(
    completion: @escaping @Sendable (Result<EndpointBrowserConfiguration, Error>) -> Void
  ) {
    let proxy =
      connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
      as? EndpointXPCProtocol
    proxy?.browserConfiguration { data, error in
      do {
        if let error { throw EndpointXPCError.remote(error) }
        guard let data else { throw EndpointXPCError.malformed }
        completion(
          .success(try JSONDecoder.endpoint.decode(EndpointBrowserConfiguration.self, from: data)))
      } catch { completion(.failure(error)) }
    }
  }

  public func updateBrowser(
    _ update: EndpointBrowserUpdate,
    completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    do {
      let data = try JSONEncoder.endpoint.encode(update)
      let proxy =
        connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
        as? EndpointXPCProtocol
      proxy?.updateBrowser(data) { accepted, error in
        accepted
          ? completion(.success(()))
          : completion(.failure(EndpointXPCError.remote(error ?? "rejected")))
      }
    } catch { completion(.failure(error)) }
  }

  public func sendChat(
    _ request: EndpointChatRequest,
    completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    do {
      let data = try JSONEncoder.endpoint.encode(request)
      let proxy =
        connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
        as? EndpointXPCProtocol
      proxy?.sendChat(data) { accepted, error in
        accepted
          ? completion(.success(()))
          : completion(.failure(EndpointXPCError.remote(error ?? "rejected")))
      }
    } catch { completion(.failure(error)) }
  }

  public func markChatRead(
    completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    let proxy =
      connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
      as? EndpointXPCProtocol
    proxy?.markChatRead { accepted, error in
      accepted
        ? completion(.success(()))
        : completion(.failure(EndpointXPCError.remote(error ?? "rejected")))
    }
  }

  public func requestMoreTime(
    _ request: EndpointMoreTimeRequest,
    completion: @escaping @Sendable (Result<Void, Error>) -> Void
  ) {
    do {
      let data = try JSONEncoder.endpoint.encode(request)
      let proxy =
        connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
        as? EndpointXPCProtocol
      proxy?.requestMoreTime(data) { accepted, error in
        accepted
          ? completion(.success(()))
          : completion(.failure(EndpointXPCError.remote(error ?? "rejected")))
      }
    } catch { completion(.failure(error)) }
  }

  public func submitAdultCode(
    _ request: EndpointAdultOverrideRequest,
    completion: @escaping @Sendable (Result<Date, Error>) -> Void
  ) {
    do {
      let data = try JSONEncoder.endpoint.encode(request)
      let proxy =
        connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
        as? EndpointXPCProtocol
      proxy?.submitAdultCode(data) { data, error in
        do {
          if let error { throw EndpointXPCError.remote(error) }
          guard let data else { throw EndpointXPCError.malformed }
          completion(.success(try JSONDecoder.endpoint.decode(Date.self, from: data)))
        } catch { completion(.failure(error)) }
      }
    } catch { completion(.failure(error)) }
  }

  public func claimPolicyEvents(
    completion: @escaping @Sendable (Result<[EndpointPolicyEvent], Error>) -> Void
  ) {
    let proxy =
      connection.remoteObjectProxyWithErrorHandler { completion(.failure($0)) }
      as? EndpointXPCProtocol
    proxy?.claimPolicyEvents { data, error in
      do {
        if let error { throw EndpointXPCError.remote(error) }
        guard let data else { throw EndpointXPCError.malformed }
        completion(
          .success(try JSONDecoder.endpoint.decode([EndpointPolicyEvent].self, from: data)))
      } catch { completion(.failure(error)) }
    }
  }
}

public enum EndpointXPCError: Error {
  case malformed
  case remote(String)
}
