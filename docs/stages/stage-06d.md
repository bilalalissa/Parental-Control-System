# STAGE-06D — Managed browser website blocking

- Version: `0.6.4-rc.1` (build `6401`)
- Branch: `stage/06d-macos-app-web-network-enforcement`
- Status: `IMPLEMENTING`
- Scope amended by the developer on 2026-09-05: `AUTHORIZE STAGE-06D SCOPE AMENDMENT: MANAGED BROWSER WEBSITE BLOCKING. PROCEED.`
- The former system-extension design in [ADR-0004](../adr/0004-macos-enforcement-extension-readiness.md) is deferred. Its Apple Developer ID and same Team ID gate and physical acceptance matrix apply only to future system-wide enforcement, not this browser-only test candidate.

## Objective and scope

Apply one parent-authored domain blocklist independently in each enrolled Chromium or Firefox profile through the existing authenticated LAN and native host. Preserve upgrades/pairing, current schedules and optional tab sharing. Do not modify browser installations or live family policies during development.

Included: bounded domain validation (256 ASCII/punycode domains, no URLs/IPs/local names), signed envelope transport, protected child persistence and version rollback checks, declarative navigation/subframe blocking, dynamic-rule readback before acknowledgement, per-profile status, known-browser setup warnings, local test packages and a macOS installer.

Excluded: Safari; application-launch denial; whole-device WAN pause; Apple system extensions; MDM/force installation; private/guest-session collection; request/page content; TLS interception; bypass resistance to a device administrator; unknown-browser guarantees; Stage 07.

## Enforcement and coverage semantics

- Domains include their subdomains using the browser's declarative domain matcher, not URL/title substring searches.
- Blocking covers future top-level/frame navigations. Already loaded pages, playing media, cached content and connections are not forcibly terminated.
- Tab sharing and blocking are independent. Disabling collection clears retained tab data but preserves the restriction policy.
- Parent changes generate an increasing version and are signed by the paired controller. Endpoint persistence is root-protected; stale and same-version conflicting policies are rejected.
- Combined browser policy configuration is capped at 24 KiB before persistence to reserve space in the 64 KiB local IPC response. Oversized lists are rejected, never silently truncated. Profile status is a bounded recent snapshot and may be compacted under IPC pressure; absent profiles are not proven protected.
- An explicit newer empty list removes rules. A host/network failure never implicitly clears a valid stored list.
- Extensions retain dynamic rules across normal restarts and upgrades. Browser policy reconciliation occurs at startup, tab activity and a one-minute alarm while the browser runs; alarms may be delayed by sleep.
- A profile acknowledges only after browser rule readback. Acknowledgements are not independent tamper attestation or a physical navigation test.
- Coverage is bounded to 24 reporting profiles plus known installed browsers (Chrome, Edge, Arc, Brave, Firefox, Safari) in documented /Applications locations. Other locations, newly created profiles and unknown browsers are not claimed detected.
- A matching recent acknowledgement is `Policy applied`; an older version is `Policy pending`; an offline device or stale report is `Not reporting`. Closed browsers and removed extensions cannot always be distinguished.
- Safari is unsupported. Guest/private browsing and profiles without an enabled extension remain gaps.
- Browser metadata logs remain bounded and omit blocked URLs, requests and content.

## Distribution and automatic-update boundary

The installer registers authenticated native hosts, not browser extensions. Explicit per-browser/profile extension installation remains required. It preserves installed extension identity and app pairing.

Chromium: the ZIP is an unpacked developer-test package; the stable existing extension ID is preserved. Adding the new permission can require approval/reloading. Supported production automatic updates require Chrome Web Store publication or an eligible managed self-hosted deployment. No publisher account or managed deployment is configured in this stage.

Firefox: the XPI is unsigned and intended for temporary installation through `about:debugging#/runtime/this-firefox`. Firefox 133+ is required. Temporary add-ons do not survive restart as a permanent installation. Normal installation and automatic updates require Mozilla signing and a configured distribution path. No signing enforcement is disabled.

