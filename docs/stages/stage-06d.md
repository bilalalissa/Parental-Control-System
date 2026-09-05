# STAGE-06D — Managed browser website blocking

- Version: `0.6.4-rc.4` (build `6404`); browser extensions remain `0.6.4-rc.1` unchanged
- Branch: `stage/06d-macos-app-web-network-enforcement`
- Status: `IMPLEMENTING` (identity/XPC recovery retest; production distribution is not ready)
- Scope amended by the developer on 2026-09-05: `AUTHORIZE STAGE-06D SCOPE AMENDMENT: MANAGED BROWSER WEBSITE BLOCKING. PROCEED.`
- The former system-extension design in [ADR-0004](../adr/0004-macos-enforcement-extension-readiness.md) is deferred. Its Apple Developer ID and same Team ID gate and physical acceptance matrix apply only to future system-wide enforcement, not this browser-only test candidate.

## Objective and scope

Apply one parent-authored domain blocklist independently in each enrolled Chromium or Firefox profile through the existing authenticated LAN and native host. Preserve upgrades/pairing, current schedules and optional tab sharing. Do not modify browser installations or live family policies during development.

### RC4 retest: ad-hoc identity and XPC recovery

RC3 physical evidence showed the installed daemon running but unable to use its Keychain identity
(`User interaction is not allowed`) and rejecting all standard-user XPC clients. That combination
left authenticated LAN heartbeats offline and allowed the cached fail-closed schedule to relock the
child repeatedly. Wi-Fi connectivity was not the source of the Offline state.

The developer explicitly authorized a narrow exception for unsigned/ad-hoc test builds. RC4 stores
only the child endpoint's 32-byte Ed25519 private identity in an atomically renamed `root:wheel`
mode-`0600` file below the root-owned mode-`0700` endpoint directory. Controller secrets remain in
Keychain. The file survives an in-place package upgrade. A stable Developer ID distribution must
migrate this identity back to Keychain.

RC4 replaces PID-to-code lookup with a root-owned package manifest containing the four exact
installed executable paths, their expected signing identifiers and package-generated SHA-256
values. The daemon validates every executable and its ad-hoc hardened-runtime signature at startup,
then maps each XPC peer from the kernel-reported process path to that prevalidated record. A standard
child user cannot replace the manifest, executable, app bundle or identity file.

Before replacement the administrator installer stops the visible helper, preventing the stale lock
loop from continuing during upgrade. It writes a consumed-once root-only maintenance marker whose
hard maximum is ten minutes. This briefly clears schedule restriction during recovery and cannot be
renewed by a standard child account. A fresh signed policy restores clock trust after reconnection;
normal fail-closed offline enforcement resumes when the bounded window expires.

Because RC3 never successfully unlocked the old Keychain key, RC4 cannot securely recover that
private key. One final adult-authorized pairing repair is required after first installing RC4. Do
not unpair: create a fresh one-time invitation for the existing device and install it with
`parental-control-agentctl pair`; the controller rotates the public credential while retaining the
device record and policy history. Subsequent RC4 reinstalls and future compatible ad-hoc upgrades
reuse the protected file identity without another repair.

Acceptance: the child stays unlocked during the installer recovery window; one adult pairing repair
returns it Online; Status, session updates, immediate actions and browser policy controls work; the
same schedule is reapplied and locks only outside allowed time; a same-version reinstall reconnects
without repair; and the helper does not enter a five-second lock loop.

### RC3 retest: legacy helper replacement and one-time pairing repair

Developer evidence identified the daemon installed on the child as the exact ad-hoc rc.5 binary (`0bb256f6135e59e5b217d11894d9848c6f64529ec5dccd6c4c0d14d853b52a66`). The rc.2 upgrade bridge deliberately restored that legacy executable so its old Keychain access control remained valid. That preserved connectivity but also permanently prevented the current service from advertising `browser-website-policy`, leaving the parent editor disabled.

RC3 removes that compatibility bridge and installs the current daemon. When the installer detects only that exact legacy binary, it changes the protected configuration to an allowlisted new Keychain service. It does not read, export, copy or delete the old private identity. Because an ad-hoc executable cannot securely inherit another executable's Keychain access, one adult-authorized pairing repair is required after this specific upgrade.

The parent accepts the repair only with a fresh one-time invitation, a newly signed 32-byte Ed25519 public key, the same stable device ID, a non-revoked existing record and bounded capabilities. It rotates only the public credential and current capability declaration. The original pairing date, device ID, retained activity/browser data, schedule/browser configuration and audit history remain. Normal rc.3 reinstalls use the same new Keychain identity and do not repeat this repair.

Install Parent Controller rc.3 first and Child Endpoint rc.3 second. Do not click Unpair. Create a fresh one-time pairing invitation in the updated parent app, then on the child run:

