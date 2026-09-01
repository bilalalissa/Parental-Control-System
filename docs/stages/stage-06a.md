# STAGE-06A — Manual third-party MDM feasibility for managed macOS login

- Version: `0.6.1-rc.1`
- Branch: `stage/06a-manual-mdm-feasibility`
- Status: `READY_FOR_DEVELOPER_TEST`
- Authorized: `2026-09-01` via `AUTHORIZE ROADMAP AMENDMENT: INSERT STAGE-06A MANUAL-MDM FEASIBILITY BEFORE STAGE-07` and `PROCEED: STAGE-06A`
- Platform evaluated: macOS 15 documentation and third-party MDM documentation; no device enrolled

## Objective, included scope, and acceptance

Determine whether manual enrollment with one third-party MDM can safely prevent an ordinary local standard child account from logging in outside a signed weekly schedule while an adult recovery administrator can always log in.

Included work is a vendor-neutral Apple-platform capability review, candidate MDM comparison, focused threat-model update, recovery and privacy gates, and an honest go/no-go decision before any external account or physical enrollment. Acceptance requires selective child-account denial, bounded restoration, an offline local adult recovery route, observable delivery, no destructive credential exposure, and no change to the local-first controller/endpoint path.

Excluded are Automated Device Enrollment, Apple Business Manager or Apple School Manager, Platform SSO, directory/network-account deployment, FileVault or secure-token changes, scripts, a public relay, product MDM API integration, device erase, application/network blocking, and STAGE-07 work. No Parent Controller or child-endpoint integration is included.

Assumptions were one disposable Mac, one ordinary local standard child account, one separate local adult recovery administrator, recoverable data, and administrator-approved manual enrollment. No vendor account, APNs certificate, API key, or enrolled device is created without separate explicit approval.

Resource limits are one checkout and branch, no native build, simulator, VM, container, device enrollment, or additional dependency; at least 5 GiB free; and only source documentation plus dependency-free validation tests.

## Result: no-go for the proposed local-account mechanism

Apple's detailed `LoginWindow` contract states that `AllowList` and `DenyList` apply only to network accounts and mobile accounts. They do not selectively block an ordinary local child account. The payload also has no weekly schedule or automatic expiry.

`LocalUserLoginEnabled` is a broad local-login control, not a safe per-account schedule. It must not be deployed for this design because it can remove the guaranteed login path for the adult recovery administrator. A cloud-delivered replacement profile is not an offline recovery mechanism.

Manual enrollment therefore cannot meet the approved acceptance criteria for the current local-account model. The source-level gate fails before a vendor trial or physical-device test would add useful evidence. No configuration profile is generated or installed.

## Third-party candidate findings

| Candidate | Manual enrollment | Custom profile control | Automation boundary | Stage 06A decision |
| --- | --- | --- | --- | --- |
| SimpleMDM | Documents enrollment by link and a 30-day trial | API documents per-device custom-profile assignment and removal | API uses secret keys and exposes destructive device endpoints, including wipe; exact least-privilege scope must be proven | Do not create an account or key because the Apple local-account gate already fails |
| Jamf Now | Documents manual profile enrollment and supervision on macOS 11+ | Custom profiles can be assigned through blueprints | Jamf Now documents no public API | Fallback UI test adds no evidence after the same Apple platform gate |

An APNs-backed third-party MDM is an optional external management dependency. It never becomes the controller's policy authority, never receives chat, app activity, browser metadata, or the local controller database, and must not be required for existing LAN pairing, status, chat, or Stage 06 enforcement.

## Safety gates that prevented deployment

1. The adult recovery administrator must be provably excluded from every denial rule.
2. Recovery must remain possible locally while the MDM vendor, APNs, or network is unavailable.
3. A deny operation must have a bounded automatic expiry or an equivalent local rollback.
4. MDM credentials must not permit erase, account deletion, password rotation, arbitrary scripts, or unrelated device commands.
5. Manual enrollment and its removability must be disclosed; no anti-administrator persistence may be claimed.
6. No real family data or identifiers may enter the repository or a public issue.

The proposed mechanism fails gates 1–3 and cannot yet prove gate 4.

## Alternatives for a later decision

