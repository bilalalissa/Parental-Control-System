# Parental Control System

A transparent, local-first parental-control system for families managing devices they own or lawfully administer.

> [!IMPORTANT]
> **Stages 00–06 are merged; STAGE-06A `0.6.1-rc.5` is approved and awaiting a separate merge command; STAGE-07 has not begun.** Stage 06A documents the manual-MDM feasibility result and adds a transition build that distinguishes active-session enforcement from unconfigured managed pre-login enforcement. It creates no external account or enrollment. See [Stage status](docs/stages/stage-status.json).

## Product direction

The planned system has a native Apple-silicon macOS Parent Controller plus visible child endpoints for macOS, Windows, and iPadOS. Desktop devices communicate directly with the controller over an authenticated local network connection and enforce the last valid signed policy while offline. A public relay, hosted database, SaaS telemetry, and mandatory cloud account are outside stages 00–12. Stage 06A is an optional bounded feasibility exception with a local transition installer; it does not make third-party MDM part of the local-first core.

The project is intentionally visible and bounded. It will not implement hidden installation, keylogging, screenshots, camera or microphone capture, message or file reading, TLS interception, private APIs, security bypasses, or arbitrary remote command execution.

## Platform truth

| Capability | macOS endpoint | Windows endpoint | Standard iPadOS app |
| --- | --- | --- | --- |
| Visible child UI | Stage 03 candidate | Planned | Planned |
| Local policy enforcement | Stage 06 candidate | Planned | Planned through Family Controls APIs |
| Foreground/running apps | Stage 04 candidate (names/bundle IDs only) | Planned | Not available |
| Browser-tab metadata | Stage 05 visible Chrome/Edge/Arc extension | Visible extension planned | Not available |
| Reliable uptime or login state | Stage 04 candidate | Planned | Not available |
| Text chat and announcements | Stage 04 candidate | Planned | While app is active in a later stage |
| Lock/logoff/restart/shutdown | Stage 06 public macOS mechanisms with confirmation for high-impact actions | Supported APIs only | Not available to a normal app |
| Presence | Authenticated heartbeat | Authenticated heartbeat | Approximate/best effort |

The full capability contract is in [the capability matrix](docs/architecture/capability-matrix.md).

## Current controller and macOS endpoint

The native Apple-silicon controller in [`apps/controller-macos`](apps/controller-macos/) includes:

- Dashboard, device detail, schedule editor, chat, audit, storage, and settings shells built with SwiftUI
- Direct chat, family group chat, and all-child-device announcements with explicit recipient lists and delivery state
- One canonical list of real paired devices; synthetic macOS, Windows, and iPad records remain test-only fixtures
- Truthful paired-device capability displays; `Offline` is never presented as proof of power-off
- Deterministic schedule validation with lock as the default restriction
- A visible Service Management start-at-login option and an original generated app icon
- A local hub helper with Bonjour discovery, TLS 1.3 certificate pinning, Ed25519-signed protocol envelopes, one-time pairing, adaptive heartbeats, delta snapshots, receipts, and bounded SQLite state
- HMAC-authenticated loopback IPC bootstrapped with an ephemeral in-memory session key, so routine launch and hub controls do not require Keychain password entry
- A visible ordinary-process mock-agent CLI for safe pairing and concurrency tests

Stage 06 keeps all communication and policy authority local-first. The controller signs per-device schedules; the endpoint verifies the paired controller key, rejects tampering and version replay, stores the accepted policy in a root-protected location, and evaluates it every 15 seconds through an event-driven scheduler. Typed announcements are still spoken locally without recording, uploads, or attachments. Arbitrary commands remain unavailable.

Stage 06A found that Apple's macOS Login Window `AllowList` and `DenyList` apply only to network and mobile accounts, not an ordinary local child account, and provide no weekly schedule or automatic expiry. Broadly disabling local logins could also deny the adult recovery administrator. The proposed manual-MDM mechanism is therefore a documented no-go before enrollment; no MDM account, APNs certificate, API key, profile, or device record is created.

The `0.6.1-rc.5` transition build keeps the Stage-06 enforcement behavior and pairing format unchanged. Both visible apps distinguish signed schedule enforcement after a child session becomes active from managed pre-login enforcement, which remains explicitly not configured. The authenticated GUI helper marks startup, wake/unlock, and public Screen Saver termination as activation boundaries, uses a fresh public Screen Saver instance for each lock request, and performs a bounded active-session re-lock check only while a recent signed-policy evaluation remains blocked and its next allowed boundary has not arrived. The child Status view scrolls and separately reports scheduled-window time, daily active-use quota, approved bonus time, temporary allowance, effective remaining time, and the rule that limits it first. It also exposes signed-policy time zone and policy-local time so system-time mismatches are visible. The endpoint announces a versioned `session-enforcement` capability without claiming or enabling managed identity.

