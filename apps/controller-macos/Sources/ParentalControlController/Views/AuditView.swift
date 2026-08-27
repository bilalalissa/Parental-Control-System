import SwiftUI

struct AuditView: View {
  let events: [AuditEvent]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScreenHeader(
        title: "Audit",
        subtitle:
          "Bounded local events. Message content and secrets never belong in audit metadata."
      )
      .padding(24)

      Divider()

      List(events) { event in
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: symbol(for: event.severity))
            .foregroundStyle(color(for: event.severity))
            .frame(width: 20)
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(event.title)
                .font(.headline)
              Spacer()
              Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(event.detail)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        }
      }
      .listStyle(.inset)
      .overlay {
        if events.isEmpty {
          ContentUnavailableView(
            "No audit events", systemImage: "checkmark.shield",
            description: Text("Authenticated controller events will appear here."))
        }
      }
    }
    .navigationTitle("Audit")
    .accessibilityIdentifier(AccessibilityID.audit.rawValue)
  }

  private func symbol(for severity: AuditSeverity) -> String {
    switch severity {
    case .information: "info.circle.fill"
    case .notice: "bell.badge.fill"
    case .warning: "exclamationmark.triangle.fill"
    }
  }

  private func color(for severity: AuditSeverity) -> Color {
    switch severity {
    case .information: .blue
    case .notice: .orange
    case .warning: .red
    }
  }
}