1. Keep the current local-first warning and re-lock behavior. This preserves recovery and offline enforcement but does not prevent initial authentication.
2. Propose a separate managed-identity feasibility stage using a network/mobile account or Platform SSO. This is materially larger and requires identity-provider, FileVault, secure-token, offline-authentication, migration, privacy, and recovery analysis.
3. Use Apple's built-in Screen Time/Downtime for the OS-supported consumer control boundary, alongside this app's visible family workflow.

No alternative is selected or implemented by STAGE-06A.

## Validation plan

Lightest-to-heaviest checks are JSON parsing, repository contract tests, the focused MDM feasibility assertions, Markdown/link review, `git diff --check`, and a bounded secret scan. No native build, installer, profile lint, MDM account, or physical-device test is justified after the platform gate fails.

Safe cleanup removes only temporary test output. The approved Stage 06 package and browser-extension artifacts remain untouched. No simulator is booted and no project process is started.

## Verification evidence

- The full dependency-free repository suite passed: 45 tests passed and the Windows-only cleanup test was skipped on macOS. Three focused Stage 06A tests require the account-type limit, recovery rejection, optional boundary, and absence of vendor/product integration.
- JSON parsing, local Markdown-link resolution, the existing protocol/policy/cleanup/security regressions, and the active-stage tracker passed in the same run.
- `git diff --check` and the bounded secret scan passed.
- Official Apple and vendor documentation was reviewed on 2026-09-01. This is source evidence, not MDM console or physical-device evidence.
- No native application code changed, so no PKG, app, extension ZIP, signing operation, entitlement check, or installer smoke test applies. The ADR is the single feasibility artifact.
- Feasibility artifact: `docs/adr/0001-manual-mdm-login-window-feasibility.md`; SHA-256 `cefe54c0c88b25b37d71bf013773f9f6a86a1840958928af54821f54964af963`; source Markdown, so signing and entitlements are not applicable.

## Resource evidence

- Free disk before work: 13 GiB. Repository: 25 MiB, including the retained approved Stage 06 candidate set at 15 MiB; its separate endpoint build path was 0 B.
- Peak temporary output estimate: less than 1 MiB for Node test process output; no build tree or package staging was created.
- Free disk after cleanup: 12 GiB. The difference from preflight is system-volume fluctuation; repository size remained 25 MiB and the stage created no build output.
- Cleanup removed two confirmed empty repository-owned directories, `.artifacts/derived-data` and `.artifacts/package-staging`. The approved Stage 06 PKG, extension ZIP, and checksums remain the only retained binary candidate set.
- No simulator, VM, container, worktree, MDM account, profile, APNs certificate, or enrolled device was created.
- Process listing was restricted by the local sandbox. A read-only launch-service inspection showed the developer's pre-existing installed Parent Controller and macOS CoreSimulator support services; none was started or stopped by Stage 06A.

## Developer review checklist

1. Open Apple's `LoginWindow` property documentation and confirm that `AllowList` and `DenyList` apply only to network accounts and mobile accounts.
2. Confirm the intended child account is an ordinary local account, not a directory-backed mobile account.
3. Confirm no MDM enrollment profile or vendor account was created for this feasibility review.
4. Confirm broad denial of all local users is unacceptable because the adult recovery administrator must always retain access.
5. Choose whether to retain Stage 06 local re-lock behavior or authorize a separately scoped managed-identity feasibility proposal.

## Sources

- [Apple LoginWindow payload contract](https://developer.apple.com/documentation/devicemanagement/loginwindow)
- [Apple Login Window deployment settings](https://support.apple.com/en-gb/guide/deployment/dep2a822b29/1/web/1.0)
- [Apple MDM enrollment profile deployment](https://developer.apple.com/documentation/devicemanagement/deploying-device-management-enrollment-profiles)
- [SimpleMDM API reference](https://api.simplemdm.com/v1)
- [SimpleMDM enrollment](https://simplemdm.com/features/device-enrollment/)
- [Jamf Now manual Mac enrollment](https://learn.jamf.com/r/en-US/jamf-now-documentation/Enrolling_a_Mac_Without_Using_Open_Enrollment)
- [Jamf Now product boundary](https://learn.jamf.com/r/en-US/jamf-now-documentation/About_Jamf_Now)
