# STAGE-07 — Windows x64 Child Agent foundation

- Status: feedback repair in progress
- Branch: `stage/07-windows-endpoint-foundation`
- Candidate: `0.7.0-rc.2`

## Objective and included scope

Deliver the first visible Windows x64 child endpoint: one automatic Windows service, one ordinary per-user WPF dashboard, authenticated and authorization-gated named-pipe IPC, explicit administrator pairing, the existing pinned-TLS and Ed25519-signed LAN protocol, adaptive bounded status snapshots, protected configuration, bounded redacted logs, a distinct generated icon, and one uninstallable per-machine MSI.

The endpoint reports only its device name/model, operating system, architecture, uptime/boot time, coarse session state, service health, and bounded private/link-local addresses from physical Ethernet or Wi-Fi interfaces. The Parent Controller remains the local authority. There is no relay, account, hosted database, SaaS telemetry, or public Internet dependency at runtime.

## Explicit exclusions

Application activity, app restrictions, browser extensions or browser data, website rules, schedules, offline enforcement, lock/logoff/restart/shutdown actions, chat, announcements, arbitrary commands, PowerShell execution, screenshots, clipboard, files, page content, forms, cookies, passwords, camera, microphone, and hidden operation are not included. Stage 07 does not claim those later capabilities.

Windows x86/ARM, macOS changes, iPadOS, a Windows VM on the development Mac, production code signing, and an automatic public release are excluded. An authorized local administrator can control or remove the endpoint; the product does not attempt to defeat one.

## Assumptions and platform boundary

- Supported target: Windows 10 version 2004 or newer and Windows 11, x64 only.
- Installation, repair, pairing, and uninstall require an adult administrator and normal Windows consent.
- The visible child app runs without elevation for read-only status. Pairing relaunches the same visible UI through Windows `runas`; the invitation is never placed on the command line.
- The service uses documented Service Control Manager, WTS session notifications, DPAPI machine protection, .NET named pipes, networking, and registry APIs.
- The service runs as LocalSystem because the installer-created protected state is machine-wide. Its protocol and IPC surfaces remain typed and allowlisted; it exposes no process-launch or command interface.
- The x64 MSI contains the .NET 8 runtime so the child PC does not require a separate runtime download. The two executables share one installed runtime payload to avoid duplication.
- MSI and executables are unsigned test candidates until production certificate credentials exist. No signing success is claimed.

## Acceptance criteria

1. A clean Windows x64 install starts exactly one automatic service and installs one visible child dashboard with Start-menu and sign-in entries.
2. Standard users can read status over the ACL-protected named pipe but cannot pair; administrator pairing consumes a valid, bounded, unexpired invitation and verifies the controller certificate fingerprint and Ed25519 messages.
3. Identity is generated once, DPAPI-protected at machine scope, retained through MSI repair/in-place upgrade, and removed by explicit uninstall.
4. Protocol size, timestamp, signature, replay, sequence, invitation, IPC, capability, network-address, and persistence boundaries have automated tests.
5. Status uses adaptive event/heartbeat work, bounds interfaces/addresses/messages/logs, and reports `Offline` without inferring power state.
6. Capability negotiation advertises only the eight Stage 07 status capabilities. Unsupported controller commands are not executed.
7. One Windows CI job builds and tests with at most two workers, then performs clean install, service/status query, repair with identity retention, uninstall, filesystem cleanup, and bounded resource measurement.
8. Exactly one x64 MSI and SHA-256 file are retained as the release candidate. Authenticode status is reported honestly.

## Resource and cleanup limits

Development began with 39 GiB free and a 37 MiB repository. No VM, container, simulator, duplicate checkout, or worktree is used. Local builds are limited to two workers and `.artifacts/build/stage-07`; dependency downloads use `.artifacts/nuget/stage-07`. Before handoff, project-started processes and generated build/dependency output are removed, free disk is remeasured, and only the current MSI/checksum may remain locally.

## Implementation notes

