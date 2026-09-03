# STAGE-06A — Manual third-party MDM feasibility for managed macOS login

- Version: `0.6.1-rc.5`
- Branch: `stage/06a-manual-mdm-feasibility`
- Status: `MERGED`
- Authorized: `2026-09-01` via `AUTHORIZE ROADMAP AMENDMENT: INSERT STAGE-06A MANUAL-MDM FEASIBILITY BEFORE STAGE-07` and `PROCEED: STAGE-06A`
- Installer amendment authorized: `2026-09-01` via `AUTHORIZE STAGE-06A SCOPE AMENDMENT: PRODUCE 0.6.1-rc.1 TRANSITION INSTALLER` and `PROCEED: STAGE-06A INSTALLER RETEST`
- Platform evaluated: macOS 15 documentation and third-party MDM documentation; no device enrolled

## Objective, included scope, and acceptance

Determine whether manual enrollment with one third-party MDM can safely prevent an ordinary local standard child account from logging in outside a signed weekly schedule while an adult recovery administrator can always log in.

Included work is a vendor-neutral Apple-platform capability review, candidate MDM comparison, focused threat-model update, recovery and privacy gates, and an honest go/no-go decision before any external account or physical enrollment. The separately authorized transition work preserves Stage-06 behavior, adds a versioned login-enforcement readiness model, visibly distinguishes active-session enforcement from managed pre-login enforcement, and produces one upgrade-safe package. Acceptance requires truthful capability presentation, preserved endpoint identity and protected state across in-place installation, unchanged local-first policy behavior, universal endpoint binaries, verified package contents, and no unsupported pre-login claim.

Excluded are Automated Device Enrollment, Apple Business Manager or Apple School Manager, Platform SSO, directory/network-account deployment, FileVault or secure-token changes, privileged MDM scripts, a public relay, product MDM API integration, device erase, application/network blocking, actual pre-login enforcement, and STAGE-07 work. No Parent Controller or child-endpoint MDM integration is included.

Assumptions were one disposable Mac, one ordinary local standard child account, one separate local adult recovery administrator, recoverable data, and administrator-approved manual enrollment. No vendor account, APNs certificate, API key, or enrolled device is created without separate explicit approval.

Resource limits are one checkout and branch, one Release build tree, two build workers, no simulator, VM, container, device enrollment, or additional dependency, and at least 5 GiB free. Only one new PKG and checksum may replace the prior local package after verification; the unchanged browser-extension ZIP is retained without rebuilding.

## RC2 retest feedback

The developer confirmed that the first lock was delivered but the blocked child session was not locked again after returning through the login/Screen Saver UI. The runtime already re-armed a restriction for an inactive-to-active workspace transition, but helper startup and Screen Saver exit can occur while the daemon's last state remains `active`. RC2 adds an authenticated activation-boundary marker from the installed GUI helper at startup, wake/session activation, and termination of Apple's public `ScreenSaverEngine`. The daemon immediately re-evaluates the existing signed policy at that boundary; it does not change policy authority, add a hidden process, or claim control of Login Window authentication.

## RC3 retest feedback

The developer confirmed that the child can still authenticate at Login Window, that returning to the session does not reliably restart an already-running Screen Saver instance, that the child Status content cannot scroll at smaller heights, and that a blocked session has no countdown. Initial Login Window authentication remains an explicit platform limitation rather than a defect this transition build can truthfully solve. RC3 requests a fresh instance of Apple's public `ScreenSaverEngine` for every allowlisted lock operation and adds a bounded helper check that retries only a signed schedule lock in an active graphical session when Screen Saver is not foreground. It also projects the next allowed policy transition, renders a one-second local countdown in the child Status view and menu bar, and makes the Status surface vertically scrollable with wrapping explanatory text.

## RC4 retest feedback

The developer confirmed that repeated active-session locking works, but observed a lock during a configured weekly allowed window. RC3 could briefly act on a cached Block decision after wake or when the allowed boundary had just arrived, before the daemon's next 15-second evaluation. RC4 requires a recent daemon evaluation before repeating a schedule lock, aligns projected allowances to the exact scheduled minute, and suppresses the repeat lock as soon as that allowed boundary arrives. Signed daily quota and explicit blocked-interval precedence remain unchanged.

## RC5 retest feedback

