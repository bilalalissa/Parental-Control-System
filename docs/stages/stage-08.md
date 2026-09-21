# STAGE-08 — Windows activity, browser extension, and chat

- Status: ready for developer retest
- Branch: `stage/08-windows-activity-browser-chat`
- Candidate: `0.8.0-rc.3` for Windows; RC2 controller and browser artifacts

## Objective and included scope

Extend the visible Windows x64 child endpoint with event-driven running/foreground application metadata, the shared visible Chromium extension through a Windows native-messaging host, text chat and notifications, request-more-time, parent-controlled collection switches, bounded retention, and controller UI compatibility. The Apple-silicon Parent Controller remains the local authority and all endpoint traffic continues over the authenticated LAN protocol.

Application observations contain only a display name, stable executable identity, optional bounded signing/publisher hashes, foreground state, and observation time. Browser observations contain at most 128 enrolled Chrome or Edge tab titles and query-free HTTP(S) origins. Chat is text-only, notifications reveal no message body, and the endpoint keeps at most 200 messages and 100 queued envelopes in DPAPI-protected state.

## Explicit exclusions

Stage 08 does not add Windows schedules, offline policy enforcement, app blocking, website blocking, lock, logoff, restart, shutdown, pre-logon control, PowerShell or arbitrary commands, hidden operation, window/page content, command lines, URL paths or queries, private tabs, browser traffic, forms, cookies, passwords, screenshots, clipboard, files, camera, microphone, or administrator resistance. Windows x86/ARM, a Windows VM on the development Mac, public relay, cloud accounts, production store publication, Authenticode credentials, and automatic release are excluded.

## Assumptions and platform boundary

- Supported target remains Windows 10 version 2004 or newer and Windows 11 on x64 hardware.
- The service is machine-wide; the visible ordinary-user UI and native host may submit metadata only from the active console session. Pairing still requires a visible adult administrator session.
- Running applications are inferred from visible top-level windows plus foreground/window events, with a bounded 15-minute reconciliation. No process command line, window title, file access, or kill API is used.
- Chrome and Edge require the separately loaded visible Manifest V3 extension and a machine-wide browser installation under Program Files. The MSI registers one exact native-host name and one stable extension origin, the service admits only the installed child UI/native-host executables from the active console session, and the native host accepts only the installed Chrome or Edge executable as its parent. Guest, private/incognito, per-user browser installations, unregistered, removed, or disabled profiles are outside coverage.
- The shared extension still contains the macOS website-policy code, but the Stage 08 Windows host supplies no website policy and the Windows endpoint does not advertise that capability.
- The MSI, extension ZIP, and controller DMG are unsigned developer-test candidates until production credentials/publication exist.

## Acceptance criteria

1. Foreground/window changes trigger bounded application updates and the exact Steam executable receives a stable `win32.steam.exe` identity rather than an unavailable identity.
2. Disabling app or browser sharing clears retained records and sends an empty authenticated delta; retention is limited to 1–30 days.
3. Chrome/Edge native messages are length-bounded, active-session-scoped, restricted to the installed native host launched by a machine-wide Chrome/Edge executable, registered by MSI, origin-bound to the stable extension ID, and sanitize URLs to HTTP(S) origins.
4. Chat, read receipts, notifications, parent edits/deletions, and one bounded request-more-time record work across reconnects with signed/replay-protected envelopes and bounded queues.
5. Capability negotiation advertises metadata/communication only and does not claim Windows schedules, app/website restrictions, signed policy, lock, or shutdown.
6. Windows unit/repository tests and native Windows CI cover privacy, bounds, compile, MSI install, health, host registration, repair/identity retention, uninstall, and resources.
7. One updated x64 MSI, one Chrome/Edge extension ZIP, and one Apple-silicon controller DMG are retained with SHA-256 files and honest signing status.
8. All project-started processes and Stage 08 build/package output are removed after verification; no Windows VM, container, simulator, duplicate checkout, or worktree is created.

## Resource and cleanup limits

Development started with 31 GiB free, a 113 MiB repository, and only the approved Stage 07 MSI/checksum plus an unrelated user `Cleaner.bat` in the release-candidate directory. Builds use one checkout and at most two workers. SwiftPM scratch is confined to `.artifacts/derived-data/stage-08`; Windows CI output is confined to `.artifacts/build/stage-08`; extension/controller packaging uses Stage 08 staging directories. The Stage 07 MSI is retained until its Stage 08 replacement passes native Windows CI. Cleanup deletes only these project-owned generated paths and retains the unrelated file.

## Build and physical verification

Windows x64 PowerShell:

```powershell
.\script\build_windows_release.ps1
.\script\test_windows_installer.ps1 -MsiPath ".artifacts\release-candidate\ParentalControlWindows-0.8.0-rc.3-x64.msi"
```

