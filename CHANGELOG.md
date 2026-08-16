# Changelog

All notable approved stage deliverables are recorded here. The project uses staged release-candidate versions; approval does not imply merge or public release.

## 0.5.0-rc.2 — 2026-08-16

Status: **STAGE-05 changes requested**

- Adds a short system alert confirmation after the parent or child sender successfully queues a chat message.
- Registers foreground notification delegates in both the visible child app and its logged-in helper so permitted arrival notifications can present their default sound while the app is open.
- Adds a persistent red unread counter to the Parent Controller Chat sidebar item and the child Chat tab, derived only from incoming messages that have not reached the Read state.
- Preserves the confirmed automatic child Online/Offline status behavior without changing presence or reconnect logic.

## 0.5.0-rc.1 — 2026-08-16

Status: **STAGE-05 ready for developer test**

- Adds one shared visible Manifest V3 Chrome/Edge extension and one packaged ZIP with a stable extension identity and explicit minimal permissions.
- Adds a universal macOS native-messaging host with exact extension-origin, browser signing/path, installed-host signing/path, and authenticated XPC checks.
- Adds opt-in, bounded, short-retention tab-title and query-free-origin metadata; private tabs, page content, paths, queries, fragments, forms, cookies, passwords, and network traffic remain excluded.
- Adds generic system-controlled arrival sound for both receiver directions and explicit conversation-visible Read receipts, while preserving content-free logs, audit rows, and notification diagnostics.
- Adds controller/child disclosures and controls, local SQLite migration/pruning, protocol types, installer/uninstaller integration, and privacy/security regression coverage.

## 0.4.0-rc.5 — 2026-08-16

Status: **STAGE-04 merged**

- Refreshes derived Online/Offline presence on the parent every five seconds without requiring UI interaction.
- Signals the daemon immediately when an established child connection closes, then preserves the bounded three-attempt, two-second retry sequence and 60-second cooldown.
- Adds deterministic regression coverage for parent presence publication and the sleep/wake reconnect policy.
- Approved by the developer with the exact command `APPROVED: STAGE-04 0.4.0-rc.5` and separately authorized for merge with `MERGE` on 2026-08-16; no release is implied.

## 0.4.0-rc.4 — 2026-08-15

Status: **STAGE-04 ready for developer retest**

- Replaced the visible child app's actor-isolated UserNotifications completion handler with the concurrency-safe async authorization API, preventing the confirmed Intel launch crash.
- Added source regression coverage and an installed-app CI launch-survival smoke test.

## 0.4.0-rc.3 — 2026-08-15

Status: **STAGE-04 ready for developer retest**

- Corrected the installed child app's authenticated XPC path validation to accept the root-protected signed application bundle path returned by macOS as well as its canonical inner executable path.
- Added regression coverage for both valid child code paths while continuing to reject paths outside the installed application.

## 0.4.0-rc.2 — 2026-08-15

Status: **STAGE-04 ready for developer retest**

- Restored automatic TLS-pinned endpoint reconnection after the parent controller restarts by migrating paired devices to a stable LAN service port.
- Reloaded and restarted the logged-in activity helper during upgrades, added bounded three-attempt startup, and configured launchd to recover it after abnormal termination.
- Replaced the inaccessible paired-device disclosure row with a dedicated accessible expansion button and activity-sharing control.

## 0.4.0-rc.1 — 2026-08-15

Status: **STAGE-04 ready for developer test**

- Added event-driven macOS foreground/running application metadata limited to names, bundle identifiers, state, and time; collection can be disabled and retention is configurable from one to thirty days.
- Added authenticated two-way direct chat, family group chat, parent announcements to all paired child devices, generic child notifications, and request-more-time.
- Added bounded persistent controller/endpoint offline queues, queued/sent/delivered/read/failed states, thirty-day chat pruning, audit metadata without message contents, and protected local storage permissions.
- Updated both visible SwiftUI apps and replaced the prior selectable package with one universal `0.4.0-rc.1` candidate.
- Browser tabs, schedule enforcement, remote actions, public relay, and cloud storage remain excluded.

## 0.3.0-rc.2 — 2026-08-15

Status: **STAGE-03 merged**

- Added the visible universal macOS Child Endpoint, boot daemon, login helper, authenticated protected XPC, explicit pairing, status/uptime/session/network/health reporting, bounded logs, installer, and uninstaller.
- Added the selectable combined package with the Parent Controller as the default role and the Child Endpoint available through Customize.
- Added bounded three-attempt startup and packaging retries with short delays and confirmed physical-device pairing, revocation, unpairing, re-pairing, and reduced routine Keychain prompts.
- App activity, browser tabs, chat, and enforcement remained excluded from Stage 03.

## 0.2.0-rc.1 — 2026-08-13

Status: **STAGE-02 merged**

- Added the local controller hub, one-time pairing, authenticated IPC, pinned TLS WebSocket transport, signed/replay-protected protocol envelopes, persistent bounded device state, receipts, and lightweight concurrent mock-agent coverage.
- Added Bonjour LAN discovery, adaptive heartbeats, delta snapshots, honest offline/last-seen behavior, revoke/unpair, and parent-process lifecycle management.
- Replaced the persistent GUI-to-hub IPC credential with a per-launch in-memory key transferred through a private pipe, preventing routine Keychain password prompts while retaining long-lived private identities in Keychain.
- Added an arm64, ad-hoc-signed developer-test DMG and protocol, persistence, IPC, transport, concurrency, resource, packaging, and lifecycle evidence.
- No privileged endpoint behavior, real monitoring, enforcement, public relay, container, or virtual machine is included.

## 0.1.0-rc.2 — 2026-08-13

Status: **STAGE-01 merged**

- Added the native Apple-silicon SwiftUI Parent Controller shell with dashboard, device, schedule, chat, audit, storage, and settings surfaces.
- Added local SQLite migrations, bounded synthetic fixtures, deterministic schedule validation, and automated capability/accessibility tests.
- Added truthful macOS, Windows, and standard-iPad capability displays without endpoint traffic, monitoring, or enforcement.
- Added a supported Service Management start-at-login control, an original canonical vector icon, constrained build/run scripts, and path-scoped macOS CI.
- Added an arm64, ad-hoc-signed developer-test DMG with SHA-256 verification.
- Added local-preview family group chat and all-device parent announcements in response to developer feedback.
- Replaced the original shelter icon with a new connected-family constellation design.

This release candidate is not Developer ID signed or notarized and contains no Stage 02 pairing or device-control behavior.

## 0.0.1-rc.1 — 2026-08-13

Status: **STAGE-00 approved**

- Established the local-first monorepo foundation and project documentation.
- Added canonical protocol and policy JSON Schemas with synthetic fixtures and deterministic golden-vector tests.
- Added architecture, capability, privacy, security, threat-model, contribution, ADR, and icon-design guidance.
- Added dry-run-first repository cleanup tools for POSIX and Windows, plus safety tests.
- Added resource-aware GitHub CI with minimal permissions, pinned actions, cancellation, and short failure-artifact retention.
- Added the MIT License, README, GitHub issue templates, pull-request template, and stage tracker.

No application runtime, privileged service, policy enforcement, installer, relay, MDM implementation, or production artifact is included in this version.