The developer confirmed that allowed-window direction and repeated locking are correct, but a Thursday 06:58–21:50 window displayed an apparently inconsistent 04:42 countdown at 08:12. The countdown was the earlier daily active-use quota limit, including approved bonus time, rather than the end of the weekly window; the child UI did not identify that precedence. RC5 keeps the established fail-closed policy order and makes it inspectable: the child shows the signed-policy time zone and current policy-local time, the exact scheduled interval and its independent remaining time, planned window duration, base and bonus quota, active-use remainder, temporary allowance, effective remaining time, and the next limiting rule. The visible menu-bar helper also identifies the effective limit in its menu and tooltip.

## Approval

The developer reported that build `6105` passed physical-device testing and approved the candidate with the exact command `APPROVED: STAGE-06A 0.6.1-rc.5` on 2026-09-03. Approval does not merge the draft pull request, create a release, or authorize STAGE-06B, STAGE-07, managed-identity work, or any other later stage.

The developer separately authorized the Stage 06A pull-request merge with the exact command `MERGE` on 2026-09-03. This merge does not create a release or authorize any later stage.

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

No managed-identity alternative is selected or implemented by STAGE-06A. The transition installer only exposes the boundary required for a later decision.

## Validation plan

Lightest-to-heaviest checks are JSON parsing, repository contract tests, focused MDM and transition-readiness assertions, Swift formatting, controller and endpoint Swift tests, bounded Release builds, package expansion and metadata inspection, architecture and embedded-signature verification, installer-choice inspection, `git diff --check`, and a bounded secret scan. A physical in-place upgrade is reserved for the developer retest because it changes installed system services and the paired endpoint under test.

Safe cleanup removes only repository-owned `dist`, Stage 06A derived data, and package-staging output after verification. The new package replaces the prior Stage 06 native package only after its checksum and expanded contents pass; the unchanged Stage 06 browser-extension ZIP remains available and is not rebuilt. No simulator, VM, container, browser driver, or GUI app is started.

## Verification evidence

- The full dependency-free repository suite passed: 46 tests passed and the Windows-only cleanup test was skipped on macOS. It covers the Stage 06A platform boundary, release version, package contract, upgrade preservation, active-stage tracker, protocol/policy/security regressions, JSON parsing, and local Markdown links.
- The controller/HubCore Swift suite passed 50 tests in 14 suites with normal Keychain and loopback access. The endpoint Swift suite passed 26 tests in three suites, including authenticated pairing, upgrade identity preservation, activation-boundary re-arming, exact-minute allowed-window projection, rejection of stale repeat-lock decisions, and an exact America/Regina test separating a Thursday 06:58–21:50 weekly window from an earlier active-use quota limit.
- Swift formatting lint, Bash syntax, installer-distribution XML validation, `git diff --check`, and the bounded secret scan passed.
- The expanded installer contains both selectable components, the native browser host manifests, launchd definitions, and the universal endpoint helpers. Both apps report `0.6.1-rc.5` build `6105` and source commit `ce7428e6a0b2`. The Parent Controller is `arm64`; the child app and its four helpers are `x86_64 arm64`.
- Deep strict code-signature verification passed for both app bundles, and strict verification passed for the separately installed daemon and CLI copy. These are ad-hoc signatures with no Team ID because no valid local signing identity is configured. The product package is unsigned and not notarized.
- Installer-choice inspection passed: Parent Controller is selected by default; Child Endpoint is visible and optional. The child choice explicitly documents in-place pairing preservation. No enrollment profile, MDM integration, or managed pre-login capability is included.
- Transition installer: `.artifacts/release-candidate/ParentalControlSystem-0.6.1-rc.5.pkg`; 15,627,326 bytes; SHA-256 `e835e4fc5023737eb5b19386afd3e4318d8700dc96db0f9392a0e3fd3ca56aa9`.
- The unchanged browser-extension archive remains `ParentalControlBrowserSharing-0.6.0-rc.9.zip`. It is not a new Stage 06A artifact; the installer updates its native host in place, so an installed extension does not require removal, reinstallation, or manual reload.
- Official Apple and vendor documentation was reviewed on 2026-09-01. This remains source evidence, not MDM-console or enrolled-device evidence. Feasibility ADR: `docs/adr/0001-manual-mdm-login-window-feasibility.md`; SHA-256 `cefe54c0c88b25b37d71bf013773f9f6a86a1840958928af54821f54964af963`.

