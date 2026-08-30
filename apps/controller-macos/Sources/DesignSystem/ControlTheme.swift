import AppKit
import SwiftUI

public enum ControlAppearance: String, CaseIterable, Identifiable, Sendable {
  public static let storageKey = "appearance.mode"

  case system
  case light
  case dark

  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }

  fileprivate var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

/// Shared visual language for every current native Parental Control surface.
/// Platform controls remain native; these semantic tokens supply the product identity.
public enum ControlTheme {
  public static let canvas = adaptive(
    light: NSColor(srgbRed: 0.965, green: 0.972, blue: 0.982, alpha: 1),
    dark: NSColor(srgbRed: 0.025, green: 0.032, blue: 0.047, alpha: 1))
  public static let canvasRaised = adaptive(
    light: NSColor(srgbRed: 0.985, green: 0.988, blue: 0.994, alpha: 1),
    dark: NSColor(srgbRed: 0.045, green: 0.055, blue: 0.078, alpha: 1))
  public static let surface = adaptive(
    light: NSColor.white,
    dark: NSColor(srgbRed: 0.070, green: 0.082, blue: 0.110, alpha: 1))
  public static let surfaceStrong = adaptive(
    light: NSColor(srgbRed: 0.925, green: 0.938, blue: 0.958, alpha: 1),
    dark: NSColor(srgbRed: 0.095, green: 0.108, blue: 0.140, alpha: 1))
  public static let accent = adaptive(
    light: NSColor(srgbRed: 0.820, green: 0.180, blue: 0.125, alpha: 1),
    dark: NSColor(srgbRed: 1.000, green: 0.345, blue: 0.263, alpha: 1))
  public static let accentSoft = adaptive(
    light: NSColor(srgbRed: 0.660, green: 0.125, blue: 0.090, alpha: 1),
    dark: NSColor(srgbRed: 1.000, green: 0.475, blue: 0.390, alpha: 1))
  public static let textMuted = adaptive(
    light: NSColor(srgbRed: 0.330, green: 0.365, blue: 0.420, alpha: 1),
    dark: NSColor(srgbRed: 0.620, green: 0.650, blue: 0.710, alpha: 1))
  public static let border = adaptive(
    light: NSColor(white: 0.12, alpha: 0.16), dark: NSColor(white: 1, alpha: 0.12))
  public static let success = adaptive(
    light: NSColor(srgbRed: 0.070, green: 0.520, blue: 0.300, alpha: 1),
    dark: NSColor(srgbRed: 0.290, green: 0.820, blue: 0.550, alpha: 1))

  public static let displayTitle = Font.system(.largeTitle, design: .monospaced, weight: .bold)
  public static let sectionTitle = Font.system(.title3, design: .monospaced, weight: .semibold)
  public static let eyebrow = Font.system(.caption2, design: .monospaced, weight: .bold)

  private static func adaptive(light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
      })
  }
}

extension View {
  public func controlTheme() -> some View {
    modifier(ControlThemeModifier())
  }

  public func controlCanvas() -> some View {
    background(ControlTheme.canvas)
  }
}

private struct ControlThemeModifier: ViewModifier {
  @AppStorage(ControlAppearance.storageKey) private var appearanceRaw = ControlAppearance.system
    .rawValue

  func body(content: Content) -> some View {
    let appearance = ControlAppearance(rawValue: appearanceRaw) ?? .system
    content
      .preferredColorScheme(appearance.colorScheme)
      .tint(ControlTheme.accent)
  }
}

public struct ControlAppearancePicker: View {
  @AppStorage(ControlAppearance.storageKey) private var appearanceRaw = ControlAppearance.system
    .rawValue

  public init() {}

  public var body: some View {
    Picker("Appearance", selection: $appearanceRaw) {
      ForEach(ControlAppearance.allCases) { appearance in
        Text(appearance.title).tag(appearance.rawValue)
      }
    }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("appearance.mode")
  }
}

public struct ControlEyebrow: View {
  private let text: String

  public init(_ text: String) {
    self.text = text
  }

  public var body: some View {
    Text(text.uppercased())
      .font(ControlTheme.eyebrow)
      .tracking(1.4)
      .foregroundStyle(ControlTheme.accentSoft)
  }
}
