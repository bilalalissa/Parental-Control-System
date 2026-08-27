import DesignSystem
import SwiftUI

struct SectionCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(ControlTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(ControlTheme.border, lineWidth: 1)
      }
  }
}

struct StatusBadge: View {
  let state: DeviceConnectionState

  private var color: Color {
    switch state {
    case .online: .green
    case .offline: .secondary
    case .approximate: .blue
    }
  }

  var body: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
      Text(state.title)
        .lineLimit(1)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(color)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(color.opacity(0.10), in: Capsule())
  }
}

struct MetricCard: View {
  let title: String
  let value: String
  let subtitle: String
  let systemImage: String
  let tint: Color

  var body: some View {
    SectionCard {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: systemImage)
          .font(.title2)
          .foregroundStyle(tint)
          .frame(width: 34, height: 34)
          .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        VStack(alignment: .leading, spacing: 4) {
          Text(value)
            .font(.title2.weight(.semibold))
          Text(title)
            .font(.headline)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

struct ScreenHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(ControlTheme.displayTitle)
      Text(subtitle)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottomLeading) {
      Rectangle()
        .fill(ControlTheme.accent)
        .frame(width: 42, height: 2)
        .offset(y: 11)
    }
  }
}
