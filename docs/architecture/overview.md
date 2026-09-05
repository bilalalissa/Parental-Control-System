# Architecture overview

## Status and scope

This document records the target architecture, the merged Stage 06 macOS policy-enforcement boundary, the bounded Stage 06A–06C feasibility decisions, and the amended browser-only Stage 06D implementation. Delivery remains gated by [`stage-status.json`](../stages/stage-status.json).

## Local-first topology

The Apple-silicon macOS Parent Controller is the local policy authority and user interface. It stores operational records in local SQLite and secrets in Keychain. Enrolled desktop endpoints initiate authenticated, TLS-protected LAN connections to the controller. They cache the last valid signed policy, enforce it locally when disconnected, and keep bounded outbound queues for receipts and chat.

The controller never treats an absent heartbeat as proof of shutdown. It displays `Offline` and the last-seen time; `Shutdown confirmed` requires an endpoint event or command receipt.

The local hub uses Bonjour `_parental-control._tcp`, a certificate-pinned TLS 1.3 WebSocket, Ed25519-signed protocol envelopes, and short-lived one-time pairing codes. The GUI authenticates loopback IPC with an ephemeral HMAC key transferred through a private child-process pipe. Stage 06 reuses that channel for nested Ed25519-signed policies, typed expiring actions, adult-verifier rotation, bonus revisions, and authenticated receipts. No second service or cloud data path is introduced.

A standard iPadOS app uses FamilyControls, DeviceActivity, ManagedSettings, and ManagedSettingsUI. It is not a persistent desktop agent. APNs may support honest best-effort notifications, but scheduling and shielding do not depend on a custom cloud database.

## Trust boundaries

1. **Adult and controller UI:** high-impact actions require an authenticated adult session and confirmation where appropriate.
2. **Controller storage:** policy and operational data are local; private keys and credentials are held in Keychain.
3. **LAN transport:** pairing and later sessions mutually authenticate controller and endpoint. TLS protects confidentiality and integrity; message IDs, expiry, sequence, and signatures provide replay protection and auditability.
4. **Desktop privileged boundary:** the narrow macOS daemon accepts only authenticated, typed IPC operations from signed installed components. The logged-in helper maps allowlisted decisions to public macOS mechanisms; it does not expose shell execution or unrestricted process launch.
5. **Browser extension boundary:** a separately installed visible Chrome/Edge/Arc extension sends bounded tab titles and query-free HTTP(S) origins through a fixed-origin native host. The host validates the exact signed parent browser path, signing identifier, and vendor Team ID; installed endpoint XPC separately validates the signed/root-protected host. Private tabs, page content, paths, queries, fragments, forms, cookies, passwords, and network traffic are excluded.
6. **Apple Family Controls boundary:** iPad capability is constrained to supported public APIs and entitlement approval.
7. **Optional external management and identity boundary:** Stages 06A and 06B evaluate documentation only. No vendor account, managed identity, SSO extension, profile, or device enrollment exists, and no external service is trusted with family communication, activity, or the canonical signed schedule. Any future MDM/IdP credential would be a high-impact secret. A Platform SSO pilot would add separate MDM, IdP, extension, network-authentication, user-registration, FileVault, and recovery trust boundaries.
8. **Optional local-router boundary:** Stage 06C evaluates a router as a WAN-only enforcement point. The current ARRIS gateway has no supported automation interface, so no credential or integration exists. A future adapter may use only a documented least-privilege local API, must store its credential in Keychain, and may expose only typed per-device lease operations with router-owned expiry. It must not inspect traffic or gain general router administration.
9. **Browser restriction boundary:** amended Stage 06D sends validated domain rules through the signed LAN envelope and authenticated native host to enrolled Chromium/Firefox profiles. Browser declarative rules persist offline and are read back before acknowledgement. The parent shows profile-specific freshness and version, not universal coverage. Safari, private/guest profiles and disabled extensions are explicit gaps. System-wide Network Extension and Endpoint Security work remains deferred.

