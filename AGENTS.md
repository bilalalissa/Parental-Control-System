# AGENTS.md — Parental Control System

## Source of truth

Before doing any work, read `CODEX_MASTER_PROMPT.md` completely. It defines product scope, platform limits, security, local-first architecture, low-resource requirements, stage gates, artifacts, cleanup, feedback, and approval.

Work only on the stage named by the developer or by `docs/stages/stage-status.json`. Never begin a later stage early.

When instructions conflict, use this order:

1. Safety, legality, privacy, and platform rules.
2. Security and data integrity.
3. The approved stage scope.
4. Low-disk, low-memory, and local-first requirements.
5. Convenience.

## Mandatory stage flow

For every stage and every retest:

1. Restate objective, included scope, exclusions, assumptions, acceptance criteria, and resource limits.
2. Inspect Git state, free disk, repository size, project-owned build output, and project-started processes.
3. State the smallest build/test plan and exact safe-cleanup plan.
4. Create or continue `stage/<stage-id>-<short-name>`.
5. Implement only the approved scope and reuse canonical source files.
6. Run checks from lightest to heaviest with constrained concurrency.
7. Produce one honest release-candidate installer/artifact per affected platform.
8. Generate SHA-256 checksums and state signing/entitlement status.
9. Stop all project processes and clean temporary project-owned output.
10. Re-measure free disk and report retained files/processes/simulator state.
11. Push the branch and open or update one draft pull request.
12. Return the exact Stage Completion Report from the master prompt.
13. Stop at `AWAITING DEVELOPER TEST RESULT`.

Feedback remains on the same branch and pull request. Replace the prior local RC after the new artifact is verified; do not accumulate candidates. Do not merge, release, or proceed without the exact developer commands in the master prompt.

## Non-negotiable resource rules

- Keep at least 5 GiB free on the development volume. Do not begin a heavy local build that could cross that floor.
- Use one checkout, one active stage branch, one platform build directory, one simulator at most, and one current local RC.
- Default to one or two build workers.
- Prefer unit/protocol tests before UI, simulator, installer, or full integration tests.
- Do not create VMs, containers, new simulator runtimes, duplicate clones, or Git worktrees without explicit approval.
- Never create a Windows VM on the low-space Mac by default; use Windows hardware or CI.
- Shut down simulators, mock agents, watchers, test hosts, dev servers, browser drivers, and log streams immediately after their check.
- Delete only repository-owned build output. Never delete unrelated caches, simulators, files, or repositories.
- Never run `git clean -fdx` or broad unscoped recursive deletion without explicit approval.
- Do not commit Derived Data, `.build`, `bin`, `obj`, publish output, `node_modules`, archives, installers, logs, diagnostics, test results, simulator data, or dependency caches.
- Do not retain duplicate `.app`, `.pkg`, `.dmg`, `.zip`, `.xcarchive`, `.ipa`, or `.msi` copies.
- Use one canonical protocol, policy specification, fixture set, and icon source. Link or generate; do not copy.
- Update existing documents rather than creating duplicate reports or READMEs.
- Do not create future empty directory trees or placeholder files solely to keep directories.
- If local capacity is insufficient, run the platform build in configured CI or report it blocked. Never fake success.

## Local-first product rules

- The Apple-silicon Parent Controller is the local authority.
- Core desktop pairing, status, policy, commands, and chat operate directly over the authenticated LAN.
- Controller data stays in local SQLite; secrets stay in Keychain.
- Endpoints cache and locally enforce the last valid signed policy.
- No public relay, hosted database, SaaS telemetry, or mandatory cloud account in stages 00–12.
- APNs is permitted only for honest iPad notification behavior; iPad schedule enforcement must use supported local Apple frameworks.
- A relay is optional, separately approved work. Local operation must continue without it.

## Platform truth

- Parent Controller: native Swift/SwiftUI on Apple silicon.
- macOS endpoint: visible universal Apple-silicon/Intel app, supported launchd/Service Management startup, authenticated IPC, public APIs, administrator installer/uninstaller.
- Windows endpoint: automatic service, visible per-user UI, authenticated named pipes, documented APIs, administrator MSI; build on Windows hardware or CI.
- iPadOS: FamilyControls, DeviceActivity, ManagedSettings, ManagedSettingsUI, app extensions, Keychain, App Group, and public APIs only. It is not a persistent desktop agent and cannot truthfully report current apps/tabs, hardware MAC, reliable uptime, desktop login state, global logout, restart, or shutdown.
- Supervised iPad MDM is optional and requires explicit approval.
- Browser tabs require a separately installed visible extension. Never inspect page content, forms, cookies, passwords, private sessions, or network traffic.

## Security and transparency

This is visible parental-control software, not covert surveillance.

Never implement hidden installation, stealth persistence, keylogging, screenshots, camera/microphone recording, clipboard capture, password/content collection, TLS interception, private APIs, exploits, security bypasses, arbitrary shell/PowerShell/AppleScript execution, unrestricted process launch, or a universal override code.

Use explicit pairing, per-device identity, TLS-protected transport, replay protection, secure key storage, signed/versioned policy, allowlisted commands, least privilege, authenticated IPC, bounded/redacted logs, short retention, visible disclosure, and audited adult overrides.

The repository is public. Never commit real secrets, certificates, profiles, APNs/MDM keys, family device identifiers, IP/MAC logs, chat data, or private screenshots.

A child desktop account must be a standard non-administrator account. Do not attempt to defeat an authorized local administrator.

## Product behavior

- Display `Offline` plus last-seen time; do not infer power-off.
- Default enforcement is lock, not shutdown.
- Warn before enforcement and protect unsaved work.
- Child settings are read-only. Changes require authenticated remote approval or a rate-limited local adult code; OS administrator authorization still applies where required.
- All high-impact actions are authenticated, capability-checked, confirmed where appropriate, and audited.
- Runtime collection and queues are event-driven, bounded, pruned, and resource-measured.

## Current starting instruction

Unless the developer has approved and advanced the project, execute `STAGE-00` only, including the resource-safe `.gitignore`, cleanup scripts, CI controls, and resource evidence required by `CODEX_MASTER_PROMPT.md`. Then stop.