On macOS, run the repository and Swift tests, package `ParentalControlBrowserSharing-0.8.0-rc.2.zip`, and package `ParentalControlController-0.8.0-rc.2-arm64.dmg`. Physical testing must verify a standard Windows child account, application foreground transitions including Steam, Chrome and Edge profiles with private mode disabled, collection disable/clear, parent/child chat and notifications, request resolution, reconnect/reboot behavior, single-instance UI behavior, MSI repair, and uninstall.

## Rollback

Use **Apps > Installed apps > Parental Control Child > Uninstall** with administrator approval. This removes the service, visible UI, browser native host/registrations, startup entry, protected state, and bounded logs. Remove the visible extension from each tested browser profile separately. Reinstall the approved Stage 07 MSI only if a foundation-only rollback is required; uninstall creates a new endpoint identity, so fresh pairing is then required.

## Evidence status

RC3 addresses the reported restart, presence, duplicate-window, repair, and misleading enforcement
UI behavior without entering Stage 09. The controller now derives Online from a current authenticated
socket rather than a recent stale heartbeat. The Windows service reacts to network-availability and
address changes and continues bounded reconnect attempts after restart. The visible Windows app owns
one per-session mutex; its ordinary pairing window closes before the adult-authorized elevated copy
waits to acquire that ownership. Removing `ARPNOREPAIR` exposes Repair through classic Programs and
Features, while the documented elevated `msiexec /fa` path remains deterministic.

The controller now hides macOS-only schedule, immediate-action, application-policy, and website-policy
editors for a Windows endpoint and explains that enforcement starts in Stage 09. Stage 08 Windows
browser support remains opt-in tab-title/origin sharing for enrolled machine-wide Chrome or Edge
profiles. The extension and native host state clearly that website blocking is unavailable on Windows,
and Windows request approval delivers an acknowledgement without claiming enforced usage time.

RC3 passed the native Windows gate in GitHub Actions run
[`35665097245`](https://github.com/bilalalissa/Parental-Control-System/actions/runs/35665097245).
The Windows Server x64 runner passed 33/33 focused tests, built the service, visible UI and browser
host with zero errors, confirmed the MSI is Authenticode unsigned, then installed, queried, health-
checked, repaired and uninstalled it. Repair remained visibly registered and preserved the endpoint
identity. The service used 42,156,032 bytes working set and 11,423,744 bytes private memory; the
installed payload measured 199,601,947 bytes.

The controller/extension gate passed in GitHub Actions run
[`35665097431`](https://github.com/bilalalissa/Parental-Control-System/actions/runs/35665097431):
55 Swift Testing tests plus four XCTest tests passed, the extension archive validated, the controller
DMG checksum validated, and the app passed strict bundle verification with an honest ad-hoc signature.
The Stage 06E regression gate also passed in run
[`35665097301`](https://github.com/bilalalissa/Parental-Control-System/actions/runs/35665097301).
Repository/cleanup contracts and GitGuardian passed. Locally, 75/75 runnable repository tests passed
with one PowerShell-only test skipped; 33/33 Windows tests and targeted Windows App, Service and
BrowserHost builds passed. The local Command Line Tools Swift compiler/SDK versions are mismatched,
so local Swift compilation could not start; the clean native macOS CI result is the compile/test
evidence for this candidate.

Retained release candidates are:

- `ParentalControlWindows-0.8.0-rc.3-x64.msi` — 62,841,093 bytes — SHA-256
  `d383683b7565b15e00f55917b60bc8f909011cca6b39a388f0ee0aee0a84920f` — Authenticode unsigned.
- `ParentalControlBrowserSharing-0.8.0-rc.2.zip` — 26,199 bytes — SHA-256
  `6c41d778ae4ddc3f0cd79fcb8f535c592a418e8eb7f43004bdc1766b473fb77c` — unsigned archive.
- `ParentalControlController-0.8.0-rc.2-arm64.dmg` — 3,971,779 bytes — SHA-256
  `e67eee831f003dea1017be5d13cb6c0e478455006d3b21bc4deca59f0ac69886` — ad-hoc test build.

The superseded Windows RC2, controller RC1, locally packaged extension copy, stale extracted app and
temporary CI downloads were removed only after the new candidates passed verification. The unrelated
user `Cleaner.bat` remains untouched. This retest started with 18 GiB free, a 102 MiB repository and
73 MiB of retained files. Project-owned temporary output peaked at 526 MiB. After cleanup, 18 GiB
remains free, the repository is 94 MiB, and the release-candidate directory is 64 MiB including the
unrelated file. No project-started build, test, watcher or CI-watch process remains; the user's
pre-existing installed Parent Controller and editor language/build hosts were left untouched. No VM,
container, simulator or emulator was used. No approval, merge, release, or later-stage progress is
claimed.

On an Intel macOS child, the fixed readiness command reports `screenLock delay is immediate`, which
satisfies that prerequisite, but Stage 08 does not change or package the previously approved
`0.6.5-rc.10` macOS child endpoint. Any child-side correction still requires concrete child status
evidence and an explicit scope amendment.
