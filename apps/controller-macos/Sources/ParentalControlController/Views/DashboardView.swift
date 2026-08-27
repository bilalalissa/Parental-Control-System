import AppKit
import DesignSystem
import HubCore
import SwiftUI

struct DashboardView: View {
  let store: ControllerStore
  let openDevice: (String) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        ScreenHeader(
          title: "Family overview",
          subtitle: "Your local authority for paired family devices—no cloud relay required."
        )

        HStack(spacing: 14) {
          MetricCard(
            title: "Paired",
            value: "\(store.pairedDevices.count)",
            subtitle: "Explicitly trusted devices",
            systemImage: "checkmark.shield",
            tint: ControlTheme.accent
          )
          MetricCard(
            title: "Online",
            value: "\(store.onlineDeviceCount)",
            subtitle: "Authenticated LAN presence",
            systemImage: "wifi",
            tint: ControlTheme.success
          )
          MetricCard(
            title: "Offline",
            value: "\(store.offlineDeviceCount)",
            subtitle: "Last seen—not inferred power state",
            systemImage: "wifi.slash",
            tint: ControlTheme.textMuted
          )
        }

        SectionCard {
          VStack(alignment: .leading, spacing: 12) {
            Label("Visible by design", systemImage: "hand.raised.fill")
              .font(.headline)
            Text(
              "Paired devices communicate directly over the authenticated local network. Controller data stays on this Mac, and every child endpoint remains visible to its user."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
        }

        SectionCard {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Label("Local device hub", systemImage: "network.badge.shield.half.filled")
                .font(.headline)
              Spacer()
              Text("\(store.pairedDevices.count) paired")
                .foregroundStyle(.secondary)
            }
            Text(store.hubStatusMessage)
              .foregroundStyle(.secondary)
            if let invitation = store.hubStatus?.invitation {
              HStack {
                Text(invitation.code)
                  .font(.system(.title2, design: .monospaced, weight: .bold))
                  .textSelection(.enabled)
                Text("Expires \(invitation.expiresAt.formatted(date: .omitted, time: .shortened))")
                  .foregroundStyle(.secondary)
                Spacer()
              }
              Text(
                "Use this code only in the visible Parental Control Child app you intend to pair."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              if let token = store.pairingInvitationToken {
                HStack {
                  Text("Pairing token: \(token.prefix(24))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                  Spacer()
                  Button("Copy pairing token") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(token, forType: .string)
                  }
                  .accessibilityIdentifier("dashboard.copyMockPairingToken")
                }
              }
            }
            HStack {
              Button("Create one-time pairing code") { store.createPairingInvitation() }
                .accessibilityIdentifier("dashboard.createPairing")
              if let message = store.pairingStatusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          Text("Devices")
            .font(.title2.weight(.semibold))
          if store.pairedDevices.isEmpty {
            ContentUnavailableView(
              "No paired devices", systemImage: "laptopcomputer.and.iphone",
              description: Text("Create a one-time pairing code to add a visible child device.")
            )
            .frame(maxWidth: .infinity, minHeight: 150)
          }
          ForEach(store.pairedDevices) { device in
            Button {
              openDevice(device.id)
            } label: {
              DashboardDeviceRow(device: device)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(device.name) details")
          }
        }
      }
      .padding(24)
    }
    .background(ControlTheme.canvas)
    .navigationTitle("Dashboard")
    .accessibilityIdentifier(AccessibilityID.dashboard.rawValue)
  }
}

private struct DashboardDeviceRow: View {
  let device: HubDeviceRecord

  var body: some View {
    SectionCard {
      HStack(spacing: 14) {
        Image(systemName: "laptopcomputer")
          .font(.title2)
          .foregroundStyle(.tint)
          .frame(width: 36)
        VStack(alignment: .leading, spacing: 3) {
          Text(device.name)
            .font(.headline)
          Text(
            "\(device.platform.capitalized) · Last seen \(device.lastSeen.formatted(date: .omitted, time: .shortened))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
        Spacer()
        HubStatusBadge(state: device.state())
        Image(systemName: "chevron.right")
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
  }
}

private struct HubStatusBadge: View {
  let state: HubDeviceState

  private var color: Color { state == .online ? ControlTheme.success : ControlTheme.textMuted }

  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(state == .online ? "Online" : "Offline")
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(color)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(color.opacity(0.12), in: Capsule())
  }
}
