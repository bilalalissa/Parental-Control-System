import Darwin
import Foundation
import HubCore
import SystemConfiguration

public enum EndpointConnectionState: String, Codable, Sendable {
  case unpaired
  case connecting
  case online
  case offline
  case revokedOrUnavailable
}

public enum EndpointSessionState: String, Codable, Sendable {
  case active
  case inactive
  case locked
  case loggedOut
  case unknown
}

public struct NetworkMetadata: Codable, Equatable, Sendable {
  public let interface: String
  public let addresses: [String]
  public let macAddress: String?

  public init(interface: String, addresses: [String], macAddress: String?) {
    self.interface = interface
    self.addresses = addresses
    self.macAddress = macAddress
  }
}

public struct EndpointStatus: Codable, Equatable, Sendable {
  public var deviceID: String
  public var deviceName: String
  public var model: String
  public var operatingSystem: String
  public var architecture: String
  public var uptimeSeconds: UInt64
  public var bootTime: Date
  public var sessionState: EndpointSessionState
  public var consoleUser: String?
  public var connectionState: EndpointConnectionState
  public var lastControllerContact: Date?
  public var networks: [NetworkMetadata]
  public var daemonHealthy: Bool
  public var helperHealthy: Bool
  public var activityCollectionEnabled: Bool
  public var activityRetentionDays: Int
  public var applications: [EndpointApplicationActivity]
  public var collectedAt: Date

  public init(
    deviceID: String,
    deviceName: String,
    model: String,
    operatingSystem: String,
    architecture: String,
    uptimeSeconds: UInt64,
    bootTime: Date,
    sessionState: EndpointSessionState = .unknown,
    consoleUser: String? = nil,
    connectionState: EndpointConnectionState = .unpaired,
    lastControllerContact: Date? = nil,
    networks: [NetworkMetadata] = [],
    daemonHealthy: Bool = true,
    helperHealthy: Bool = false,
    activityCollectionEnabled: Bool = true,
    activityRetentionDays: Int = 7,
    applications: [EndpointApplicationActivity] = [],
    collectedAt: Date = Date()
  ) {
    self.deviceID = deviceID
    self.deviceName = deviceName
    self.model = model
    self.operatingSystem = operatingSystem
    self.architecture = architecture
    self.uptimeSeconds = uptimeSeconds
    self.bootTime = bootTime
    self.sessionState = sessionState
    self.consoleUser = consoleUser
    self.connectionState = connectionState
    self.lastControllerContact = lastControllerContact
    self.networks = networks
    self.daemonHealthy = daemonHealthy
    self.helperHealthy = helperHealthy
    self.activityCollectionEnabled = activityCollectionEnabled
    self.activityRetentionDays = max(1, min(activityRetentionDays, 30))
    self.applications = Array(applications.prefix(64))
    self.collectedAt = collectedAt
  }
}

public struct EndpointApplicationActivity: Codable, Equatable, Identifiable, Sendable {
  public var id: String { bundleIdentifier }
  public let bundleIdentifier: String
  public let applicationName: String
  public let isForeground: Bool
  public let observedAt: Date

  public init(
    bundleIdentifier: String, applicationName: String, isForeground: Bool,
    observedAt: Date = Date()
  ) {
    self.bundleIdentifier = String(bundleIdentifier.prefix(200))
    self.applicationName = String(applicationName.prefix(120))
    self.isForeground = isForeground
    self.observedAt = observedAt
  }
}

public struct EndpointActivityUpdate: Codable, Equatable, Sendable {
  public let applications: [EndpointApplicationActivity]
  public let observedAt: Date

  public init(applications: [EndpointApplicationActivity], observedAt: Date = Date()) {
    self.applications = Array(applications.prefix(64))
    self.observedAt = observedAt
  }
}

public struct EndpointChatMessage: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let threadID: UUID
  public let sentAt: Date
  public let sender: String
  public let text: String
  public let audience: ChatAudience
  public var state: ChatDeliveryState
  public let isFromParent: Bool

  public init(
    id: UUID = UUID(), threadID: UUID = UUID(), sentAt: Date = Date(), sender: String,
    text: String, audience: ChatAudience = .direct, state: ChatDeliveryState = .queued,
    isFromParent: Bool
  ) {
    self.id = id
    self.threadID = threadID
    self.sentAt = sentAt
    self.sender = String(sender.prefix(80))
    self.text = String(text.prefix(2_000))
    self.audience = audience
    self.state = state
    self.isFromParent = isFromParent
  }
}