```bash
sudo parental-control-agentctl pair --invitation "$TOKEN"
sudo launchctl kickstart -k system/com.bilalalissa.ParentalControlAgent.daemon
```

Replace `$TOKEN` with the complete invitation copied from the parent. The repair is intentionally not automatic because the parent must authorize credential rotation. If the installed child daemon did not have the exact legacy hash, no repair migration is applied.

Acceptance: the parent retains one existing device record rather than creating a duplicate; the child reconnects with build 6403; the parent advertises `browser-website-policy`; the domain editor enables; existing schedule/browser settings remain; and a subsequent rc.3 reinstall reconnects without another repair.

### RC2 retest: disabled controls after an upgrade

Developer feedback showed an online updated child while the parent disabled Apply Website Policy. The hub handled an existing device's authenticated capability announcement only as a last-seen update, retaining its original pairing-time capabilities. A synthetic upgrade/reconnect test reproduced missing `browser-website-policy`, retained obsolete support, and rejected policy application before the fix.

RC2 replaces the bounded declared capability list on authenticated reconnect, after existing key/revocation/replay checks. It verifies the announcement's public key matches the paired key, rejects malformed/oversized declarations, and does not change identity, pairing date, policies or revocation state. Removed capabilities are removed rather than accumulated. A metadata-only audit event is added only when capabilities change. The same upgrade test now delivers a new website policy without re-pairing.

The parent explains unavailable website capability more precisely and explicitly states that device-wide Internet pause is unavailable. The child's disabled Allow 15 Minutes button requires an adult code; it is a schedule override, not a WAN control. No WAN enforcement was added in this retest.

RC2's hub-side capability refresh remains in RC3. It fixes ordinary same-identity upgrades, while the one-time repair above handles the exact legacy helper that rc.2 had continued restoring. Browser source/packages are unchanged; already-loaded 0.6.4-rc.1 extensions need no reload for this native installer repair.

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

1. Quit the Parent app, install the RC4 Parent Controller component on the parent Mac, then reopen it. Install only Child Endpoint RC4 on the child Mac. Use an ordinary standard child account and retain an adult recovery administrator. Install over existing apps without uninstalling or clicking Unpair. The installer should stop the RC3 lock loop and provide at most ten minutes for recovery.
2. Perform the one final RC4 invitation repair exactly as described above. Confirm that the parent still shows the same device once, now online with website blocking available. Do not unpair or delete the existing device record.
3. Keep an existing loaded 0.6.4-rc.1 extension unchanged. Otherwise extract the Chromium ZIP to a stable location, load it through the browser's extension developer UI and approve the declarative blocking permission. Repeat per Chrome/Edge/Arc/Brave profile being tested.
4. For Firefox, temporarily load the unsigned XPI via about:debugging. Permanent restart/automatic-update testing is blocked until a signed distribution is available.
5. In Devices > Browser website restrictions, enter `example.com` and `youtube.com`, confirm Apply and wait for each reporting profile's matching policy acknowledgement (normally within 1–2 minutes).
6. Navigate to those domains/subdomains: denied. Unlisted domains remain available. Similar-looking unrelated domains must not match. Reloading an already loaded page must be tested separately.
7. Turn off tab sharing: domain denial continues; new tab titles/origins must not arrive.
8. Disconnect the parent LAN connection: stored restrictions continue in the running browser. Restore the LAN and apply a changed policy: matching acknowledgements return.
9. Close/restart Chromium: dynamic rules persist. Firefox temporary install restart is explicitly not a pass for permanent persistence.
10. Apply an empty list: confirm the formerly blocked sites become available and new-version acknowledgements arrive.
11. Disable/remove the extension or close the browser: after three minutes, status becomes Not reporting. Add another profile: do not infer protection from the first profile. Safari must remain Unsupported.
12. Reinstall the RC4 child component in place: it must reconnect without another invitation; the schedule, file identity and extension identity remain. Verify chat and schedule behavior remain intact and no repeated lock loop occurs.
13. Confirm the Parent app never claims device-wide WAN/app blocking or complete browser protection.

## Rollback and cleanup

Apply an empty website policy and wait for acknowledgements before removing test extensions if the intent is to remove restrictions. Removing an extension also removes its browser rules. Use the administrator uninstaller only when intentionally removing the child endpoint and its pairing data; do not uninstall for upgrades.

After packaging, remove only project-owned `dist`, derived-data, icon renders and package-staging using the existing cleanup dry-run/apply tool. Preserve the prior installer until the replacement is verified. Existing installed Parent Controller/hub and developer-owned simulator services are untouched.

## Evidence and resources

