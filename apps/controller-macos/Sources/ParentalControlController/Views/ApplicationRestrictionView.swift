import DesignSystem
import HubCore
import SwiftUI

struct ApplicationRestrictionView: View {
  let device: HubDeviceRecord
  let configuration: ActivityConfiguration
  let applications: [HubAppActivity]
  let store: ControllerStore

  @State private var selectedBundleIdentifiers: Set<String> = []
  @State private var confirming = false

  private var uniqueApplications: [HubAppActivity] {
    var byBundle = Dictionary(grouping: applications, by: \.bundleIdentifier)
      .compactMapValues { $0.max { $0.observedAt < $1.observedAt } }
    for rule in configuration.restrictionPolicy?.rules ?? []
    where byBundle[rule.bundleIdentifier] == nil {
      byBundle[rule.bundleIdentifier] = HubAppActivity(
        deviceID: device.id, bundleIdentifier: rule.bundleIdentifier,
        applicationName: rule.applicationName, signingIdentifier: rule.signingIdentifier,
        teamIdentifier: rule.teamIdentifier, isForeground: false)
    }
    return byBundle.values.sorted {
      $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
    }
  }

  var body: some View {
    SectionCard {
      VStack(alignment: .leading, spacing: 10) {
        Text("Application-use restrictions").font(ControlTheme.sectionTitle)
        Text(
          "Select recently observed, signed third-party apps. Rules use the exact bundle, signing and Team identities—not display names or paths."
        )
        .font(.caption).foregroundStyle(.secondary)

        if !device.capabilities.contains("app-use-restrictions") {
          Label("Update the child endpoint and reconnect.", systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(ControlTheme.accentSoft)
        } else if uniqueApplications.isEmpty {
          Text("No observed applications are available yet. Open the app once on the child Mac.")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 8) {
              ForEach(uniqueApplications) { application in
                let protected = ApplicationRestrictionRule.isProtected(application.bundleIdentifier)
                let identityAvailable =
                  application.signingIdentifier == application.bundleIdentifier
                  && application.teamIdentifier?.isEmpty == false
                Toggle(
                  isOn: Binding(
                    get: { selectedBundleIdentifiers.contains(application.bundleIdentifier) },
                    set: { enabled in
                      if enabled {
                        selectedBundleIdentifiers.insert(application.bundleIdentifier)
                      } else {
                        selectedBundleIdentifiers.remove(application.bundleIdentifier)
                      }
                    })
                ) {
                  HStack {
                    VStack(alignment: .leading, spacing: 2) {
                      Text(application.applicationName)
                      Text(application.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if protected {
                      Text("Protected").font(.caption).foregroundStyle(.secondary)
                    } else if !identityAvailable {
                      Text("Signing identity unavailable").font(.caption).foregroundStyle(
                        .secondary)
                    }
                  }
                }
                .toggleStyle(.checkbox)
                .disabled(protected || !identityAvailable)
              }
            }
            .padding(.trailing, 6)
          }
          .scrollIndicators(.visible)
          .frame(height: min(220, max(50, CGFloat(uniqueApplications.count) * 46)))
        }

        HStack {
          Button("Apply App Policy…") { confirming = true }
            .disabled(!device.capabilities.contains("app-use-restrictions"))
          Text(
            "Requested policy: \(configuration.restrictionPolicy.map { String($0.version) } ?? "None")"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        if let message = store.applicationRestrictionStatusMessage {
          Text(message).font(.caption).foregroundStyle(.secondary)
        }
        Text(
          "Entitlement-free enforcement occurs immediately after launch, so an app may appear briefly. The helper requests a normal quit first and locks the session only if the app refuses. A local administrator can bypass this; use a standard child account."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .onAppear { synchronizeSelection() }
    .onChange(of: device.id) { _, _ in synchronizeSelection() }
    .onChange(of: configuration.restrictionPolicy?.version) { _, _ in synchronizeSelection() }
    .confirmationDialog(
      "Apply application-use policy?", isPresented: $confirming, titleVisibility: .visible
    ) {
      Button(selectedBundleIdentifiers.isEmpty ? "Remove App Restrictions" : "Apply Restrictions") {
        store.applyApplicationRestrictionPolicy(
          configuration: configuration,
          rules: uniqueApplications.compactMap { application in
            guard selectedBundleIdentifiers.contains(application.bundleIdentifier),
              let signingIdentifier = application.signingIdentifier,
              let teamIdentifier = application.teamIdentifier
            else { return nil }
            return try? ApplicationRestrictionRule(
              bundleIdentifier: application.bundleIdentifier,
              signingIdentifier: signingIdentifier, teamIdentifier: teamIdentifier,
              applicationName: application.applicationName)
          })
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Restricted apps will be asked to quit on the child Mac. Unsaved-work prompts remain controlled by the app and macOS."
      )
    }
  }

  private func synchronizeSelection() {
    selectedBundleIdentifiers = Set(
      configuration.restrictionPolicy?.rules.map(\.bundleIdentifier) ?? [])
  }
}
