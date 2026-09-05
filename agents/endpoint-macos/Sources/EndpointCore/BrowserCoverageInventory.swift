import Foundation
import HubCore

/// Checks only known application locations, never browser profile files or history.
public enum BrowserCoverageInventory {
  public static func reports(_ enrolled: [BrowserProtectionReport], now: Date = Date())
    -> [BrowserProtectionReport]
  {
    var result = Array(enrolled.suffix(24))
    let candidates = [
      ("chrome", "/Applications/Google Chrome.app"), ("edge", "/Applications/Microsoft Edge.app"),
      ("arc", "/Applications/Arc.app"), ("brave", "/Applications/Brave Browser.app"),
      ("firefox", "/Applications/Firefox.app"), ("safari", "/System/Applications/Safari.app"),
      ("safari", "/Applications/Safari.app"),
    ]
    for (browser, path) in candidates where FileManager.default.fileExists(atPath: path) {
      if !result.contains(where: { $0.browser == browser }) {
        result.append(
          BrowserProtectionReport(
            browser: browser, profile: "", version: nil,
            state: browser == "safari" ? "unsupported" : "setup-required", observedAt: now))
      }
    }
    return Array(result.prefix(32))
  }
}
