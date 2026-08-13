# Parental Control System

A transparent, local-first parental-control system for families managing devices they own or lawfully administer.

> [!IMPORTANT]
> **Stage 00 is merged and the Stage 01 feedback revision is in progress.** The controller remains a local, mock-data macOS shell; it does not yet pair with devices or enforce policy. See [Stage status](docs/stages/stage-status.json).

## Product direction

The planned system has a native Apple-silicon macOS Parent Controller plus visible child endpoints for macOS, Windows, and iPadOS. Desktop devices communicate directly with the controller over an authenticated local network connection and enforce the last valid signed policy while offline. A public relay, hosted database, SaaS telemetry, and mandatory cloud account are outside stages 00–12.

The project is intentionally visible and bounded. It will not implement hidden installation, keylogging, screenshots, camera or microphone capture, message or file reading, TLS interception, private APIs, security bypasses, or arbitrary remote command execution.

## Platform truth

| Capability | macOS endpoint | Windows endpoint | Standard iPadOS app |
| --- | --- | --- | --- |
| Visible child UI | Planned | Planned | Planned |
| Local policy enforcement | Planned | Planned | Planned through Family Controls APIs |
| Foreground/running apps | Planned | Planned | Not available |
| Browser-tab metadata | Visible extension only | Visible extension only | Not available |
| Reliable uptime or login state | Planned | Planned | Not available |
| Lock/logoff/restart/shutdown | Supported APIs only | Supported APIs only | Not available to a normal app |
| Presence | Authenticated heartbeat | Authenticated heartbeat | Approximate/best effort |

The full capability contract is in [the capability matrix](docs/architecture/capability-matrix.md).

## Current Stage 01 shell

The native Apple-silicon controller preview in [`apps/controller-macos`](apps/controller-macos/) includes:

- Dashboard, device detail, schedule editor, chat, audit, storage, and settings shells built with SwiftUI
- Direct chat, family group chat, and all-child-device announcement previews with explicit recipient lists
- Local SQLite migrations and bounded synthetic macOS, Windows, and standard-iPad fixtures
- Truthful per-platform capability and limitation displays; `Offline` is never presented as proof of power-off
- Deterministic schedule validation with lock as the default restriction
- A visible Service Management start-at-login option and an original generated app icon

Pairing, real endpoint traffic, monitoring, policy enforcement, and remote actions are intentionally unavailable at this stage.

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

Building the Stage 01 controller requires Apple-silicon macOS 14 or newer with Xcode and Swift installed. Build work is constrained to two workers and one project-owned output tree:

```sh
swift format lint --recursive apps/controller-macos/Sources apps/controller-macos/Tests
swift test --package-path apps/controller-macos --jobs 2
./script/build_app.sh Release
./script/build_and_run.sh
./script/package_release.sh
```

The formatter checks style without changing files. `swift test` runs the controller unit tests. `build_app.sh` produces a local ad-hoc-signed app, `build_and_run.sh` rebuilds and launches it, and `package_release.sh` replaces the single retained Stage 01 DMG and SHA-256 checksum. For normal development, run the formatter and tests, then use `build_and_run.sh`; use `package_release.sh` only when preparing a release candidate. `build_app.sh` is a lower-level command and is not additionally required because both higher-level scripts call it. Ad-hoc signing is for developer testing only; the app is not Developer ID signed or notarized.

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
