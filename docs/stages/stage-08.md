# STAGE-08 — Windows activity, browser extension, and chat

- Status: changes requested
- Branch: `stage/08-windows-activity-browser-chat`
- Candidate: `0.8.0-rc.2` for Windows; unchanged RC1 controller and browser artifacts

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
.\script\test_windows_installer.ps1 -MsiPath ".artifacts\release-candidate\ParentalControlWindows-0.8.0-rc.2-x64.msi"
```

On macOS, run the repository and Swift tests, package `ParentalControlBrowserSharing-0.8.0-rc.1.zip`, and package `ParentalControlController-0.8.0-rc.1-arm64.dmg`. Physical testing must verify a standard Windows child account, application foreground transitions including Steam, Chrome and Edge profiles with private mode disabled, collection disable/clear, parent/child chat and notifications, request resolution, reconnect/reboot behavior, MSI repair, and uninstall.

## Rollback

Use **Apps > Installed apps > Parental Control Child > Uninstall** with administrator approval. This removes the service, visible UI, browser native host/registrations, startup entry, protected state, and bounded logs. Remove the visible extension from each tested browser profile separately. Reinstall the approved Stage 07 MSI only if a foundation-only rollback is required; uninstall creates a new endpoint identity, so fresh pairing is then required.

## Evidence status

The initial automated verification passed, but developer physical testing reported two failures.
The supplied Windows verbose installer log proves that the x64 MSI was elevated on Windows 11 Pro
x64 and installed the automatic LocalSystem service. The service then failed during startup because
an existing machine state could not be decrypted by DPAPI (`CryptographicException: The data is
invalid` in `DpapiSecretProtector.Unprotect`), so Windows Installer displayed its generic error 1920
privileges text. RC2 limits recovery to that DPAPI failure: it preserves one unreadable ciphertext
as `endpoint.dat.unreadable` under the existing SYSTEM/Administrators-only data directory, creates
a fresh unpaired device identity, records a redacted recovery event, and requires fresh explicit
pairing. Valid state remains unchanged, decryptable malformed state still fails closed, and a failed
replacement restores the original unreadable file. Windows CI must reproduce this exact preseeded
state during native MSI install/repair/uninstall before RC2 is ready for retest.

On an Intel macOS child, the fixed readiness command reports `screenLock delay is immediate`, which
satisfies that prerequisite, but the child status evidence for app version, helper/session health,
signed-policy decision/action, Secure Lock readiness and the last lock result is still required.
The Stage 08 macOS artifact is the Parent Controller only; Stage 08 neither changed nor packages the
previously approved `0.6.5-rc.10` macOS child endpoint, so a child-side correction requires concrete
child status evidence and an explicit scope amendment before producing another macOS child package.
No approval, merge, release, or retest readiness is claimed.