## Canonical contracts

- [`packages/protocol/message.schema.json`](../../packages/protocol/message.schema.json) is the single message envelope schema.
- [`packages/policy-engine-spec/policy.schema.json`](../../packages/policy-engine-spec/policy.schema.json) is the single policy schema.
- [`packages/test-fixtures`](../../packages/test-fixtures/) contains synthetic cross-platform fixtures and policy golden vectors.

Platform code may generate types from these definitions, but copied schemas are not authoritative. Changes require contract tests, compatibility notes, and an ADR when semantics or a trust boundary changes.

## Data flow and retention

Endpoints send capability-negotiated snapshots and bounded deltas. The active heartbeat is 15 seconds and backs off to 60 seconds while idle; a device becomes `Offline` after 75 seconds without a valid signed message. The login helper uses `NSWorkspace` launch, termination, and activation notifications rather than continuous process polling. At most 64 regular application names and bundle IDs are retained in an endpoint snapshot, and unchanged activity is not resent. Stage 05 keeps at most 128 sanitized tab records per device, debounces extension changes, and reconciles at most every 15 minutes.

Stage 06 retains the Stage 05 data bounds and adds one current signed policy plus one small runtime-state file. A 15-second policy timer uses a continuous monotonic clock, counts only an active login session, records daily quota/override/grace state, detects material wall-clock discontinuity, and survives sleep and reboot without a polling process. Endpoint logs remain capped below 25 MiB by their existing rotation policy.

## Failure posture

- Invalid, expired, replayed, unsupported, or unverifiable messages fail closed with a readable receipt where safe.
- Endpoints continue enforcing the latest valid signed policy during controller outages.
- Missing or unsupported capabilities disable the related UI/action rather than being emulated.
- Default enforcement is lock with warning and grace; destructive force is disabled.
- An authorized local administrator can remove desktop software. The architecture does not attempt to defeat one.

## Deployment boundaries

Stages 00–12 contain no public relay, hosted API/database, SaaS telemetry, Docker/Kubernetes deployment, or mandatory cloud account. Stages 06A–06D are developer-authorized bounded additions. Stage 06C creates no router credential or product dependency. Stage 06D adds only local domain policies and bounded browser-profile acknowledgements, no network-content or execution data flow.

Stage 06A found that Apple's Login Window allow/deny lists do not selectively schedule an ordinary local account. Stage 06B found that Platform SSO can require live IdP authentication for a managed child at Login Window and can exclude a local adult recovery account, but it has no weekly schedule or callback into the local signed policy. Its offline grace is measured in days since successful identity authentication; without grace, all offline child login is denied. The FileVault authentication policy is Apple-silicon-only. Managed identity therefore does not replace the local-first schedule. A narrower online-only physical pilot, optional supervised-iPad MDM, and any relay work each require explicit later approval and separate architecture/security review.

Stage 06C found the current ARRIS gateway unsuitable for automatic WAN pausing: its supported path is a credential-protected interactive CGI UI, no documented least-privilege API or hard-expiring lease was found, and the ISP warns that its timer is unreliable. A future router adapter must act only in the WAN forwarding path for explicitly mapped child identities, enforce IPv4 and IPv6 together, preserve authenticated local controller traffic, and schedule expiry on the router itself. MikroTik RouterOS and supported OpenWrt hardware have documented primitives worth a separately approved lab evaluation; neither is currently integrated or recommended for purchase.

Stage 06D uses supported declarative WebExtension APIs under the developer's scope amendment, not Apple system extensions. Its local installer does not require managed entitlements. App-launch denial and WAN pause remain unavailable. Production browser signing/publication is a separate distribution gate. See [Stage 06D](../stages/stage-06d.md) and the deferred [ADR-0004](../adr/0004-macos-enforcement-extension-readiness.md).