public struct EndpointDashboardSnapshot: Codable, Equatable, Sendable {
  public let status: EndpointStatus
  public let messages: [EndpointChatMessage]

  public init(status: EndpointStatus, messages: [EndpointChatMessage]) {
    self.status = status
    self.messages = Array(messages.suffix(200))
  }
}

public enum EndpointOutboundKind: String, Codable, Sendable {
  case chat
  case requestMoreTime
  case receipt
}

public struct EndpointOutboundItem: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let kind: EndpointOutboundKind
  public let payload: [String: JSONValue]
  public let createdAt: Date

  public init(
    id: UUID = UUID(), kind: EndpointOutboundKind, payload: [String: JSONValue],
    createdAt: Date = Date()
  ) {
    self.id = id
    self.kind = kind
    self.payload = payload
    self.createdAt = createdAt
  }
}

public struct EndpointRuntimeState: Codable, Equatable, Sendable {
  public let messages: [EndpointChatMessage]
  public let outbound: [EndpointOutboundItem]

  public init(messages: [EndpointChatMessage], outbound: [EndpointOutboundItem]) {
    self.messages = Array(messages.suffix(200))
    self.outbound = Array(outbound.suffix(100))
  }
}

public struct SessionUpdate: Codable, Equatable, Sendable {
  public let state: EndpointSessionState
  public let consoleUser: String?
  public let observedAt: Date

  public init(state: EndpointSessionState, consoleUser: String?, observedAt: Date = Date()) {
    self.state = state
    self.consoleUser = consoleUser
    self.observedAt = observedAt
  }
}

public enum DeviceSnapshotCollector {
  public static func collect(deviceID: String, session: SessionUpdate? = nil) -> EndpointStatus {
    let uptime = UInt64(max(0, ProcessInfo.processInfo.systemUptime))
    return EndpointStatus(
      deviceID: deviceID,
      deviceName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
      model: sysctlString("hw.model") ?? "Unknown Mac",
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: machineArchitecture(),
      uptimeSeconds: uptime,
      bootTime: Date(timeIntervalSinceNow: -TimeInterval(uptime)),
      sessionState: session?.state ?? .unknown,
      consoleUser: session?.consoleUser,
      networks: networkMetadata())
  }

  public static func consoleUser() -> String? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let value = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
      value != "loginwindow"
    else {
      return nil
    }
    return String(value.prefix(128))
  }

  public static func networkMetadata() -> [NetworkMetadata] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return [] }
    defer { freeifaddrs(head) }
    var values: [String: (addresses: Set<String>, mac: String?)] = [:]
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let item = cursor?.pointee {
      defer { cursor = item.ifa_next }
      let name = String(cString: item.ifa_name)
      guard name != "lo0", (item.ifa_flags & UInt32(IFF_UP)) != 0, let address = item.ifa_addr
      else { continue }
      let family = Int32(address.pointee.sa_family)
      var current = values[name] ?? ([], nil)
      if family == AF_INET || family == AF_INET6 {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length =
          family == AF_INET
          ? socklen_t(MemoryLayout<sockaddr_in>.size) : socklen_t(MemoryLayout<sockaddr_in6>.size)
        if getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
          let decoded = String(
            decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
          let text = decoded.split(separator: "%", maxSplits: 1).first.map(String.init) ?? ""
          if !text.isEmpty { current.addresses.insert(text) }
        }
      } else if family == AF_LINK {
        let link = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_dl.self).pointee
        if link.sdl_alen == 6 {
          let base = withUnsafePointer(to: link.sdl_data) { pointer in
            UnsafeRawPointer(pointer).advanced(by: Int(link.sdl_nlen)).assumingMemoryBound(
              to: UInt8.self)
          }
          current.mac = (0..<6).map { String(format: "%02X", base[$0]) }.joined(separator: ":")
        }
      }
      values[name] = current
    }
    return values.sorted(by: { $0.key < $1.key }).prefix(16).map {
      NetworkMetadata(
        interface: $0.key, addresses: Array($0.value.addresses).sorted().prefix(8).map { $0 },
        macAddress: $0.value.mac)
    }
  }

  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  private static func machineArchitecture() -> String {
    var value = utsname()
    uname(&value)
    var machine = value.machine
    let capacity = MemoryLayout.size(ofValue: machine)
    return withUnsafePointer(to: &machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
        let buffer = UnsafeBufferPointer(start: $0, count: capacity)
        return String(
          decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
      }
    }
  }
}
