import Foundation
import SafariServices

private let serviceName = "com.bilalalissa.ParentalControlAgent.xpc"
private let maximumTabs = 128

@objc private protocol EndpointBrowserXPC {
  func browserConfiguration(withReply reply: @escaping (Data?, String?) -> Void)
  func updateBrowser(_ payload: Data, withReply reply: @escaping (Bool, String?) -> Void)
}

private final class CompletionGate: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false

  func once(_ work: () -> Void) {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return
    }
    completed = true
    lock.unlock()
    work()
  }
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    guard
      let item = context.inputItems.first as? NSExtensionItem,
      let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
      let type = message["type"] as? String,
      ["configuration.query", "policy.ack", "tabs.update"].contains(type)
    else {
      complete(context, ["accepted": false, "enabled": false, "error": "invalid request"])
      return
    }

    let profile = profileIdentifier(item: item, message: message)
    guard !profile.isEmpty, profile.utf8.count <= 80 else {
      complete(context, ["accepted": false, "enabled": false, "error": "invalid profile"])
      return
    }

    withConfiguration(context: context) { configuration, connection in
      switch type {
      case "configuration.query":
        var response = configuration
        response["accepted"] = true
        response["browser"] = "safari"
        self.complete(context, response, connection: connection)
      case "policy.ack":
        self.handleAcknowledgement(
          message, profile: profile, configuration: configuration,
          context: context, connection: connection)
      default:
        self.handleTabs(
          message, profile: profile, configuration: configuration,
          context: context, connection: connection)
      }
    }
  }

  private func profileIdentifier(item: NSExtensionItem, message: [String: Any]) -> String {
    if let value = item.userInfo?[SFExtensionProfileKey] as? UUID { return value.uuidString }
    if let value = item.userInfo?[SFExtensionProfileKey] as? String, !value.isEmpty { return value }
    return message["profile"] as? String ?? ""
  }

  private func withConfiguration(
    context: NSExtensionContext,
    completion: @escaping ([String: Any], NSXPCConnection) -> Void
  ) {
    let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: EndpointBrowserXPC.self)
    connection.resume()
    let gate = CompletionGate()
    let fail: @Sendable () -> Void = {
      gate.once {
        self.complete(
          context, ["accepted": false, "enabled": false, "error": "local endpoint unavailable"],
          connection: connection)
      }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: fail)
    let proxy =
      connection.remoteObjectProxyWithErrorHandler { _ in fail() }
      as? EndpointBrowserXPC
    guard let proxy else {
      fail()
      return
    }
    proxy.browserConfiguration { data, error in
      gate.once {
        guard error == nil, let data,
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
          self.complete(
            context, ["accepted": false, "enabled": false, "error": "local endpoint unavailable"],
            connection: connection)
          return
        }
        completion(value, connection)
      }
    }
  }

  private func handleAcknowledgement(
    _ message: [String: Any], profile: String, configuration: [String: Any],
    context: NSExtensionContext, connection: NSXPCConnection
  ) {
    let state = message["policyState"] as? String ?? ""
    guard ["applied", "error", "setup-required"].contains(state) else {
      complete(
        context, ["accepted": false, "enabled": false, "error": "invalid acknowledgement"],
        connection: connection)
      return
    }
    let expected = (configuration["websitePolicy"] as? [String: Any])?["version"] as? NSNumber
    let reported = message["policyVersion"] as? NSNumber
    guard
      (expected == nil && state == "setup-required") || (expected != nil && expected == reported)
    else {
      complete(
        context, ["accepted": false, "enabled": false, "error": "policy version mismatch"],
        connection: connection)
      return
    }
    let reportVersion: Any = reported?.int64Value ?? NSNull()
    sendUpdate(
      [
        "browser": "safari", "profileID": profile, "tabs": [], "observedAt": now(),
        "protectionReport": [
          "browser": "safari", "profile": profile,
          "version": reportVersion, "state": state, "observedAt": now(),
        ],
      ],
      enabled: configuration["enabled"] as? Bool == true,
      context: context, connection: connection)
  }

  private func handleTabs(
    _ message: [String: Any], profile: String, configuration: [String: Any],
    context: NSExtensionContext, connection: NSXPCConnection
  ) {
    guard configuration["enabled"] as? Bool == true,
      let rawTabs = message["tabs"] as? [[String: Any]], rawTabs.count <= maximumTabs
    else {
      complete(
        context, ["accepted": false, "enabled": false, "error": "sharing disabled"],
        connection: connection)
      return
    }
    let tabs = rawTabs.prefix(maximumTabs).compactMap { tab -> [String: Any]? in
      guard let origin = sanitizedOrigin(tab["origin"] as? String) else { return nil }
      let title = String((tab["title"] as? String ?? "Untitled").prefix(300))
      return [
        "browser": "safari", "profileID": profile, "title": title, "origin": origin,
        "isActive": tab["active"] as? Bool == true, "observedAt": now(),
      ]
    }
    sendUpdate(
      ["browser": "safari", "profileID": profile, "tabs": tabs, "observedAt": now()],
      enabled: true,
      context: context, connection: connection)
  }

  private func sendUpdate(
    _ update: [String: Any], enabled: Bool, context: NSExtensionContext,
    connection: NSXPCConnection
  ) {
    guard JSONSerialization.isValidJSONObject(update),
      let data = try? JSONSerialization.data(withJSONObject: update)
    else {
      complete(
        context, ["accepted": false, "enabled": false, "error": "invalid update"],
        connection: connection)
      return
    }
    let gate = CompletionGate()
    let fail: @Sendable () -> Void = {
      gate.once {
        self.complete(
          context, ["accepted": false, "enabled": false, "error": "local endpoint unavailable"],
          connection: connection)
      }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: fail)
    let proxy =
      connection.remoteObjectProxyWithErrorHandler { _ in fail() }
      as? EndpointBrowserXPC
    guard let proxy else {
      fail()
      return
    }
    proxy.updateBrowser(data) { accepted, error in
      gate.once {
        var response: [String: Any] = [
          "accepted": accepted, "enabled": enabled, "browser": "safari",
        ]
        if let error { response["error"] = error }
        self.complete(context, response, connection: connection)
      }
    }
  }

  private func complete(
    _ context: NSExtensionContext, _ message: [String: Any], connection: NSXPCConnection? = nil
  ) {
    connection?.invalidate()
    let item = NSExtensionItem()
    item.userInfo = [SFExtensionMessageKey: message]
    context.completeRequest(returningItems: [item], completionHandler: nil)
  }

  private func now() -> Double { Date().timeIntervalSince1970 * 1_000 }

  private func sanitizedOrigin(_ value: String?) -> String? {
    guard let value, let components = URLComponents(string: value),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = components.host?.lowercased(), !host.isEmpty
    else { return nil }
    var sanitized = URLComponents()
    sanitized.scheme = scheme
    sanitized.host = host
    sanitized.port = components.port
    return sanitized.url?.absoluteString
  }
}