The Stage 06A package remains one selectable clean-install and in-place-upgrade installer. It installs the Apple-silicon Parent Controller by default; on a child Mac, choose **Customize**, deselect **Parent Controller**, and select **Child Endpoint**. The universal `arm64`/`x86_64` endpoint has a visible read-only policy dashboard, boot daemon, login helper, authenticated XPC, protected configuration/policy/queue files, Keychain-backed identity, adaptive delta heartbeats, bounded/redacted logs, native browser host, and administrator uninstaller. Lock starts the system screen saver and preserves open applications. Logoff, restart, and shutdown use documented loginwindow confirmation dialogs and never force-terminate applications; unsaved-work prompts remain under macOS control.

To test one mock after installing the developer candidate:

1. On the dashboard, choose **Create one-time pairing code**, then **Copy pairing token**.
2. In Terminal, set `TOKEN` to the copied value and run:

   ```sh
   "/Applications/Parental Control.app/Contents/Helpers/ParentalControlMockAgent" \
     --invitation "$TOKEN" --id mock-one --name "Mock One"
   ```

The command starts one visible, unprivileged mock process. Stop it with `Control-C`. Each additional mock needs a newly generated one-time token and a unique `--id`. The mock reports only synthetic presence/delta data and performs no monitoring or enforcement.

## Stage 00 foundation

- Canonical JSON Schemas for the [wire protocol](packages/protocol/) and [policy model](packages/policy-engine-spec/)
- Synthetic protocol fixtures and policy golden vectors in [packages/test-fixtures](packages/test-fixtures/)
- Dependency-free contract and cleanup safety tests
- Architecture, threat model, capability, privacy, and security documentation
- Resource-aware CI and dry-run-first cleanup tools for macOS/Linux and Windows
- GitHub issue and pull-request templates, contribution guidance, and stage tracking

## Quick start

Repository checks require Node.js 22 or newer and have no third-party package dependencies:

```sh
npm test
npm run cleanup:list
```

Building the Stage 06A macOS transition candidate requires macOS 14 or newer with Xcode and Swift installed. Build work is constrained to two workers and one project-owned output tree:

```sh
swift format lint --recursive apps/controller-macos/Sources apps/controller-macos/Tests
swift test --package-path apps/controller-macos --jobs 2
swift format lint --recursive agents/endpoint-macos/Sources agents/endpoint-macos/Tests
swift test --package-path agents/endpoint-macos --jobs 2
./script/build_endpoint_app.sh Release
./script/build_and_run.sh
./script/package_endpoint_release.sh
```

The endpoint build compiles Apple-silicon and Intel sequentially, combines each executable once, verifies both slices, and deletes the per-architecture trees. `build_and_run.sh` launches the uninstalled child dashboard for UI inspection; protected XPC and enforcement require the installed daemon/helper. `package_endpoint_release.sh` creates the selectable Stage 06A `.pkg`; the already-installed browser extension does not need removal, reinstallation, or manual reload because its native host is updated in place. Builders default to ad-hoc app/helper signing for credential-free CI; a physical developer candidate can set `MACOS_SIGNING_IDENTITY` to one stable local Apple Development identity. The product package remains unsigned and not notarized.

Install the same package on the parent Mac with its default **Parent Controller** choice. On the child Mac, choose **Customize**, deselect **Parent Controller**, and select **Child Endpoint**. Confirm the endpoint service before pairing:

```sh
parental-control-agentctl status
```

Then create a one-time pairing invitation in the Parent Controller and run the typed administrator command below on the child. Restarting the daemon reads the protected invitation; the pairing code is removed after the controller accepts it.

```sh
sudo parental-control-agentctl pair --invitation "$TOKEN"
sudo launchctl kickstart -k system/com.bilalalissa.ParentalControlAgent.daemon
```

Uninstall with the visible bundled administrator script. This removes the app, launchd jobs, protected endpoint data, and endpoint Keychain item:

```sh
sudo "/Applications/Parental Control Child.app/Contents/Resources/uninstall.sh"
```

The cleanup command only lists repository-owned generated paths. Deletion requires an explicit command:

```sh
npm run cleanup:apply
```

On Windows PowerShell:

```powershell
.\tools\cleanup.ps1
.\tools\cleanup.ps1 -Apply
```

See [resource-safe development](docs/architecture/resource-development.md) for disk limits, constrained commands, exact cleanup behavior, and CI fallback.

## Architecture at a glance

The macOS controller is the policy authority. Each enrolled endpoint has its own identity, uses a TLS-protected authenticated channel, accepts only typed allowlisted commands, and reports capabilities rather than pretending all platforms behave alike. Controller data remains in local SQLite and secrets remain in platform secure storage. See the [architecture overview](docs/architecture/overview.md) and [threat model](docs/architecture/threat-model.md).

## Project workflow

Work advances one approved stage at a time. The current branch is expected to follow `stage/<stage-id>-<short-name>`, and later-stage work must wait for the exact approval described in [CODEX_MASTER_PROMPT.md](CODEX_MASTER_PROMPT.md). Security reports should follow [SECURITY.md](SECURITY.md); contributions should follow [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Licensed under the [MIT License](LICENSE).
