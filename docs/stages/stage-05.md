# STAGE-05 — Shared Chromium extension and macOS integration

- Version: `0.5.0-rc.2`
- Branch: `stage/05-chromium-extension`
- Status: `READY_FOR_RETEST`
- Platform: Chrome and Microsoft Edge on a universal macOS child endpoint; Parent Controller on Apple silicon; macOS 14 or newer

## Objective and scope

Deliver one visible Manifest V3 WebExtension source for Chrome and Edge, one packaged extension, and a narrowly authenticated macOS native-messaging host. When the parent explicitly enables sharing, collect at most 128 open HTTP(S) tab titles and query-free origins with browser, pseudonymous local profile, active state, and observation time. Exclude private tabs and clear retained metadata immediately when disabled.

Complete the deferred Stage 04 chat feedback: a short system alert after a sender successfully queues a message, generic system-controlled arrival sound for both parent and child receivers, red unread counters on both Chat navigation items, distinct `Sent`, `Delivered`, and `Read` indicators, durable acceptance before `Delivered`, and an explicit relevant-conversation visibility event before `Read`.

Excluded: Safari, browser history, page/document contents, full URLs or paths, query strings, fragments, forms, cookies, passwords, private browsing, downloads, bookmarks, network traffic, screenshots, keystrokes, clipboard, message contents in logs/audit/notification diagnostics, schedule enforcement, remote actions, public relay, cloud storage, and Stage 06+ work.

## Delivered design

- The shared extension requests only `tabs`, `storage`, `nativeMessaging`, and `alarms`. It filters private tabs, accepts only HTTP(S), converts URLs to origins, caps each update at 128 records, debounces change events by 500 ms, and performs one bounded 15-minute reconciliation.
- The deterministic extension identity is embedded as a public manifest key. The native-host manifest allows exactly that extension origin and points to one installed universal helper.
- The native host verifies the exact extension origin and the valid signed parent browser process at an expected Google Chrome or Microsoft Edge application path. Endpoint XPC independently restricts browser configuration and updates to the signed, root-protected installed host.
- Browser sharing defaults off. The parent enables it per child and chooses one-to-thirty-day retention; disabling clears endpoint memory and controller SQLite records. The visible child app and extension popup disclose the exact fields and exclusions.
- Browser records reuse the signed, replay-protected local TLS channel. Controller storage is bounded to 128 records per device and audit metadata omits titles and origins.
- A sender receives one short system alert only after at least one target accepts the queued message. A receiving child or parent uses an ordinary generic UserNotifications notification with the default sound; the visible child app and logged-in helper both register foreground delegates. macOS notification permission, mute, Focus, and sound preferences remain authoritative for arrivals.
- The parent sidebar and child tab bar display a red count derived only from incoming messages whose durable state is not `Read`. Opening the relevant conversation advances receipts and clears the corresponding count; outgoing messages never contribute.
- `Delivered` is set only after the receiving side durably saves the message and returns an authenticated receipt. `Read` is sent only when the receiver opens the relevant conversation; dashboard/status refreshes do not mark messages read.

## Verification evidence

| Check | Result |
| --- | --- |
| Repository tests | 34 passed; one Windows-only cleanup test skipped on macOS (35 total), including regression assertions for the SDK-compatible parent notification delegate signature and fresh default-parent CI installation order. |
| Controller/hub suite | 29 tests in 9 suites passed, including browser migration/bounds/pruning, monotonic receipt transitions, and incoming-only unread counting. |
| Endpoint suite | All 11 tests passed locally, including real TLS pairing, restart/reconnect, heartbeat progression, revocation, browser opt-in/sanitization/host identity, and explicit-read behavior. The integration test uses an injected ephemeral reconnect port while a separate assertion proves production still defaults to stable port `49171`. |
| Formatting/static checks | `swift format lint`, `git diff --check`, JSON parsing, JavaScript syntax, shell syntax, and extension packaging without optional `rg` passed. |
| Privacy/security checks | Extension permission allowlist, private-tab filtering, query/fragment stripping, 128-record bounds, native caller identity, installed-host XPC identity, no private-key/API-token diff patterns, and no production npm dependencies passed. |
| Extension package | ZIP integrity, eight required files, no key/certificate file extensions, and SHA-256 passed. Chrome/Edge physical loading remains a developer check. |
| Bundle/package | Strict nested ad-hoc app signatures, selectable choices XML, package payload/native manifests, embedded `0.5.0-rc.2` build `5002`, source commit `ba5de9270eab`, and SHA-256 passed. |
| Universal binaries | Child app, daemon, login helper, typed control tool, and browser host each report `x86_64 arm64`. |
| GitHub Actions | macOS 15 verification passed repository tests, formatting, controller/endpoint suites, packaging, universal-slice checks, fresh default-parent installation, child installation/status/launch/uninstallation, artifact upload, and scoped cleanup. Supporting cleanup and secret-scanning checks also passed. |

The final package was not installed over the developer Mac's existing approved parent installation. The draft PR passed disposable default-parent and child install/uninstall checks on a fresh macOS 15 CI runner. No claim is made for Intel execution or physical Chrome/Edge behavior until developer evidence is available.

## Release candidates

- `.artifacts/release-candidate/ParentalControlSystem-0.5.0-rc.2.pkg`
  - Purpose: selectable Parent Controller or universal visible macOS Child Endpoint, including the native host and Chrome/Edge native-host manifests
  - SHA-256: `0207c8f53d2bdb9198b8260d34a48af2eab525bbcc84ddaf951c420482a35c3c`
  - Apps/helpers: ad-hoc signed, no Team ID or restricted entitlements
  - Installer: unsigned and not notarized; no Developer ID Installer identity is available
