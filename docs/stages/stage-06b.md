# STAGE-06B — Managed-identity feasibility for scheduled macOS login

- Version: `0.6.2-rc.1`
- Branch: `stage/06b-managed-identity-feasibility`
- Status: `READY_FOR_DEVELOPER_TEST`
- Authorized: `2026-09-03` via `AUTHORIZE ROADMAP AMENDMENT: INSERT STAGE-06B MANAGED-IDENTITY FEASIBILITY BEFORE STAGE-07` and `PROCEED: STAGE-06B`
- Evidence type: official-source review and dependency-free repository validation; no physical enrollment
- Canonical decision: [ADR-0002](../adr/0002-managed-identity-scheduled-login-feasibility.md)

## Objective

Determine whether managed identity can close the pre-login gap left by Stage 06A: deny only a standard child account outside a weekly schedule while preserving local adult and FileVault recovery and keeping the existing signed local schedule authoritative.

## Included scope

- Apple Platform SSO requirements and its FileVault, Login Window, and Lock Screen policies.
- Password, Secure Enclave, and local/network-fallback implications.
- Managed child account registration or migration and standard-account status.
- Secure Token, Bootstrap Token, volume ownership, FileVault automatic-login, and PRK recovery boundaries.
- Offline authentication, IdP/MDM outage, unenrollment, and rollback behavior.
- Representative Microsoft Entra/Intune, Okta Device Access, and Jamf Connect documentation.
- Focused architecture, capability, privacy, threat-model, and automated repository checks.

## Excluded scope

- Creating or configuring an MDM/IdP tenant, account, managed identity, certificate, API token, or billing relationship.
- Enrolling a real Mac, installing an SSO extension/profile, registering a user/device, or changing FileVault, Login Window, local accounts, passwords, secure tokens, or volume ownership.
- Calling vendor APIs or integrating managed identity into the Parent Controller or child endpoint.
- Scheduled account enable/disable automation, arbitrary scripts, custom authorization plug-ins, private APIs, or attempts to defeat a local administrator.
- An installer or application release. No executable changed.
- Stage 07 or any later feature.

## Assumptions

- The child account is a standard account; the adult recovery account is a separate local administrator.
- The currently tested Intel/macOS 15 class remains relevant, while a future pilot may use Apple silicon.
- A family schedule must be deterministic from the signed local policy even if the controller or Internet is unavailable.
- The adult retains a FileVault personal recovery key and lawful administrative control.
- Official Apple documentation is authoritative for macOS behavior; vendor documentation is authoritative only for that vendor's supported integration.

## Acceptance criteria

1. State whether managed identity meets the exact online and offline family-schedule requirement.
2. Separate Platform SSO's authentication enforcement from the IdP's policy decision.
3. Cover FileVault, processor, offline grace, adult exemption, account migration, rollback, and recovery.
4. Compare representative vendor paths without recommending procurement or creating external state.
5. Define strict gates and a synthetic-data plan for any later physical pilot.
6. Update the roadmap and canonical security/privacy/capability documents.
7. Pass dependency-free tests with no product runtime or installed-device change.
8. Provide one reviewable source dossier with a SHA-256 checksum.

## Resource limits and execution plan

- Documentation and Node repository checks only; no Swift/Xcode build, simulator, VM, container, daemon, browser driver, or external app process.
- At most two test workers.
- No dependency installation or generated package output.
- Preserve the approved Stage 06A application and extension artifacts; they remain the latest installable product candidates and are not Stage 06B artifacts.
- Cleanup is limited to repository-owned paths reported by `npm run cleanup:list`; no unrelated installed app or user process is touched.

## Finding

Platform SSO can provide a genuine live IdP requirement at FileVault (Apple silicon only), Login Window, and unlock when Password authentication and `RequireAuthentication` are supported. `NonPlatformSSOAccounts` provides a documented way to exempt the separate local adult recovery administrator.

It does not provide the required weekly schedule. Apple's Platform SSO configuration has no weekday or start/end-time fields and no callback into this project's signed local policy. Offline behavior is binary: no grace denies every offline login; grace permits the local password for a number of days since successful Platform SSO authentication. Neither choice answers whether the current local time falls inside the family schedule.

The IdP would need to make the time decision. No native family weekly Login Window condition was found in the reviewed Microsoft, Okta, or Jamf documentation. Custom scheduled account disablement would depend on an external control plane, introduce delayed rollback and lockout risk, and violate the current local-first boundary.

## Decision summary

