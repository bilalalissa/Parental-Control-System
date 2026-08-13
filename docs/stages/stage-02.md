# STAGE-02 — Local controller hub, pairing, and lightweight mock agents

- Version: `0.2.0-rc.1`
- Branch: `stage/02-local-hub-pairing`
- Status: `MERGED`
- Platform: Apple-silicon macOS 14 or newer

## Objective and scope

Deliver a local controller hub with authenticated controller-to-hub IPC, Bonjour LAN discovery, one-time pairing, TLS-protected WebSocket transport, Ed25519-signed protocol envelopes, adaptive heartbeats, delta snapshots, receipts, persistent paired-device state, revoke/unpair, bounded queues and audit history, and a lightweight mock-agent CLI.

No privileged endpoint component, real device monitoring, policy enforcement, arbitrary remote command, public relay, hosted database, SaaS telemetry, container, virtual machine, iPad MDM, or Stage 03+ behavior is included. Mock agents run only as visible ordinary local test processes.

## Delivered architecture and security behavior

- `ParentalControlHub` is a bundled ordinary-user helper. It advertises `_parental-control._tcp` on Bonjour and serves a TLS 1.3 WebSocket endpoint with an application-pinned self-signed certificate.
- Each mock device owns an Ed25519 key. Protocol envelopes are signed, versioned, size-limited, expiry/skew checked, and protected against duplicate message IDs and non-monotonic sequence replay.
- Pairing invitations are one-use, expire after five minutes, and allow at most five failed attempts. A successful pairing persists the device public key and consumes the code.
- Local SQLite retains paired devices, last-seen and replay state, snapshots, receipts, audit history, and bounded per-device queues. Restart, revoke, unpair, and queue-bound behavior are covered by tests.
- The GUI authenticates loopback IPC using HMAC-SHA256. Its 32-byte session key is generated per launch, retained only in memory, and transferred once to the child helper through a private standard-input pipe. It is never written to disk, placed in process arguments, or stored in Keychain.
- Persistent controller signing and TLS private keys remain hub-only in Keychain. The public TLS certificate is a mode-0600 Application Support file. Two launches of the same final app binary were checked with no SecurityAgent prompt, and routine launch, status refresh, pairing, and shutdown require no Keychain password entry. A newly rebuilt ad-hoc binary can still cause macOS to re-evaluate Keychain access; a stable Developer ID identity is later release-hardening work.
- The hub watches its parent controller process and exits synchronously with it. Normal quit left no controller, hub, or mock process running.
- Stage 01's direct, family-group, and all-device announcement previews remain available. Real chat delivery remains Stage 04 work.

## Verification evidence

| Check | Result |
| --- | --- |
| `npm test` | 24 passed; the single Windows cleanup case was correctly skipped on macOS (25 total). |
| `swift format lint --recursive apps/controller-macos/Sources apps/controller-macos/Tests` | Passed. |
| `swift test --package-path apps/controller-macos --jobs 2` | 25 tests in 9 suites passed. |
| Protocol tests | Valid signature plus tamper, expiry, future-date, duplicate-ID, non-monotonic sequence, and ISO-8601 cases passed. |
| Pairing/persistence tests | One-use/expiry/attempt limits, restart persistence, revoke/unpair, and database bounds passed. |
| Transport/IPC tests | Pinned TLS WebSocket, IPC HMAC, replay, timestamp expiry, heartbeat, and delta cases passed. |
| Concurrent mock integration | Two mock agents connected simultaneously, were persisted with independent sequences, became honestly offline without changing last-seen, and remained after hub restart. |
| TLS restart integration | The certificate fingerprint remained `38:3C:FB:F1:A3:FE:80:0C:99:2E:6B:2E:6A:0A:F4:B5:84:56:77:5E:E4:FC:2D:E1:B1:50:CF:89:B1:F8:83:06`. |
| App lifecycle | Exactly one controller and one helper ran; two launches of the final binary showed no SecurityAgent prompt; normal quit left none. |
| Package verification | DMG verification and strict code-signature verification passed; controller, hub, and mock binaries are arm64. |
| CI packaging resilience | DMG creation and verification each use three bounded attempts with two-second delays; verification remains mandatory and fail-closed. |

