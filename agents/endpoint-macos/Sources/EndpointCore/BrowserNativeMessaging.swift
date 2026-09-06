import Darwin
import Foundation
import HubCore
import Security

public enum BrowserNativeMessaging {
  public static let hostName = "com.bilalalissa.parental_control"
  public static let extensionID = "pdcjgejgdjomjjemejhjhmdkcabkidmi"
  public static let allowedOrigin = "chrome-extension://\(extensionID)/"
  public static let firefoxExtensionID = "parental-control@bilalalissa.com"
  public static let maximumMessageBytes = 256 * 1_024
  public static let maximumTabs = 128
}

public struct BrowserNativeTab: Codable, Equatable, Sendable {
  public let title: String
  public let origin: String
  public let active: Bool
  public let observedAt: Date

  public init(title: String, origin: String, active: Bool, observedAt: Date = Date()) {
    self.title = String(title.prefix(300))
    self.origin = origin
    self.active = active
    self.observedAt = observedAt
  }
}

public struct BrowserNativeRequest: Codable, Equatable, Sendable {
  public let type: String
  public let browser: String
  public let profile: String
  public let tabs: [BrowserNativeTab]
  public var policyVersion: Int64?
  public var policyState: String?

  public init(type: String, browser: String, profile: String, tabs: [BrowserNativeTab]) {
    self.type = type
    self.browser = browser
    self.profile = profile
    self.tabs = Array(tabs.prefix(BrowserNativeMessaging.maximumTabs))
  }

  public func validatedUpdate(expectedBrowser: String) -> EndpointBrowserUpdate? {
    guard type == "tabs.update", browser.lowercased() == expectedBrowser.lowercased(),
      !profile.isEmpty, profile.count <= 80
    else { return nil }
    let values: [EndpointBrowserTab] = tabs.prefix(BrowserNativeMessaging.maximumTabs).compactMap {
      tab -> EndpointBrowserTab? in
      guard let origin = EndpointBrowserTab.sanitizedOrigin(tab.origin) else { return nil }
      return EndpointBrowserTab(
        browser: expectedBrowser, profileID: profile, title: tab.title, origin: origin,
        isActive: tab.active, observedAt: tab.observedAt)
    }
    return EndpointBrowserUpdate(browser: expectedBrowser, profileID: profile, tabs: values)
  }
}

public struct BrowserNativeResponse: Codable, Equatable, Sendable {
  public let accepted: Bool
  public let enabled: Bool
  public let acceptedTabs: Int
  public let error: String?
  public let browser: String?
  public let websitePolicy: BrowserWebsitePolicy?

  public init(
    accepted: Bool, enabled: Bool, acceptedTabs: Int = 0, error: String? = nil,
    browser: String? = nil, websitePolicy: BrowserWebsitePolicy? = nil
  ) {
    self.accepted = accepted
    self.enabled = enabled
    self.acceptedTabs = acceptedTabs
    self.error = error.map { String($0.prefix(160)) }
    self.browser = browser.map { String($0.lowercased().prefix(40)) }
    self.websitePolicy = websitePolicy
  }
}

public enum BrowserCallerAuthorization {
  public static func expectedBrowser(
    origin: String, executablePath: String, signingIdentifier: String?, teamIdentifier: String?,
    signatureValid: Bool
  ) -> String? {
    guard signatureValid,
      let signingIdentifier, let teamIdentifier
    else { return nil }
    let resolved = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
    if origin == BrowserNativeMessaging.firefoxExtensionID,
      isInsideApp(resolved, bundlePath: "/Applications/Firefox.app"),
      teamIdentifier == "43AQ936H96", signingIdentifier == "org.mozilla.firefox"
    {
      return "firefox"
    }
    guard origin == BrowserNativeMessaging.allowedOrigin else { return nil }
    if isInsideApp(resolved, bundlePath: "/Applications/Brave Browser.app"),
      teamIdentifier == "KL8N8XSYF4",
      signingIdentifier == "com.brave.Browser" || signingIdentifier.hasPrefix("com.brave.Browser.")
    {
      return "brave"
    }
    if isInsideApp(resolved, bundlePath: "/Applications/Google Chrome.app"),
      teamIdentifier == "EQHXZ8M8AV",
      signingIdentifier == "com.google.Chrome" || signingIdentifier.hasPrefix("com.google.Chrome.")
    {
      return "chrome"
    }
    if isInsideApp(resolved, bundlePath: "/Applications/Microsoft Edge.app"),
      teamIdentifier == "UBF8T346G9",
      signingIdentifier == "com.microsoft.edgemac"
        || signingIdentifier.hasPrefix("com.microsoft.edgemac.")
    {
      return "edge"
    }
    if isInsideApp(resolved, bundlePath: "/Applications/Arc.app"),
      teamIdentifier == "S6N382Y83G",
      signingIdentifier == "company.thebrowser.Browser"
        || signingIdentifier.hasPrefix("company.thebrowser.Browser.")
    {
      return "arc"
    }
    return nil
  }

  private static func isInsideApp(_ path: String, bundlePath: String) -> Bool {
    path == bundlePath || path.hasPrefix(bundlePath + "/")
  }
}

/// Resolves the native host's browser parent from the kernel-reported executable path, then
/// validates that exact executable as static signed code. PID-to-dynamic-code lookup is not used:
/// ad-hoc endpoint testing showed that lookup can fail for otherwise valid GUI browser processes.
public enum BrowserProcessInspector {
  struct SigningIdentity: Equatable {
    let executablePath: String
    let signingIdentifier: String
    let teamIdentifier: String
  }

  public static func expectedBrowser(origin: String, parentPID: pid_t) -> String? {
    guard let path = processPath(pid: parentPID), let identity = signingIdentity(path: path) else {
      return nil
    }
    return BrowserCallerAuthorization.expectedBrowser(
      origin: origin, executablePath: identity.executablePath,
      signingIdentifier: identity.signingIdentifier, teamIdentifier: identity.teamIdentifier,
      signatureValid: true)
  }

  static func processPath(pid: pid_t) -> String? {
    guard pid > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: 4_096)
    let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard count > 0 else { return nil }
    let bytes = buffer.prefix(Int(count)).prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
      .resolvingSymlinksInPath().path
  }

  static func signingIdentity(path: String) -> SigningIdentity? {
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    var staticCode: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(resolved as CFURL, [], &staticCode) == errSecSuccess,
      let staticCode,
      SecStaticCodeCheckValidity(
        staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
    else { return nil }
    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let signing = information as? [CFString: Any],
      let identifier = signing[kSecCodeInfoIdentifier] as? String,
      let teamIdentifier = signing[kSecCodeInfoTeamIdentifier] as? String
    else { return nil }
    return SigningIdentity(
      executablePath: resolved.path, signingIdentifier: identifier,
      teamIdentifier: teamIdentifier)
  }
}
