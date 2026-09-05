# Threat model

## Scope

Stage-06D was amended on 2026-09-05 to managed browser-only website blocking. A browser process/extension is a weaker enforcement boundary than a system filter: disabling it, guest/private mode, another profile or unsupported browser bypasses it. Policy acknowledgements are extension reports, not independent proof; freshness and version matching prevent stale success displays but do not attest a hostile browser. No claim of universal protection or admin resistance is allowed. Publisher/signing services are optional code-distribution gates, not LAN policy authorities. Domain rules are declarative with no page/request-content listeners, remain durable on native-host loss, and clear only on an explicit newer policy or extension removal. Updates keep stable extension identity and require supported browser signing; unsigned test packages are not automatic-update acceptance.

Stage 00 covers contracts and repository controls. This model defines requirements for later runtime stages without claiming those controls are implemented. The system is for devices owned or lawfully administered by a parent or guardian and must remain visible to the child user.

## Assets

- Controller and endpoint private keys, credentials, adult-verifier material, and pairing invitations
- Signed policy, bonus time, commands, receipts, and audit integrity
- Device status, application/tab metadata, chat, and retention configuration
- Availability of local enforcement and the controller's local database
- Availability and recoverability of any optional managed-device login policy
- Integrity and availability of any optional managed identity, SSO extension, account mapping, and online login-policy decision
- Integrity and recoverability of any optional router-owned WAN-pause lease and child-interface mapping
- Integrity, entitlement state, availability, and recoverability of optional macOS Network Extension and Endpoint Security enforcement
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
- **Local router or compromised router credential:** may disconnect the controller, affect the wrong household device, expose unrelated inventory, leave a rule indefinitely, or permit an IPv4/IPv6/interface bypass.
- **Privileged macOS enforcement extension:** may block the wrong user/app/domain, over-collect flow/process data, lose parent recovery, fail to expire, or misrepresent unavailable entitlements.

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
| Broad router administrator credential | Full LAN compromise or unrelated configuration changes | Reject the current broad Device Access Code for automation; require a dedicated operation-scoped API principal stored only in Keychain |
| Router pause blocks local control | Parent cannot cancel or verify enforcement | Place rules only in the WAN forwarding path; explicitly exempt/test controller and recovery LAN paths over Wi-Fi and Ethernet |
| Stale router deny rule | Child remains disconnected beyond approved time | Require maximum-eight-hour router-owned absolute expiry, tagged idempotent leases, independent adult removal, and reboot/controller-loss tests |
| Wrong router client identity | Unrelated device is blocked or child bypasses over another interface | Explicitly approve every Wi-Fi/Ethernet mapping; detect private-address changes; never infer stable identity from a single MAC |
| Partial IP-family enforcement | Child bypasses the pause over IPv4 or IPv6 | Apply and verify both families as one transaction; report unknown/failure unless parity is proven |
| Router content overcollection | DNS, destination, or traffic history becomes surveillance data | Use forwarding decisions only; prohibit packet capture, DNS history, URL/domain retention, TLS interception, and unrelated client inventory |
| Ambiguous router response | UI falsely claims Internet is paused or restored | Verify tagged lease state; report `Unknown—verify router` on timeout or disagreement and retain a visible manual recovery path |
| Missing or mismatched Apple capability | Installer cannot activate enforcement but UI claims success | Verify explicit App IDs, managed entitlements, profiles, identity, and same Team ID before build; disable controls until signed physical activation passes |
| Mutable application identity match | Unrelated binary is denied or an update bypasses policy | Match selected standard-account launches by signing identity/designated requirement; treat identity changes as `needs review`; never use display name or path alone |
| System or adult recovery process denied | Device becomes unusable or unrecoverable | Non-editable safety allowlist, standard child account scope, fail-open timeout/error, independent administrator recovery, boot/login/update soak tests |
| Domain-rule overreach or evasion | Legitimate sites fail or configured site remains reachable | Strict IDNA hostname normalization and label-boundary matching; IPv4/IPv6 and DNS/QUIC/VPN/proxy/VM physical matrix; report unsupported paths honestly |
| Endpoint pause blocks controller or persists | Parent cannot cancel or child remains offline indefinitely | Preserve authenticated LAN on parent Wi-Fi/Ethernet, eight-hour signed hard expiry evaluated locally, monotonic reconciliation, fail-open crash/uninstall recovery |
| Extension event overcollection | Process or browsing behavior becomes surveillance data | Discard unrelated execution events; no URL/path/query/DNS history/packet/payload storage; bounded redacted receipts only |

## Prohibited designs

Hidden installation, stealth persistence, keylogging, screenshots, camera/microphone or clipboard capture, password/form/file/message collection, TLS interception, private APIs, exploits, anti-malware evasion, unrestricted remote browsing/transfer, arbitrary shell/process execution, scheduled MDM/IdP account scripts, cloud-only recovery, destructive API integration, unsupported router CGI/HTML automation, network-content inspection, real-account migration without a synthetic rollback trial, and a universal override code are outside the product boundary.

## Security stage gates

Each implementation stage must update this model when a trust boundary changes, add abuse/negative tests, record residual risks, and distinguish source review from native-device evidence. High or critical findings block release unless explicitly accepted by the developer. Stage 06A's third-party MDM review is source-only and rejects the proposed local-account mechanism before enrollment. Stage 06B's managed-identity review is also source-only: it rejects Platform SSO as an offline family-schedule substitute and permits only a separately approved, recovery-first online pilot. Stage 06C rejects automatic integration with the current ARRIS gateway and permits only a separately approved, recovery-first lab evaluation of a documented router API. Stage 06D remains blocked until Apple-managed entitlements, matching same-Team profiles, a Developer ID identity, signed activation, and its full physical recovery matrix pass. Supervised MDM, a physical managed-identity/router pilot, and any relay require separate approval and focused threat models.
