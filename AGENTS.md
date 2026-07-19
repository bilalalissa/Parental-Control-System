# AGENTS.md — Parental Control System

## Source of truth

Before doing any work, read `CODEX_MASTER_PROMPT.md` completely. It defines the product scope, architecture, platform limitations, security rules, stage plan, acceptance criteria, release process, and required completion report.

This repository uses a strict stage gate. Work on only the stage named in `docs/stages/stage-status.json` or explicitly named by the developer. Never begin a later stage early.

## Stage workflow

For every stage:

1. Restate the stage objective, scope, exclusions, assumptions, and acceptance criteria.
2. Synchronize from `main` and create `stage/<stage-id>-<short-name>`.
3. Update the stage specification and status file.
4. Implement only the approved scope.
5. Add or update automated tests and documentation.
6. Run all relevant checks and record the exact commands/results.
7. Build honest developer artifacts for supported native platforms.
8. Publish artifacts with SHA-256 checksums and signed/unsigned status.
9. Push the branch and open a draft pull request.
10. Return the mandatory Stage Completion Report from `CODEX_MASTER_PROMPT.md`.
11. Stop at `AWAITING DEVELOPER TEST RESULT`.

Feedback must be fixed on the same stage branch/PR unless the developer explicitly instructs otherwise. Do not broaden scope while addressing feedback. Do not merge, release, or proceed without the exact approval commands defined in the master prompt.

## Platform truth

Never fake or overstate a capability.

- macOS endpoint: use public APIs, a visible app, supported Service Management/launchd mechanisms, authenticated IPC, and a universal Apple-silicon/Intel build.
- Windows endpoint: use a Windows Service, visible per-user UI, authenticated named pipes, documented Windows APIs, and an administrator installer.
- iPadOS standard app: use FamilyControls, DeviceActivity, ManagedSettings, ManagedSettingsUI, app extensions, APNs, and public Apple APIs only. It is not a persistent desktop agent. Do not claim current apps, browser tabs, reliable uptime, hardware MAC address, desktop login state, global logout, restart, or shutdown.
- Supervised iPad MDM is a separate optional stage and must not start without explicit approval.
- Desktop browser tabs require a separately installed, visible browser extension. Never inspect page content, forms, cookies, passwords, private/incognito sessions, or network traffic.

## Security and privacy

This is a transparent parental-control product, not covert surveillance software.

Never implement hidden installation, stealth persistence, keylogging, screenshots, camera/microphone recording, clipboard capture, password collection, file/message contents, TLS interception, private APIs, security bypasses, arbitrary remote shell/PowerShell/AppleScript execution, or unrestricted process launch.

Use:

- explicit pairing;
- per-device identity;
- TLS-protected transport;
- replay protection;
- secure platform key storage;
- signed/versioned policy;
- allowlisted commands;
- least privilege;
- authenticated local IPC;
- bounded/redacted logs;
- short configurable retention;
- visible endpoint disclosure;
- audited adult overrides.

The repository is public. Never commit real credentials, certificates, provisioning profiles, APNs/MDM keys, device identifiers, IP/MAC logs, chat data, private screenshots, or other personal data. Use examples and synthetic fixtures only.

A child desktop account must be a standard non-administrator account for meaningful enforcement. Do not attempt to defeat an authorized local administrator.

## Engineering rules

- Prefer native, supported platform frameworks.
- Record material design choices in ADRs.
- Keep privileged services narrow; UI processes must not run as root or LocalSystem.
- Do not add an arbitrary command executor.
- Do not disable tests to make CI pass.
- Do not claim checks passed unless they ran.
- Clearly separate local checks, CI checks, physical-device tests, and signing/entitlement blockers.
- Treat warnings as errors where practical.
- Add unit, integration, protocol-contract, policy-golden, security, and installer tests appropriate to the stage.
- Run formatting, linting, static analysis, dependency/secret/license scans, and SBOM generation for production stages.
- Keep commits focused and update installation, rollback, privacy, security, and release notes with behavior changes.

## Product behavior

- Show `Offline` and last-seen time for an unreachable device; do not infer power-off without a reliable shutdown event.
- Cache and enforce the last valid signed policy while a desktop endpoint is offline.
- Default enforcement action is lock, not shutdown.
- Warn before enforcement and protect unsaved work.
- Endpoint settings are read-only to the child. Changes require authenticated remote approval or a rate-limited local adult code; there is no default or master backdoor code.
- All high-impact actions must be authenticated, capability-checked, confirmed where appropriate, and audit logged.

## Current starting instruction

Unless the developer has approved and advanced the project, begin with `STAGE-00` only, as defined in `CODEX_MASTER_PROMPT.md`, and stop after its developer-test release candidate is ready.