- Developer feedback on RC1 exposed a wire-upgrade mismatch: the Windows client requested `/` without the required WebSocket subprotocol, while the controller accepts only `/hub` with `parental-control.v1`. RC2 uses the canonical path and subprotocol, accepts the controller's binary receipt frames, and reports a bounded actionable pending-pairing failure instead of masking it as `Not paired`.
- `.NET 8` WPF provides the visible UI; the service uses `ServiceBase` and event-driven session notifications.
- Bouncy Castle provides Ed25519 interoperability with the existing Swift/CryptoKit wire identity. The exact 2.7.0 dependency is locked.
- Local IPC is length-prefixed, limited to 16 KiB, protected by Windows pipe ACLs, and additionally checks the impersonated caller's administrator role for pairing.
- LAN messages use the canonical 64 KiB envelope, one pinned TLS WebSocket, sorted JSON signing data, monotonic persisted sequences, a 256-ID replay window, and bounded heartbeat intervals.
- Only private/link-local IPv4/IPv6 addresses and informational physical-interface MAC values are considered. Public and non-Ethernet/Wi-Fi interfaces are discarded before transport.
- Logs contain bounded event names and short error classes, rotate at 5 MiB, and redact URL-shaped detail. They do not contain invitations, keys, addresses, user names, or message bodies.

## Build and hardware verification

Run on Windows x64 PowerShell from the repository root:

```powershell
.\script\build_windows_release.ps1
.\script\test_windows_installer.ps1 -MsiPath ".artifacts\release-candidate\ParentalControlWindows-0.7.0-rc.2-x64.msi"
```

The second command intentionally installs, repairs, and removes the test endpoint and its protected local state. Use it only on the intended test PC or ephemeral Windows CI host. Physical parent/child pairing and visible UI review remain developer acceptance gates after the automated candidate passes.

## Rollback and uninstall

Use **Apps > Installed apps > Parental Control Child > Uninstall** and approve the administrator prompt. The MSI stops and removes the service, binaries, startup entry, protected endpoint configuration, and bounded logs. Reinstalling after uninstall creates a new endpoint identity and therefore requires a new one-time invitation.

## Evidence status

Local macOS cross-target compilation covers the shared core, Windows service, and WPF source with zero warnings. All 24 Windows-core tests pass, including the deterministic Swift/Windows signing vector; the dependency-free repository suite reports 75 passed and one expected platform skip. The local WiX compiler cannot execute because the development Mac has an incompatible legacy x86_64 .NET 6 host, so Windows CI is the authoritative MSI build/install environment.

Commit `2fffa4820418355a51000c511405db40d76c4304` passed the [native Windows x64 build, Authenticode inspection, install, authenticated status, repair/identity-retention, uninstall, artifact upload, and scoped cleanup](https://github.com/bilalalissa/Parental-Control-System/actions/runs/34911829035). The same commit passed [repository contracts and POSIX/Windows cleanup checks](https://github.com/bilalalissa/Parental-Control-System/actions/runs/34911829007), the [macOS cross-language signature check](https://github.com/bilalalissa/Parental-Control-System/actions/runs/34911829011), and secret scanning.

The verified unsigned MSI is 62,713,118 bytes with SHA-256 `0dff66db9e10d4b7b7458099a3cc6bb3f7a541ca0f8e9c6555fcfab3e6f13ecd`. On the disposable Windows 2025 CI host, the installed service used a 39,100,416-byte working set and 10,002,432 bytes of private memory; the self-contained installed payload was 199,303,503 bytes. Physical Windows UI, parent/child pairing, reboot/login startup, network transition, and Windows 10 testing remain developer gates.

Final local cleanup removed 11 repository-owned build/dependency paths and the verified temporary download. The superseded local Stage 06E RC10 copies were removed after the Stage 07 checksum matched; RC10 remains recoverable from its published GitHub release. Cleanup left 37 GiB free, a 113 MiB repository, one 60 MiB MSI plus its checksum, no Stage 07 process, and no simulator, emulator, VM, container, duplicate checkout, or worktree.
