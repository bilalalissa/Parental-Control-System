# Changelog

All notable approved stage deliverables are recorded here. The project uses staged release-candidate versions; approval does not imply merge or public release.

## 0.2.0-rc.1 — 2026-08-13

Status: **STAGE-02 ready for developer test**

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
