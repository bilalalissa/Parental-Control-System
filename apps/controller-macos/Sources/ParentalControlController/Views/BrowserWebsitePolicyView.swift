import DesignSystem
import HubCore
import SwiftUI

struct BrowserWebsitePolicyView: View {
  let device: HubDeviceRecord
  let configuration: BrowserConfiguration
  let now: Date
  let store: ControllerStore
  @State private var domains = ""
  @State private var confirming = false

  var body: some View {
    SectionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Browser website restrictions").font(ControlTheme.sectionTitle)
        Text(
          "Block a domain and its subdomains in enrolled browser profiles. Enter one bare domain per line; use punycode for international names. An empty list removes these website restrictions."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        TextEditor(text: $domains).font(.body.monospaced()).frame(height: 110)
          .accessibilityLabel("Blocked website domains")
          .disabled(!device.capabilities.contains("browser-website-policy"))
        Button("Apply Website Policy…") { confirming = true }
          .disabled(!device.capabilities.contains("browser-website-policy"))
        if !device.capabilities.contains("browser-website-policy") {
          Text("Update the child app before applying website restrictions.").font(.caption)
        }
        Text(
          "Requested policy: \(configuration.websitePolicy.map { String($0.version) } ?? "None")"
        )
        .font(.caption)
        Text("Profile status is a bounded recent snapshot, not a complete browser inventory.")
          .font(.caption).foregroundStyle(.secondary)
        ForEach(configuration.protectionReports ?? []) { report in
          HStack(alignment: .top) {
            VStack(alignment: .leading) {
              Text(report.browser.capitalized)
              if !report.profile.isEmpty {
                Text("Profile \(report.profile.prefix(8))").font(.caption).foregroundStyle(
                  .secondary)
              }
            }
            Spacer()
            Text(
              report.label(
                expectedVersion: configuration.websitePolicy?.version, now: now,
                online: device.state(now: now) == .online)
            ).font(.caption)
          }
        }
        Text(
          "Coverage is limited to reporting profiles. New, guest/private or unregistered profiles and browsers outside known installation locations are not proven protected. Safari is unsupported. A stopped browser and a removed extension may both show Not reporting. This does not pause device Internet or stop already loaded content."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Text(
          "Test extensions require manual loading. Automatic updates require a published/signed browser distribution; they are not provided by this test package."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .onAppear { domains = configuration.websitePolicy?.domains.joined(separator: "\n") ?? "" }
    .confirmationDialog(
      "Apply these website restrictions to enrolled profiles?", isPresented: $confirming
    ) {
      Button("Apply Website Policy") {
        store.applyBrowserWebsitePolicy(
          configuration: configuration,
          domains: domains.split(whereSeparator: \.isNewline).map(String.init))
      }
      Button("Cancel", role: .cancel) {}
    }
  }
}
