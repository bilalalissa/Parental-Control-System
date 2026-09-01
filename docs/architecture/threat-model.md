# Threat model

## Scope

Stage 00 covers contracts and repository controls. This model defines requirements for later runtime stages without claiming those controls are implemented. The system is for devices owned or lawfully administered by a parent or guardian and must remain visible to the child user.

## Assets

- Controller and endpoint private keys, credentials, adult-verifier material, and pairing invitations
- Signed policy, bonus time, commands, receipts, and audit integrity
- Device status, application/tab metadata, chat, and retention configuration
- Availability of local enforcement and the controller's local database
- Availability and recoverability of any optional managed-device login policy
- Child safety, privacy, unsaved work, and an honest understanding of endpoint state

## Actors and assumptions

- **Authenticated parent/guardian:** trusted to set policy, but high-impact mistakes remain possible.
- **Standard child account:** may try to stop user-level components, replay traffic, alter clocks, or modify accessible files.
- **Authorized desktop administrator:** can ultimately uninstall or change the software; defeating them is not a goal.
- **LAN attacker:** may observe, inject, replay, reorder, or block traffic.
- **Malicious extension/app/content:** may try to cross a local IPC or data-collection boundary.
- **Repository or build attacker:** may introduce secrets, unsafe dependencies, workflow privilege, or generated artifacts.
- **Third-party MDM or compromised vendor account:** may receive device inventory, push stale profiles, or expose high-impact device commands outside the local controller trust boundary.

The operating system, platform secure storage, supported public APIs, and correct cryptographic libraries form part of the trusted computing base. A normal iPad app cannot be treated as continuously present or desktop-equivalent.

## Threats and required mitigations

| Threat | Impact | Required mitigation and verification |
| --- | --- | --- |
| Impersonated controller or endpoint | Unauthorized policy/actions or false status | Explicit single-use pairing, displayed fingerprints, per-device keys, mutual authentication, revocation, negative pairing tests |
| Replay, reordering, or expired command | Repeated or stale enforcement | Message UUID, monotonic sequence, expiry, signature, idempotency, durable replay window, golden/negative tests |
| Network eavesdropping or tampering | Family-data disclosure or command modification | TLS 1.3 where supported, certificate/key binding, signed messages, no downgrade, transport tests |
| Arbitrary privileged execution | Full device compromise | Typed allowlisted commands, authenticated narrow IPC, capability checks, no shell/script fields, contract and authorization tests |
| Child-accessible policy/configuration | Enforcement bypass | Protected storage, signed/versioned policy, standard child account, integrity checks, fail-closed behavior |
| Clock manipulation | Restored quota or bypassed schedule | Trusted UTC plus IANA zone, monotonic elapsed usage, rollback detection, restart/sleep/DST vectors |
| Excess collection or retention | Privacy harm | Per-device controls, endpoint disclosure, bounded deltas/queues/logs, pruning, no content/credentials/private browsing |
| Dangerous shutdown/logoff | Lost work or safety issue | Lock by default, warnings/grace, explicit confirmation and capability, graceful operations, force disabled |
| Offline-state overclaim | Misleading parent action | Show `Offline` plus last seen; require acknowledged event for shutdown confirmation |
| Adult-code guessing or leakage | Unauthorized settings changes | Memory-hard verifier only, rate limits/increasing delays, scoped short session, never log codes |
| Diagnostic/log leakage | Secrets or family data exposed | Stable event IDs, redaction, bounded rotation, reviewable on-demand bundle, automatic expiry |
| Supply-chain/workflow compromise | Malicious build or secret theft | Minimal dependencies/permissions, pinned actions, secret scanning, no untrusted privileged workflows, reproducible generation |
| Denial of service or storage exhaustion | Lost control/enforcement | Bounded queues and snapshots, input limits, backpressure, small-batch pruning, resource measurements |
| Third-party MDM compromise or destructive API credential | Device wipe, account modification, privacy loss, or unauthorized management | Keep MDM optional; no credential or enrollment without separate approval; require operation-scoped credentials; never expose erase/scripts/password rotation; store approved credentials only in Keychain; audit and revoke |
| Stale or delayed managed login denial | Child or adult indefinitely unable to log in | Require bounded automatic expiry and a tested offline local recovery administrator; reject cloud-only rollback and any profile that can deny the recovery account |
| MDM profile removal by an administrator | Managed policy bypass | Disclose manual enrollment removability; require a standard child account; do not claim anti-administrator persistence or use unsupported bypasses |
| External inventory disclosure | Device/user metadata leaves the LAN | Use synthetic test identities, document vendor fields/retention, exclude chat/app/tab/family data, and delete the test record after approved evaluation |

## Prohibited designs

Hidden installation, stealth persistence, keylogging, screenshots, camera/microphone or clipboard capture, password/form/file/message collection, TLS interception, private APIs, exploits, anti-malware evasion, unrestricted remote browsing/transfer, arbitrary shell/process execution, scheduled MDM scripts, cloud-only recovery, destructive API integration, and a universal override code are outside the product boundary.

## Security stage gates

Each implementation stage must update this model when a trust boundary changes, add abuse/negative tests, record residual risks, and distinguish source review from native-device evidence. High or critical findings block release unless explicitly accepted by the developer. Stage 06A's third-party MDM review is source-only and rejects the proposed local-account mechanism before enrollment. Supervised MDM, managed identity, and any relay require separate approval and focused threat models.
