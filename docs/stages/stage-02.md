# STAGE-02 — Local controller hub, pairing, and lightweight mock agents

- Version: `0.2.0-rc.1`
- Branch: `stage/02-local-hub-pairing`
- Status: `IMPLEMENTING`
- Platform: Apple-silicon macOS 14 or newer

## Objective and included scope

Deliver a local controller hub with authenticated controller-to-hub IPC, Bonjour LAN discovery, one-time pairing, TLS-protected WebSocket transport, Ed25519-signed protocol envelopes, adaptive heartbeats, delta snapshots, receipts, persistent paired-device state, revoke/unpair, bounded queues and audit history, and a lightweight mock-agent CLI.

## Exclusions

No privileged endpoint component, real device monitoring, policy enforcement, arbitrary remote command, public relay, hosted database, SaaS telemetry, container, virtual machine, iPad MDM, or Stage 03+ behavior is included. Mock agents run only as visible ordinary local test processes.

## Assumptions and acceptance criteria

- The Parent Controller remains the local authority and stores operational records in local SQLite; transport and IPC secrets remain in Keychain.
- Pairing requires a short-lived, rate-limited, one-use code and per-device identity.
- The hub rejects expired, future-dated, tampered, duplicate-ID, and non-monotonic signed messages.
- Two mock agents can connect concurrently, report delta snapshots, receive receipts, and become Offline with an honest last-seen time after heartbeat expiry.
- Paired devices and replay sequence state survive a hub restart; revocation blocks subsequent application traffic.
- Audit, receipt, replay, and outbound queues have tested hard bounds.
- One arm64 controller DMG is retained after verification. It is ad-hoc signed and not notarized.

## Resource plan and safe cleanup

Use one checkout, one project-owned SwiftPM scratch tree, at most two build workers, no simulator, and ordinary mock-agent processes only. Run protocol/unit tests before integration and packaging. Stop the hub, mocks, controller, and log streams after each check. After the candidate verifies, remove the previous RC and all project-owned scratch, staging, mount, log, and measurement output; retain only the current DMG and checksum. Never remove user application data or unrelated caches.

## Implementation notes

In progress. Final architecture decisions, exact checks, installer details, limitations, security notes, resource evidence, and the developer checklist will be recorded here before the stage is marked ready for developer testing.
