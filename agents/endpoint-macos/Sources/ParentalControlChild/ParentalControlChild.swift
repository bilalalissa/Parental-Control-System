import EndpointCore
import SwiftUI

@main
struct ParentalControlChildApp: App {
  @StateObject private var model = ChildDashboardModel()
  var body: some Scene {
    WindowGroup("Parental Control") {
      ChildDashboard(model: model).frame(minWidth: 620, minHeight: 520)
    }
    .windowResizability(.contentMinSize)
  }
}

@MainActor
final class ChildDashboardModel: ObservableObject {
  @Published var status: EndpointStatus?
  @Published var error = "Connecting to the protected endpoint service…"
  private let client = EndpointXPCClient()
  private var timer: Timer?
  init() {
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }
  func refresh() {
    client.fetchStatus { [weak self] result in
      Task { @MainActor in
        switch result {
        case .success(let value):
          self?.status = value
          self?.error = ""
        case .failure:
          self?.error =
            "Endpoint service unavailable. Ask an administrator to run parental-control-agentctl status."
        }
      }
    }
  }
}

struct ChildDashboard: View {
  @ObservedObject var model: ChildDashboardModel
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(
          width: 64, height: 64)
        VStack(alignment: .leading) {
          Text("Parental controls are visible and active").font(.title2.bold())
          Text(
            "This Mac shares limited device status directly with your parent controller on the local network."
          ).foregroundStyle(.secondary)
        }
      }
      Divider()
      if let status = model.status {
        statusGrid(status)
        GroupBox("Information shared") {
          Text(
            "Device name and model, macOS version, architecture, uptime, login/session state, network interface IP and MAC metadata, and agent health. No screenshots, keystrokes, passwords, files, messages, microphone, camera, or page content are collected."
          ).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        GroupBox("Schedule and contact") {
          Text(
            "No schedule or enforcement is configured in this foundation release. Contact your parent or guardian directly if you need help."
          ).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
      } else {
        ProgressView()
        Text(model.error).foregroundStyle(.secondary)
      }
      Spacer()
    }.padding(24).toolbar {
      Button("Refresh") { model.refresh() }.accessibilityIdentifier("refresh-status")
    }
  }
  private func statusGrid(_ status: EndpointStatus) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
      row("Controller", status.connectionState.rawValue.capitalized)
      row(
        "Last contact",
        status.lastControllerContact?.formatted(date: .abbreviated, time: .standard) ?? "Never")
      row("This Mac", "\(status.deviceName) · \(status.model)")
      row("System", "\(status.operatingSystem) · \(status.architecture)")
      row("Session", status.sessionState.rawValue.capitalized)
      row(
        "Uptime",
        Duration.seconds(status.uptimeSeconds).formatted(
          .units(allowed: [.days, .hours, .minutes], width: .abbreviated)))
      row(
        "Components",
        status.daemonHealthy && status.helperHealthy
          ? "Healthy" : "Daemon active; login helper pending")
    }
  }
  private func row(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }
}