Thus local implementation does not mean production automatic updates are complete. Signing/publication and physical browser tests remain separate release gates. No Apple Developer membership is required for the browser-only source/test package; the native macOS apps remain ad-hoc signed and the package unsigned/not notarized.

Official references:
- [Chrome distribution and automatic updates](https://developer.chrome.com/docs/extensions/how-to/distribute)
- [Mozilla signing and distribution](https://extensionworkshop.com/documentation/publish/signing-and-distribution-overview/)
- [Persistent dynamic rules](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/declarativeNetRequest/updateDynamicRules)
- [Firefox native messaging arguments and host authorization](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging)

## Acceptance and smallest test plan

1. Dependency-free Node tests: normalization, rule generation/readback, failure preservation, rollback, explicit clear, privacy permissions and Firefox manifest generation.
2. Swift endpoint and hub tests: policy persistence/migration, acknowledgements, freshness and caller authorization.
3. Build parent arm64 and child universal sequentially, two workers, under `.artifacts/derived-data/stage-06d`.
4. Build one combined selectable macOS package plus Chromium ZIP and Firefox test XPI; inspect contents, architectures/signatures and SHA-256.
5. Physical developer tests below are required. Native-host browser identity and real DNR behavior are not proven by source mocks.
6. Keep at least 5 GiB free. No VMs, simulators or live-device enforcement during development.

## Installation and manual developer tests

1. Install the Parent Controller component on the parent Mac; install only Child Endpoint on the child Mac. Use an ordinary standard child account and retain an adult recovery administrator. Install over the existing apps, without uninstalling/unpairing.
2. Extract the Chromium ZIP to a stable location. Load/reload it through the browser's extension developer UI and approve the new declarative blocking permission. Repeat per Chrome/Edge/Arc/Brave profile being tested.
3. For Firefox, temporarily load the unsigned XPI via about:debugging. Permanent restart/automatic-update testing is blocked until a signed distribution is available.
4. In Devices > Browser website restrictions, enter `example.com` and `youtube.com`, confirm Apply and wait for each reporting profile's matching policy acknowledgement (normally within 1–2 minutes).
5. Navigate to those domains/subdomains: denied. Unlisted domains remain available. Similar-looking unrelated domains must not match. Reloading an already loaded page must be tested separately.
6. Turn off tab sharing: domain denial continues; new tab titles/origins must not arrive.
7. Disconnect the parent LAN connection: stored restrictions continue in the running browser. Restore the LAN and apply a changed policy: matching acknowledgements return.
8. Close/restart Chromium: dynamic rules persist. Firefox temporary install restart is explicitly not a pass for permanent persistence.
9. Apply an empty list: confirm the formerly blocked sites become available and new-version acknowledgements arrive.
10. Disable/remove the extension or close the browser: after three minutes, status becomes Not reporting. Add another profile: do not infer protection from the first profile. Safari must remain Unsupported.
11. Reinstall the app package in place: existing pairing, schedule and extension identity are preserved. Verify chat and schedule behavior remain intact.
12. Confirm the Parent app never claims device-wide WAN/app blocking or complete browser protection.

## Rollback and cleanup

Apply an empty website policy and wait for acknowledgements before removing test extensions if the intent is to remove restrictions. Removing an extension also removes its browser rules. Use the administrator uninstaller only when intentionally removing the child endpoint and its pairing data; do not uninstall for upgrades.

After packaging, remove only project-owned `dist`, derived-data, icon renders and package-staging using the existing cleanup dry-run/apply tool. Preserve the prior installer until the replacement is verified. Existing installed Parent Controller/hub and developer-owned simulator services are untouched.

## Evidence and resources

Initial free disk: 18 GiB. Repository: 28 MiB; retained artifacts: 15 MiB. No stale project-started process was identified; installed parent/hub are developer-owned. Tests/build/package evidence and final resource measurements will be recorded after verification.
