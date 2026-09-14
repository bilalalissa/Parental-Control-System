import DesignSystem
import HubCore
import SwiftUI

struct BrowserWebsitePolicyView: View {
  let device: HubDeviceRecord
  let configuration: BrowserConfiguration
  let now: Date
  let store: ControllerStore
  @State private var domains = ""
  @State private var domainsDirty = false
  @State private var confirming = false
  @State private var retiringReport: BrowserProtectionReport?

  var body: some View {
    SectionCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Browser website restrictions").font(ControlTheme.sectionTitle)
        Text(
          "Block a domain and its subdomains in enrolled browser profiles. Enter one bare domain per line; use punycode for international names. An empty list removes these website restrictions."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        TextEditor(
          text: Binding(
            get: { domains },
            set: {
              domains = $0
              domainsDirty = true
            })
        ).font(.body.monospaced()).frame(height: 110)
          .accessibilityLabel("Blocked website domains")
          .disabled(!device.capabilities.contains("browser-website-policy"))
        Button("Apply Website Policy…") { confirming = true }
          .disabled(!device.capabilities.contains("browser-website-policy"))
        if let status = store.browserStatusMessage {
          Text(status).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !device.capabilities.contains("browser-website-policy") {
          Text(
            "The connected child service has not advertised website blocking. Update the child endpoint and reconnect; re-pairing is not required."
          ).font(.caption)
        }
        Text(
          "Requested policy: \(configuration.websitePolicy.map { String($0.version) } ?? "None")"
        )
        .font(.caption)
        Text("Profile status is a bounded recent snapshot, not a complete browser inventory.")
          .font(.caption).foregroundStyle(.secondary)
        if hasProtectionGap {
          Label(
            protectionGapMessage,
            systemImage: "exclamationmark.shield.fill"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(ControlTheme.accentSoft)
        }
        ForEach(enrolledReports) { report in
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
            if report.label(
              expectedVersion: configuration.websitePolicy?.version, now: now,
              online: device.state(now: now) == .online) == "Not reporting"
            {
              Button("Retire Profile…") { retiringReport = report }
                .font(.caption)
                .help("Use only after this browser profile or extension installation was removed.")
            }
          }
        }
        Text(
          "Coverage is limited to reporting profiles. New, guest/private or unregistered profiles and browsers outside known installation locations are not proven protected. Safari requires its installed companion extension to be enabled for each tested profile with website access. A stopped browser and a removed extension may both show Not reporting. This does not pause device Internet or stop already loaded content."
        )
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Text(
          "Device-wide Internet pause is not available in this release. Website rules only block the listed domains in enrolled browser profiles. Test extensions require manual loading; production automatic updates are not provided by this package."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
    .onAppear { hydrateDomainsIfUnedited(configuration.websitePolicy) }
    .onChange(of: configuration.websitePolicy) { _, policy in
      hydrateDomainsIfUnedited(policy)
    }
    .confirmationDialog(
      "Apply these website restrictions to enrolled profiles?", isPresented: $confirming
    ) {
      Button("Apply Website Policy") {
        domainsDirty = false
        store.applyBrowserWebsitePolicy(
          configuration: configuration,
          domains: domains.split(whereSeparator: \.isNewline).map(String.init))
      }
      Button("Cancel", role: .cancel) {}
    }
    .alert(item: $retiringReport) { report in
      Alert(
        title: Text("Retire this browser profile?"),
        message: Text(
          "Only continue if profile \(report.profile.prefix(8)) in \(report.browser.capitalized) was removed or its extension was reinstalled under a new profile identity. This stops the old profile from counting as a protection gap."
        ),
        primaryButton: .destructive(Text("Retire Profile")) { retire(report) },
        secondaryButton: .cancel())
    }
  }

  private func hydrateDomainsIfUnedited(_ policy: BrowserWebsitePolicy?) {
    guard !domainsDirty else { return }
    domains = policy?.domains.joined(separator: "\n") ?? ""
  }

  private var hasProtectionGap: Bool {
    guard configuration.websitePolicy?.domains.isEmpty == false else { return false }
    return BrowserProtectionCoverage.hasProtectionGap(
      reports: enrolledReports, expectedVersion: configuration.websitePolicy?.version, now: now,
      online: device.state(now: now) == .online)
  }

  private var protectionGapMessage: String {
    if device.consoleAccountType == "administrator" {
      return
        "Protection gap: no enrolled profile has applied the current website policy, or a profile reported an error or older policy. An administrator can disable or remove an unmanaged extension."
    }
    if device.consoleAccountType == "none" {
      return "Website-policy reporting is paused because no child session is active."
    }
    return
      "Protection gap: no enrolled profile has applied the current website policy, or a profile reported an error or older policy. Open the affected browser and check its extension."
  }

  private var enrolledReports: [BrowserProtectionReport] {
    BrowserProtectionCoverage.enrolledReports(
      configuration.protectionReports ?? [],
      retiredReportIDs: configuration.websitePolicy?.retiredReportIDs ?? [])
  }

  private func retire(_ report: BrowserProtectionReport) {
    var retired = configuration.websitePolicy?.retiredReportIDs ?? []
    retired.append(report.id)
    store.applyBrowserWebsitePolicy(
      configuration: configuration,
      domains: configuration.websitePolicy?.domains ?? [], retiredReportIDs: retired)
  }
}
