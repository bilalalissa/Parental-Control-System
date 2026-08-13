import Foundation
import Network

public struct DiscoveredLocalHub: Equatable, Sendable, Identifiable {
  public let name: String
  public let type: String
  public let domain: String

  public var id: String { "\(name).\(type).\(domain)" }

  public init(name: String, type: String, domain: String) {
    self.name = name
    self.type = type
    self.domain = domain
  }
}

public final class LocalHubBrowser: @unchecked Sendable {
  private let browser: NWBrowser
  private let queue = DispatchQueue(label: "parental-control.hub.discovery")

  public var onResults: (@Sendable ([DiscoveredLocalHub]) -> Void)?
  public var onFailure: (@Sendable (Error) -> Void)?

  public init() {
    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = true
    browser = NWBrowser(
      for: .bonjour(type: SecureWebSocketServer.serviceType, domain: nil),
      using: parameters)
  }

  public func start() {
    browser.stateUpdateHandler = { [weak self] state in
      if case .failed(let error) = state { self?.onFailure?(error) }
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      let discovered = results.compactMap { result -> DiscoveredLocalHub? in
        guard case .service(let name, let type, let domain, _) = result.endpoint else {
          return nil
        }
        return DiscoveredLocalHub(name: name, type: type, domain: domain)
      }.sorted { $0.id < $1.id }
      self?.onResults?(discovered)
    }
    browser.start(queue: queue)
  }

  public func cancel() { browser.cancel() }
}
