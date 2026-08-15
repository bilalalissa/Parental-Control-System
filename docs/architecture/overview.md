# Architecture overview

## Status and scope

This document records the target architecture and the Stage 04 macOS activity/chat implementation boundary. Delivery remains gated by [`stage-status.json`](../stages/stage-status.json).

## Local-first topology

The Apple-silicon macOS Parent Controller is the local policy authority and user interface. It stores operational records in local SQLite and secrets in Keychain. Enrolled desktop endpoints initiate authenticated, TLS-protected LAN connections to the controller. They cache the last valid signed policy, enforce it locally when disconnected, and keep bounded outbound queues for receipts and chat.

The controller never treats an absent heartbeat as proof of shutdown. It displays `Offline` and the last-seen time; `Shutdown confirmed` requires an endpoint event or command receipt.

The local hub uses Bonjour `_parental-control._tcp`, a certificate-pinned TLS 1.3 WebSocket, Ed25519-signed protocol envelopes, and short-lived one-time pairing codes. The GUI authenticates loopback IPC with an ephemeral HMAC key transferred through a private child-process pipe. Stage 04 extends the same channel with bounded activity deltas, direct/group/announcement chat, delivery receipts, activity configuration, and more-time requests. No second service or cloud data path is introduced.

A standard iPadOS app uses FamilyControls, DeviceActivity, ManagedSettings, and ManagedSettingsUI. It is not a persistent desktop agent. APNs may support honest best-effort notifications, but scheduling and shielding do not depend on a custom cloud database.

## Trust boundaries

1. **Adult and controller UI:** high-impact actions require an authenticated adult session and confirmation where appropriate.
2. **Controller storage:** policy and operational data are local; private keys and credentials are held in Keychain.
3. **LAN transport:** pairing and later sessions mutually authenticate controller and endpoint. TLS protects confidentiality and integrity; message IDs, expiry, sequence, and signatures provide replay protection and auditability.
4. **Desktop privileged boundary:** future narrow privileged services accept only authenticated, typed IPC operations from their visible user component. They do not expose shell execution.
5. **Browser extension boundary:** a separately installed visible extension sends bounded metadata through an authenticated native-messaging host. It excludes private sessions and page content.
6. **Apple Family Controls boundary:** iPad capability is constrained to supported public APIs and entitlement approval.

## Canonical contracts

- [`packages/protocol/message.schema.json`](../../packages/protocol/message.schema.json) is the single message envelope schema.
- [`packages/policy-engine-spec/policy.schema.json`](../../packages/policy-engine-spec/policy.schema.json) is the single policy schema.
- [`packages/test-fixtures`](../../packages/test-fixtures/) contains synthetic cross-platform fixtures and policy golden vectors.

Platform code may generate types from these definitions, but copied schemas are not authoritative. Changes require contract tests, compatibility notes, and an ADR when semantics or a trust boundary changes.

## Data flow and retention

Endpoints send capability-negotiated snapshots and bounded deltas. The active heartbeat is 15 seconds and backs off to 60 seconds while idle; a device becomes `Offline` after 75 seconds without a valid signed message. The login helper uses `NSWorkspace` launch, termination, and activation notifications rather than continuous process polling. At most 64 regular application names and bundle IDs are retained in an endpoint snapshot, and unchanged activity is not resent. Browser tabs remain stage-gated.

Stage 04 implements configurable one-to-thirty-day app-activity retention (seven days by default), thirty-day chat retention, a 100-envelope offline queue per device, a 200-message endpoint view, and bounded requests, receipts, replay caches, and audit records. Endpoint logs remain capped below 25 MiB by their existing rotation policy.

## Failure posture

- Invalid, expired, replayed, unsupported, or unverifiable messages fail closed with a readable receipt where safe.
- Endpoints continue enforcing the latest valid signed policy during controller outages.
- Missing or unsupported capabilities disable the related UI/action rather than being emulated.
- Default enforcement is lock with warning and grace; destructive force is disabled.
- An authorized local administrator can remove desktop software. The architecture does not attempt to defeat one.

## Deployment boundaries

Stages 00–12 contain no public relay, hosted API/database, SaaS telemetry, Docker/Kubernetes deployment, or mandatory cloud account. Optional supervised-iPad MDM and relay work each require explicit later approval and separate architecture/security review.