- `.artifacts/release-candidate/ParentalControlBrowserSharing-0.5.0-rc.2.zip`
  - Purpose: one shared unpacked-extension package for Chrome and Microsoft Edge
  - SHA-256: `e6b8ad1674522fa556cfb5ef87b00e97b5b527207826e47498fc6d6e92f57b9b`
  - ZIP/extension: unsigned and not store-published; contains only the public extension key, not private signing material

## Installation outline

1. Install the selectable macOS package, choosing the Parent Controller on the parent Mac and the Child Endpoint on the child Mac.
2. Extract the single browser-extension ZIP into one stable child-owned folder.
3. In Chrome or Edge, open the extensions page, enable Developer mode, choose **Load unpacked**, and select the extracted `ParentalControlBrowserSharing` folder. Do not enable the extension in private/incognito mode.
4. On the parent, expand the paired child in Devices and explicitly enable **Share browser tab titles and website origins**. Retention defaults to seven days.

## Uninstallation / rollback

Run `sudo "/Applications/Parental Control Child.app/Contents/Resources/uninstall.sh"`. It removes the app, daemon/helper/tool, Chrome/Edge native-host manifests, protected endpoint state, endpoint Keychain item, and project-owned logs. Remove the visible extension from each Chrome/Edge profile separately. To roll back the parent, quit it and reinstall the approved Stage 04 package while preserving controller Application Support if local family history is needed.

## Manual developer checklist

1. Verify both SHA-256 values, install the parent default choice and child customized choice, and confirm both visible apps report `0.5.0-rc.2`.
2. Confirm the existing pairing survives upgrade and the child appears Online without a new token.
3. Extract the extension ZIP, load the same folder in Chrome, and confirm its popup says sharing is disabled before the parent opts in.
4. Enable browser sharing on the parent. Open normal HTTP(S) tabs, including one URL with a path, query, and fragment. Confirm the parent shows only tab title plus scheme/host/optional port—never path, query, fragment, credentials, or content.
5. If Microsoft Edge is installed, load the same extension folder there and confirm Chrome and Edge records both appear. Do not enable private/incognito access; if temporarily enabled for the test, confirm a private tab is never shown, then disable private access again.
6. Open more than 128 synthetic/ordinary tabs only if safe for the test Mac and confirm the controller remains capped at 128 records; otherwise leave this bound to automated evidence.
7. Disable browser sharing and confirm retained tab records disappear from the parent and the extension popup reports disabled. Re-enable and test one-to-thirty-day retention controls.
8. Keep the child on Status, send a parent-to-child direct message, and confirm one parent send alert, one permitted child arrival sound, and a red count on the child Chat tab. Open Chat and confirm the count clears and the parent advances Sent → Delivered → Read.
9. Keep the parent on Devices, send a child-to-parent message, and confirm one child send alert, one permitted parent arrival sound, and a red count on the parent Chat sidebar item. Open the matching conversation and confirm the count clears and the child advances Delivered → Read.
10. Repeat one family group message and one announcement. Confirm no message text, tab title, or origin appears in audit/log details.
11. Quit/reopen both visible apps and confirm chat history/states persist. Sleep/wake the child and confirm existing offline/reconnect behavior remains correct.
12. Remove the extension from Chrome/Edge and confirm no new browser records arrive. Run the bundled child uninstaller and confirm both native-host manifest files and the endpoint app/jobs/tool/data are removed.

## Known development-candidate limitations

- The extension is a developer package, not Chrome Web Store or Microsoft Edge Add-ons signed/distributed. Each browser profile must load it explicitly.
- The app/helper signatures are local ad-hoc signatures; the installer and ZIP are unsigned and not notarized.
- Browser collection depends on the visible extension, installed child endpoint, active paired daemon, and local LAN. There is no relay or background cloud delivery.
- Tab metadata is a current bounded snapshot, not browsing history or usage-duration accounting.

## Resource and cleanup evidence

- Free disk before Stage 05: 7.5 GiB; repository: 15 MiB; retained prior RC output: 9.3 MiB.
- Free disk before the `rc.2` feedback fix: 10 GiB; repository: 17 MiB; retained `rc.1` candidate: 11 MiB.
- Builds used two workers, one checkout, one project-owned Stage 05 build tree, sequential endpoint architectures, no simulator, VM, container, worktree, browser driver, or dev server.
- Peak project-owned generated output was approximately 508 MiB (482 MiB under `.artifacts` plus 26 MiB `dist`); lowest observed free space was 6.4 GiB, above the 5 GiB floor.
- Final scoped cleanup removed `dist`, `.artifacts/derived-data`, and `.artifacts/package-staging`. The verified `rc.2` replacement removed the four superseded `rc.1` files and retained only the 11 MiB current CI-built PKG/ZIP and checksum files; no duplicate candidate copy remains.
- Final free disk after `rc.2` cleanup: 10 GiB. The pre-existing installed Parent Controller and Hub processes were not started by Stage 05 and were deliberately preserved. No Stage 05 process remains. No simulator/emulator was used.

## Failure evidence to collect

- `parental-control-agentctl status`
- `launchctl print system/com.bilalalissa.ParentalControlAgent.daemon`
- `/var/log/com.bilalalissa.ParentalControlAgent.daemon.log`
- `/Library/Application Support/ParentalControlAgent/Logs/agent.log*` after reviewing for family metadata
- Chrome or Edge version, extension ID/status screenshot, and extension service-worker error text without private URLs
- Exact browser/retention control state and message delivery state without copying private chat text, tab titles, origins, device identifiers, or network addresses
- macOS version, architecture, package/ZIP checksums, and whether notification permission, mute, or Focus was active