Source/build commit: `3e309ea3d25e6db88b07cbfb4143646bb883013e`. Existing draft PR: [#11](https://github.com/bilalalissa/Parental-Control-System/pull/11). The final documentation commit does not change packaged application/extension source.

Local checks on 2026-09-05:

- `node --test --test-concurrency=2 --test-reporter=tap`: 69 passed, one Windows-only skip (70 total), including 10 browser policy tests and static verification of the legacy-helper migration boundary.
- `swift test --package-path apps/controller-macos --scratch-path .artifacts/derived-data/stage-06d/controller-tests --jobs 2`: 54 passed (4 XCTest + 50 Swift Testing).
- `swift test --package-path agents/endpoint-macos --scratch-path .artifacts/derived-data/stage-06d/endpoint-tests --jobs 2`: 30 passed (4 XCTest + 26 Swift Testing). Includes isolated signed LAN policy delivery, child persistence, independent profile acknowledgement with sharing disabled, capability refresh, and an adult-authorized credential rotation that retains the existing record and browser configuration.
- `swift format lint` for both source/test trees, shell syntax checks and `git diff --check`: passed.
- `script/package_endpoint_release.sh`: passed for RC3, including package expansion, embedded migration scripts, expected native hosts and version/build checks. The packaged daemon SHA-256 is `58296df7de82c1e4d8b32e35623c5f2daad72a212e66ebffbe416d2ac9012464`, which differs from the detected legacy rc.5 daemon. Browser source/packages are unchanged from RC1; their existing checksums were reverified, not regenerated.
- `codesign --verify --deep --strict` on both apps: passed. Signatures are ad-hoc, Team ID absent. Installer is unsigned; no notarization or Apple managed entitlements claimed.
- `lipo -archs`: parent arm64; child, daemon, user helper and browser host arm64 + x86_64.
- `installer -showChoicesXML`: Parent selected by default; Child available separately. Authorized read-only inspection succeeded. No local installation was performed.
- SHA-256 sidecars verified with `shasum -a 256 -c`.

CI results are not claimed here. Real browser navigation, native-host authorization against installed browser versions, Intel execution, in-place install behavior on family devices and idle runtime resource use remain physical developer tests. Existing UI/hub processes were not used as test fixtures.

### Retained artifacts

All three files are in `.artifacts/release-candidate/`; each has a `.sha256` sidecar.

| File | Purpose / status | SHA-256 |
| --- | --- | --- |
| `ParentalControlSystem-0.6.4-rc.3.pkg` | Selectable parent/child installer; legacy-helper detection and one-time pairing repair; unsigned package with ad-hoc apps | `519e98c2ef3b1b8b7131b04a7068dd7822ddf21c3270f3b2cce1b7d02ba5d324` |
| `ParentalControlBrowserSharing-0.6.4-rc.1.zip` | Chromium unpacked developer test extension | `ab4e1585c211edbc3c311c7747a1db2754d444e22a83ef901b4f9b31668fb4e2` |
| `ParentalControlBrowserFirefox-0.6.4-rc.1.xpi` | Firefox unsigned temporary test extension | `3fd6e3df59222562e98db64b85739b6e716e7ede7f5f609545909dafa4ef04f4` |

### Resource report

Free disk before: 16 GiB; final free disk: 16 GiB. Initial repository: 29 MiB; initial retained artifacts: 16 MiB. Largest observed project output was about 744 MiB after build; peak estimate including transient package staging was under 900 MiB. Two build workers, sequential platform builds. No capacity exception; stayed above the 5 GiB floor.

Cleanup removed only reviewed project-owned `dist`, `.artifacts/derived-data`, `.artifacts/package-staging`, the temporary package-inspection directory, and the superseded `0.6.4-rc.2` macOS installer/checksum after replacement verification. Prior binaries were deleted, not archived; source remains in Git for rebuilding. Final repository: 29 MiB; artifacts: 16 MiB. Only one current installer and the two required browser-specific test packages remain. No project-started processes remain. No simulator was started; pre-existing developer-owned simulator services and installed parent/hub were left untouched.

## Failure evidence and feedback

Collect OS/browser version, selected installer component, test step, requested policy version and the affected profile's status. Include only redacted relevant extension errors or bounded app errors. Do not submit browsing history, full agent status, pairing/override codes, local IP/MAC addresses or private screenshots to this public repository.

```text
STAGE FEEDBACK
Stage: STAGE-06D
Version: 0.6.4-rc.4 (6404)
Platform and OS:
Hardware:
Result: PASS | FAIL | PARTIAL
Steps performed:
Expected:
Observed:
Logs:
Screenshots:
Requested changes:
Decision: CHANGES_REQUIRED | APPROVED
```

AWAITING DEVELOPER TEST RESULT