- **Exact product requirement:** no-go. Do not implement or claim offline scheduled pre-login enforcement through managed identity.
- **Narrow online pilot:** conditional go only under a new approval. It may test live IdP denial for a synthetic managed child identity and independent adult recovery.
- **Current product:** keep Stage 06/06A local signed-schedule warnings and active-session re-locking. Continue to disclose that initial Login Window authentication is outside its control.
- **Installer:** none. Stage 06B changes no executable, profile, or installed state.

## Feasibility and recovery matrix

| Case | Expected platform behavior | Meets weekly schedule? | Pilot disposition |
| --- | --- | --- | --- |
| Online, child inside allowed time | IdP must accept; Platform SSO proceeds | Only if IdP has a correct time policy | Conditional test |
| Online, child outside allowed time | IdP must deny | Only if IdP has a correct time policy | Conditional test |
| Offline, `RequireAuthentication`, no grace | Child cannot log in, even during allowed time | No | Required negative test |
| Offline, offline grace enabled | Local password can work during whole-day grace | No | Required bypass test |
| Parent controller offline, Internet/IdP online | IdP cannot consume a fresh local signed schedule | No | Document divergence |
| IdP/MDM outage | Child denied without grace; may bypass with grace | No | Recovery drill required |
| Adult local recovery account | Excluded through `NonPlatformSSOAccounts`; local login retained | N/A | Must pass before denial |
| Apple-silicon FileVault boot | Password-mode FileVault policy can require live IdP | Still no schedule in profile | Conditional test |
| Intel FileVault boot | Local FileVault unlock occurs before second Login Window gate | No preboot schedule gate | Disclose limitation |
| Existing local child registration | Password sync may alter local credential | N/A | Synthetic account only |
| Policy removal/unenrollment | Must restore verified local login before external identity deletion | N/A | Same-session rollback test |
| Network unavailable during recovery | Adult account/PRK/recoveryOS must work independently | N/A | Mandatory recovery test |

## Review checklist for this dossier

1. Confirm the distinction between a conditional online pilot and the no-go for the exact offline family-schedule requirement.
2. Confirm that `NonPlatformSSOAccounts` protects only a deliberately separate local adult recovery administrator; it is not applied to the child.
3. Confirm that the offline-grace dilemma is acceptable as the reason not to integrate: allow grace can bypass time windows, while no grace blocks allowed offline use.
4. Confirm that Apple-silicon-only FileVault policy and the Intel two-step limitation are explicit.
5. Confirm no account, enrollment, extension, profile, credential, hardware mutation, or external data transfer occurred.
6. Confirm any future pilot will require a new authorization naming the vendor, eligible disposable hardware, cost, test identity, data retention, and rollback date.

## Rollback

There is no device rollback because nothing was installed or configured. Repository rollback is a normal Git revert of this documentation stage. The approved `0.6.1-rc.5` installer remains the latest application artifact and behavior.

## Security and privacy

The review introduces no runtime trust boundary. A later pilot would introduce an MDM, IdP, SSO extension, network authentication, device/user registration, and recovery secrets. The adult account and PRK must work offline before denial is enabled. Device identifiers in attestation stay disabled by default. No family chat, activity, browser, schedule, IP/MAC, or real identity data may be used in the public repository or sent to a provider during a synthetic pilot.

## Validation commands

```sh
npm test
git diff --check
npm run cleanup:list
```

Physical behavior, provider policy semantics, FileVault recovery, and Login Window denial remain unverified until a separately approved pilot runs on eligible non-primary hardware.

## Candidate evidence

- `npm test`: 50 passed, 0 failed, 1 Windows-only cleanup test skipped on macOS.
- `git diff --check`: passed.
- Stage tracker and schema JSON parse: passed.
- Local Markdown link validation: included in the repository test and passed.
- Scoped private-key/token pattern scan of changed source documents: no matches.
- Dossier artifact: `docs/adr/0002-managed-identity-scheduled-login-feasibility.md`.
- Dossier SHA-256: `c7056407492c8def60a4245f1d0e8bdac241ff4bcfbb47f315054bf10c91a301`.
- Signing and entitlements: not applicable to a Markdown feasibility artifact.

## Resource evidence

- Free disk before work: 22 GiB on the repository volume.
- Repository size before work: 27 MiB; retained project-owned artifacts: 15 MiB.
- Peak temporary build size: 0 bytes of build output; the source-only delta remained below 100 KiB.
- Free disk after validation and cleanup listing: 21 GiB.
- Cleanup result: no repository-owned generated output found.
- Retained product artifacts: the approved Stage 06A package and Stage 05 browser-extension ZIP remain because Stage 06B does not replace either installable product.
- Project processes started by this stage: none.
- Existing installed parent controller/hub processes: developer-owned and deliberately untouched.
- Simulator/emulator/VM/container state: not used.
- Resource-budget exception: none; the 5 GiB floor remained satisfied.
