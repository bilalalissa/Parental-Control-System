import SwiftUI

/// Shared visual language for every current native Parental Control surface.
/// Platform controls remain native; these semantic tokens supply the product identity.
public enum ControlTheme {
  public static let canvas = Color(red: 0.025, green: 0.032, blue: 0.047)
  public static let canvasRaised = Color(red: 0.045, green: 0.055, blue: 0.078)
  public static let surface = Color(red: 0.070, green: 0.082, blue: 0.110)
  public static let surfaceStrong = Color(red: 0.095, green: 0.108, blue: 0.140)
  public static let accent = Color(red: 1.000, green: 0.345, blue: 0.263)
  public static let accentSoft = Color(red: 1.000, green: 0.475, blue: 0.390)
  public static let textMuted = Color(red: 0.620, green: 0.650, blue: 0.710)
  public static let border = Color.white.opacity(0.12)
  public static let success = Color(red: 0.290, green: 0.820, blue: 0.550)

  public static let displayTitle = Font.system(.largeTitle, design: .monospaced, weight: .bold)
  public static let sectionTitle = Font.system(.title3, design: .monospaced, weight: .semibold)
  public static let eyebrow = Font.system(.caption2, design: .monospaced, weight: .bold)
}

extension View {
  public func controlTheme() -> some View {
    preferredColorScheme(.dark)
      .tint(ControlTheme.accent)
  }

  public func controlCanvas() -> some View {
    background(ControlTheme.canvas)
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
