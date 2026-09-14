import Foundation
import HubCore

/// Retains only profiles that have actually acknowledged through an authenticated browser host.
/// Application installation paths do not prove that a profile or extension is enrolled.
public enum BrowserCoverageInventory {
  public static func reports(_ enrolled: [BrowserProtectionReport], now: Date = Date())
    -> [BrowserProtectionReport]
  {
    BrowserProtectionCoverage.enrolledReports(enrolled)
  }
}