## Resource evidence

- RC5 retest preflight: 12 GiB free; repository 26 MiB excluding generated artifacts; retained candidate set 15 MiB; no generated build output.
- Peak observed repository size before cleanup was 889 MiB, including the bounded controller and endpoint test/build output. The development volume remained above the 5 GiB floor.
- After cleanup: 15 GiB free; repository 27 MiB excluding generated artifacts; retained candidate set 15 MiB. `dist`, root and package-local Stage 06A test/derived data, endpoint SwiftPM output, package-staging output, and incidental release-folder metadata were removed, and the cleanup dry run reports no remaining generated output.
- Retained files are the single current native package and checksum plus the unchanged Stage 06 browser-extension ZIP and checksum. No duplicate native RC is retained.
- No simulator, VM, container, worktree, MDM account, profile, APNs certificate, or enrolled device was created. No project service or GUI process was intentionally launched. The developer's previously installed Parent Controller and its Hub helper remained running and were not modified or stopped by build verification.

## Developer review checklist

1. Verify the package SHA-256 before installation.
2. Install Parent Controller over the currently installed version and confirm About reports `0.6.1-rc.5` build `6105`.
3. On the already paired child Mac, choose **Customize**, deselect **Parent Controller**, select **Child Endpoint**, and install without uninstalling or unpairing first. Confirm pairing, online state, signed policy, messages, and retained browser observations remain available.
4. Confirm the Parent Controller device detail and child Status view both report active-session enforcement as available and managed pre-login enforcement as not configured.
5. For a pure weekly-window test, set the daily quota to 1,440 minutes and configure no explicit blocked interval. Apply a weekly allowed window spanning the current time and confirm the child remains unlocked.
6. Apply a window that excludes the current time and confirm the first lock after the configured warning/grace period. Authenticate through the macOS Screen Saver/login UI while the schedule remains blocked; initial authentication is expected to succeed, but confirm the active desktop is re-locked within 15 seconds. Repeat once and confirm there is no rapid duplicate-lock loop.
7. Configure the next allowed boundary a few minutes ahead. While blocked, confirm the child Status view and visible menu-bar item count down to it; at the exact boundary, authenticate and confirm the app stops re-locking the session.
8. During an allowed window, confirm **Schedule time zone** and **Policy time** match the signed parent policy and local wall clock. Confirm **Current scheduled window**, **Planned window duration**, and **Scheduled time remaining** agree with the parent editor. **Effective time remaining** may be earlier only when **Next limiting rule** identifies a daily quota, blocked interval, or temporary allowance boundary. For a pure weekly-window test, use a 1,440-minute quota, no blocked interval, and no active temporary allowance.
9. Resize the child window vertically and horizontally and confirm all Status content wraps or remains readable through vertical scrolling. Approve bonus time and confirm the child separately shows the base quota, bonus, total active-use allowance, and temporary parent allowance. Then recheck one immediate lock action and one time-extension request/decision.
10. Open a new browser tab and confirm it appears without removing, reinstalling, or manually reloading the already installed extension.
11. Repeat-install the same Child Endpoint choice and confirm identity and protected state remain intact.
12. Confirm no profile is installed, no MDM account is requested, and the app makes no claim that it can deny an ordinary local account at Login Window.
13. On a clean Mac, confirm the endpoint still requires one explicit pairing, as designed.

## Sources

- [Apple LoginWindow payload contract](https://developer.apple.com/documentation/devicemanagement/loginwindow)
- [Apple Login Window deployment settings](https://support.apple.com/en-gb/guide/deployment/dep2a822b29/1/web/1.0)
- [Apple MDM enrollment profile deployment](https://developer.apple.com/documentation/devicemanagement/deploying-device-management-enrollment-profiles)
- [SimpleMDM API reference](https://api.simplemdm.com/v1)
- [SimpleMDM enrollment](https://simplemdm.com/features/device-enrollment/)
- [Jamf Now manual Mac enrollment](https://learn.jamf.com/r/en-US/jamf-now-documentation/Enrolling_a_Mac_Without_Using_Open_Enrollment)
- [Jamf Now product boundary](https://learn.jamf.com/r/en-US/jamf-now-documentation/About_Jamf_Now)
