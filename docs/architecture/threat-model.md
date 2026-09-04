# Threat model

## Scope

Stage 00 covers contracts and repository controls. This model defines requirements for later runtime stages without claiming those controls are implemented. The system is for devices owned or lawfully administered by a parent or guardian and must remain visible to the child user.

## Assets

- Controller and endpoint private keys, credentials, adult-verifier material, and pairing invitations
- Signed policy, bonus time, commands, receipts, and audit integrity
- Device status, application/tab metadata, chat, and retention configuration
- Availability of local enforcement and the controller's local database
- Availability and recoverability of any optional managed-device login policy
- Integrity and availability of any optional managed identity, SSO extension, account mapping, and online login-policy decision
- Child safety, privacy, unsaved work, and an honest understanding of endpoint state

## Actors and assumptions

- **Authenticated parent/guardian:** trusted to set policy, but high-impact mistakes remain possible.
- **Standard child account:** may try to stop user-level components, replay traffic, alter clocks, or modify accessible files.
- **Authorized desktop administrator:** can ultimately uninstall or change the software; defeating them is not a goal.
- **LAN attacker:** may observe, inject, replay, reorder, or block traffic.
- **Malicious extension/app/content:** may try to cross a local IPC or data-collection boundary.
- **Repository or build attacker:** may introduce secrets, unsafe dependencies, workflow privilege, or generated artifacts.
- **Third-party MDM or compromised vendor account:** may receive device inventory, push stale profiles, or expose high-impact device commands outside the local controller trust boundary.
- **Third-party IdP, SSO extension, or compromised managed identity:** may deny login, synchronize a credential incorrectly, mis-map account privilege, disclose registration identifiers, or become unavailable at an authentication boundary.

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
| Managed-identity schedule divergence | IdP decision and locally signed family schedule disagree | Do not represent Platform SSO as the local schedule evaluator; require a documented provider decision point and compare allowed/blocked boundaries before any pilot claim |
| Offline authentication dilemma | Grace bypasses blocked time, or no grace denies allowed offline use | Treat the exact offline schedule design as no-go; never silently substitute day-based grace for a weekly schedule |
| Adult account captured by child policy | Parent loses local recovery | Use a separate local administrator in `NonPlatformSSOAccounts`; verify offline login, secure-token/volume authority, and PRK recovery before child denial |
| FileVault passthrough or processor mismatch | Disk unlock bypasses a second gate or coverage is overstated | Document Apple-silicon-only Platform SSO FileVault policy; on Intel require and test the separate post-FileVault Login Window, without claiming preboot schedule enforcement |
| Password synchronization or account mapping error | Child data or local access is lost | Use only a disposable synthetic standard account in a separately approved pilot; record current credentials/ownership and prove rollback before considering real-account migration |
| IdP/MDM/extension outage or policy delay | Child or adult is locked out, or a denial arrives late | Keep adult recovery independent and offline; test provider outage, profile removal, PRK/recoveryOS bypass, and same-session rollback before denial |
| Excess identity attestation | Hardware or user identifiers are unnecessarily disclosed | Keep device identifiers in attestation disabled by default; separately approve any claimed necessity and vendor retention |

## Prohibited designs

Hidden installation, stealth persistence, keylogging, screenshots, camera/microphone or clipboard capture, password/form/file/message collection, TLS interception, private APIs, exploits, anti-malware evasion, unrestricted remote browsing/transfer, arbitrary shell/process execution, scheduled MDM/IdP account scripts, cloud-only recovery, destructive API integration, real-account migration without a synthetic rollback trial, and a universal override code are outside the product boundary.

## Security stage gates

Each implementation stage must update this model when a trust boundary changes, add abuse/negative tests, record residual risks, and distinguish source review from native-device evidence. High or critical findings block release unless explicitly accepted by the developer. Stage 06A's third-party MDM review is source-only and rejects the proposed local-account mechanism before enrollment. Stage 06B's managed-identity review is also source-only: it rejects Platform SSO as an offline family-schedule substitute and permits only a separately approved, recovery-first online pilot. Supervised MDM, a physical managed-identity pilot, and any relay require separate approval and focused threat models.