The local integration used loopback and disabled Bonjour only for deterministic mock execution; the Bonjour advertisement and browser implementation compiled, and LAN discovery remains a developer manual test. CI and a second physical Mac have not yet run. No simulator, VM, or container was used.

## Release candidate

- Artifact: `.artifacts/release-candidate/ParentalControlController-0.2.0-rc.1-arm64.dmg`
- SHA-256: `a8c29f78854739264f3b30557e45e95f2a5d2502eda12d809e0bcb79ccfcbd22`
- Embedded commit: `8d779df99314`
- Signing: local ad-hoc signature only; no Developer ID Team ID, notarization, or restricted entitlements

The DMG contains `Parental Control.app` and an Applications link. It replaces the prior local RC; no duplicate installer is retained.

## Installation and rollback

1. Open the DMG and drag **Parental Control.app** to **Applications**.
2. Launch the app. Because this developer candidate is ad-hoc signed and not notarized, macOS may require explicit approval to open it.
3. Permit Local Network access if macOS requests it; LAN discovery cannot work without that permission.
4. To uninstall or roll back, quit the app, confirm its hub and mocks have stopped, and move **Parental Control.app** to Trash. The app does not install a privileged daemon or system extension.
5. Local application data is deliberately not deleted automatically. Remove it manually only if a clean-state test is intended and the developer accepts losing the test pairings and Stage 01 preview data.

## Manual developer checklist

1. Install and open the DMG on Apple-silicon macOS 14 or newer; confirm the Dashboard loads and no Keychain password prompt appears during routine use.
2. Quit and reopen the same installed binary; confirm again that no Keychain prompt appears and only one helper accompanies the controller.
3. Select **Create one-time pairing code**, copy the mock token, and run the README mock command with a unique ID.
4. Confirm the device appears with the correct name and last-seen time, then stop the mock and confirm it becomes `Offline` without being called powered off.
5. Create two new tokens and run two uniquely named mocks concurrently; confirm both appear and update independently.
6. Restart the controller and confirm paired devices and their last-seen information persist.
7. Revoke one device and confirm its subsequent traffic is rejected. Unpair it and confirm its queued state is removed.
8. If another Mac is available on the same LAN, confirm Bonjour discovery is visible with Local Network permission granted.
9. Exercise the Stage 01 family group and all-device announcement previews; confirm they remain previews and do not claim delivery.
10. Quit the controller and confirm the helper and mocks are no longer running, then test uninstall or rollback.

## Known limitations

- This stage connects only the included synthetic mock agent; macOS, Windows, and iPad endpoints are later stages.
- It performs no monitoring, enforcement, policy command, privileged action, or real chat delivery.
- The artifact is arm64, ad-hoc signed, and not notarized. Gatekeeper behavior is not representative of a final Developer ID release.
- Local Network permission and the same reachable LAN are required for Bonjour discovery; no public relay or mandatory cloud account exists.
- Standard iPadOS capability limits remain unchanged; this stage makes no desktop-style presence or control claims for iPad.

## Resource and cleanup evidence

- Free disk before implementation: 10 GiB.
- Project-owned source/repository before implementation: 3.3 MiB; retained Stage 01 RC: 1.9 MiB; local application data: about 220 KiB.
- Peak project-owned repository/build output: 289 MiB total, including 281 MiB of project-owned generated output.
- Optimized four-sample idle measurement across a full refresh interval: controller average CPU 0.3%, controller peak RSS 124,976 KiB; hub CPU 0.0%, hub RSS 15,056 KiB; combined peak about 136.7 MiB.
- Pre-cleanup free disk: 11 GiB. Application Support data retained for developer testing: 352 KiB across seven files.
- Cleanup removes only `.artifacts/derived-data` and `dist`; the single DMG and checksum remain. No simulator state exists, and no project process is retained.

## Developer approval

The developer approved this release candidate with the exact command `APPROVED: STAGE-02 0.2.0-rc.1` and separately authorized its merge with the exact command `MERGE` on 2026-08-13. The stage is merged but unreleased. Stage 03 must not begin without a subsequent exact `PROCEED` command.
