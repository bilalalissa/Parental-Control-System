import Foundation

public struct HubRuntimeInfo: Codable, Equatable, Sendable {
  public let processID: Int32
  public let ipcPort: UInt16
  public let hubPort: UInt16
  public let certificateFingerprint: String
  public let startedAt: Date

  public init(
    processID: Int32,
    ipcPort: UInt16,
    hubPort: UInt16,
    certificateFingerprint: String,
    startedAt: Date
  ) {
    self.processID = processID
    self.ipcPort = ipcPort
    self.hubPort = hubPort
    self.certificateFingerprint = certificateFingerprint
    self.startedAt = startedAt
  }
}

public enum HubRuntime {
  public static func defaultURL() -> URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    .appendingPathComponent("ParentalControlController", isDirectory: true)
    .appendingPathComponent("hub-runtime.json")
  }

  public static func read(from url: URL = defaultURL()) throws -> HubRuntimeInfo {
    try IPCCodec.decoder().decode(HubRuntimeInfo.self, from: Data(contentsOf: url))
  }
}
