# ADR-0002: Do not substitute managed identity for the local family schedule

- Status: Proposed for STAGE-06B developer review
- Date: 2026-09-03
- Stage: STAGE-06B
- Version: `0.6.2-rc.1`
- Owners: project maintainers

## Question

Can Apple Platform SSO or a managed network/mobile identity prevent a standard child account from logging in outside the parent's weekly schedule while all of these properties remain true?

1. The parent controller remains the local policy authority.
2. The last signed schedule works without the parent or Internet.
3. An adult has an independent, offline recovery account.
4. FileVault remains recoverable and does not silently bypass the second authentication gate.
5. Existing local child data can be migrated and rolled back without destructive account operations.

Stage 06A proved that the ordinary Login Window MDM allow/deny lists cannot selectively schedule a local child account. Stage 06B evaluates the managed-identity alternative before any account, tenant, enrollment, profile, or physical test is created.

## Platform evidence

Apple Platform SSO requires a device-management service, an Extensible SSO configuration, and a compatible identity-provider extension. Login policies are available on macOS 15 or later. With password authentication, `LoginPolicy`, `UnlockPolicy`, and—on Apple-silicon Macs—`FileVaultPolicy` can attempt or require live identity-provider authentication. `NonPlatformSSOAccounts` can exclude a named local recovery administrator from those policies.

`RequireAuthentication` is a real online gate: when the Mac is online, the identity provider must accept the login. When the Mac is offline, the only documented choices are to deny access or permit a configured `OfflineGracePeriod`. That grace is an integer number of days following a successful Platform SSO login. It is not a weekly schedule and cannot consume the parent controller's signed local policy. `AttemptAuthentication` instead permits the matching local password while offline.

The Platform SSO profile has no weekday, start-time, end-time, or local policy callback. The identity provider would therefore have to make the schedule decision. The representative provider documentation reviewed for Microsoft Entra ID/Intune, Okta Device Access, and Jamf Connect documents identity, device, authentication, or local-fallback conditions, but no native family weekly-login schedule. Absence from those documented condition sets is evidence against a deployable design, not proof that every commercial customization is impossible. Scheduled external account disablement or custom automation would move policy authority to a cloud control plane and create delayed rollback and lockout risks; it is outside this project.

### FileVault and processor boundary

Apple's `FileVaultPolicy` Platform SSO gate applies only on Apple silicon. The currently tested Intel class cannot use it. On Intel with FileVault, a FileVault-enabled user can still unlock the encrypted volume with the local password before a separate Login Window policy is evaluated. `DisableFDEAutoLogin` can force that second Login Window step, but does not make the preboot FileVault prompt schedule-aware.

On Apple silicon, a Password-authentication Platform SSO design can apply a live policy at FileVault, Login Window, and unlock, but it requires usable networking to the identity provider at the relevant screen. The identity provider and extension must support every selected feature. A personal recovery key remains mandatory for recovery; an institutional recovery key is not the recommended recovery design.

Secure Enclave authentication is attractive for phishing resistance, but Apple's general `AttemptAuthentication` and `RequireAuthentication` login-policy options are documented for the Password method. It therefore does not provide the evaluated schedule gate. Password synchronization also changes an existing local credential and increases migration/rollback complexity.

### Recovery boundary

The adult recovery administrator must be a separate local administrator listed in `NonPlatformSSOAccounts`, must retain the FileVault/volume authority needed for recovery, and must never share the child's identity-provider policy. The personal recovery key and any Recovery Lock secret must be held offline by the adult, not by this public repository or the parent app.

Apple documents a recoveryOS command, `security platformsso bypass-login-policy`, which temporarily bypasses the live identity-provider requirement for 12 hours or until a successful identity-provider authentication. This is an emergency repair mechanism, not a routine family override. It demonstrates recoverability but also means Platform SSO is not an unbreakable boundary against someone with recovery authority—which is correct for this product.

## Decision

**No-go for product integration or a claim of offline scheduled pre-login enforcement.** Platform SSO cannot consume the locally signed family schedule, and its offline behavior cannot distinguish an allowed Tuesday morning from a blocked Tuesday night. Allowing offline grace can bypass the intended schedule; disabling it prevents all offline child login, even during allowed time. Neither behavior meets the requirement.

**Conditional go for a separately approved, online-only feasibility pilot.** A pilot could establish that a managed standard child identity can be denied by the identity provider at Login Window while an excluded local adult account remains available. It would prove a narrower enterprise-authentication property, not the complete parental-control requirement. It is justified only if all pilot gates below are accepted.

No Parent Controller or child endpoint source changes are made. No MDM/IdP account, extension, profile, enrollment, managed identity, certificate, API key, or real device record is created. Stage 07 remains gated.

## Evaluated designs

| Design | Online child denial | Offline scheduled decision | Adult recovery | FileVault coverage | Result |
| --- | --- | --- | --- | --- | --- |
| Platform SSO Password + `RequireAuthentication`, no offline grace | Yes, if the IdP denies the login | No; all offline child logins are denied | Feasible with excluded local admin and PRK | Login/Unlock on macOS 15; FileVault policy only on Apple silicon | Conditional pilot only |
| Platform SSO Password + `RequireAuthentication` + offline grace | Yes | No; local password is allowed for whole-day grace after last live login | Feasible | Same processor limit | Reject for schedule guarantee |
| Platform SSO Password + `AttemptAuthentication` | Yes after a live attempt; local password works when initially offline | No; offline bypass | Feasible | Same processor limit | Reject |
| Platform SSO Secure Enclave | Strong passwordless identity; local password remains relevant at reboot | No documented `RequireAuthentication` schedule gate | Feasible | Does not provide the evaluated password-policy behavior | Reject for this use case |
| Jamf Connect `DenyLocal`, no fallback | Requires network identity | No native local weekly evaluator | Exclusions can preserve a local adult, but recovery is vendor/config dependent | Requires a second login after FileVault unlock | Conditional comparison only |
| Jamf Connect local fallback | Requires network identity when reachable | No; offline local login bypasses schedule | Better availability | FileVault unlock remains local | Reject for schedule guarantee |
| Scheduled cloud account disable/enable or custom IdP automation | Potentially | No; external state and delivery determine behavior | High lockout/rollback risk | Vendor specific | Prohibited in this stage |
| Existing Stage 06/06A local active-session re-lock | Not pre-login | Yes, after the standard session becomes active | Local | Does not gate FileVault/Login Window | Retain as supported core |

## Candidate provider comparison

The providers below are representative implementation paths, not endorsements or procurement recommendations.

| Candidate | Required external components | Existing-account behavior relevant to pilot | Documented time-window decision | Stage 06B finding |
| --- | --- | --- | --- | --- |
| Apple Platform SSO framework + compatible IdP | MDM, IdP, signed SSO extension | Can register or create local accounts; Password mode synchronizes the local password | None in Apple's Platform SSO profile | Best platform-native basis, but incomplete for family schedule |
| Microsoft Entra ID + Intune Company Portal | Entra tenant, Intune enrollment/profile, Company Portal | Secure Enclave leaves local password unchanged; Password mode syncs it | No native family weekly Login Window condition found in reviewed docs | Viable online authentication pilot; not offline schedule enforcement |
| Okta Device Access + Okta Verify | Okta Identity Engine, Device Access entitlement, MDM, Okta Verify, device registration | Links/creates the local account according to provider workflow | No native family weekly Login Window condition found in reviewed docs | Viable provider comparison only |
| Jamf Connect + compatible IdP | MDM/configuration, Jamf Connect login plug-in, IdP | Can force network auth and exclude local users; local fallback weakens denial | No native family weekly Login Window condition found in reviewed docs | Useful contrast; custom login replacement adds recovery complexity |

## Account and migration plan for any later pilot

A future pilot must not convert the only copy of an existing family account. It must use a synthetic managed identity and a disposable standard local test account on a non-primary test Mac.

1. Inventory OS version, processor, FileVault state, volume owners, secure-token holders, MDM removal rights, and network availability without recording real identifiers in the repository.
2. Create and verify the independent local adult recovery administrator first. Confirm it is excluded from Platform SSO policy and can unlock FileVault where intended.
3. Escrow a rotated personal recovery key to the adult through an offline channel. Test it before applying a live-authentication requirement.
4. Enroll through an explicitly approved MDM and install only the selected IdP's signed extension and minimal Platform SSO profile.
5. Register a synthetic standard child account. Do not overwrite or rename an existing child's home directory.
6. Verify local data ownership and Keychain behavior before copying only non-sensitive test data.
7. Test online denial, allowed login, lock/unlock, reboot, no-network behavior, IdP outage, policy removal, unenrollment, PRK recovery, and the excluded adult account.
8. Roll back by removing the test policy while online, unregistering Platform SSO, confirming local credentials, then unenrolling and deleting the synthetic external identity according to vendor retention rules.

An in-place migration of a real existing account is a later, separately approved activity. Password-mode registration can synchronize or change the local password, while Secure Enclave mode does not satisfy the evaluated policy gate. Rollback must therefore be proven with synthetic data first.

## Physical-pilot gates

All must be true before asking to enroll hardware:

- Separate written approval names the MDM and IdP, tenant ownership, license/cost, eligible non-primary Mac, and deletion date.
- The pilot requirement explicitly accepts Internet-dependent child login and does not call it offline schedule enforcement.
- The IdP supplies a documented, deterministic policy decision for the desired test interval; manual account disablement is insufficient.
- The adult recovery administrator is excluded from Platform SSO and verified independently.
- FileVault PRK and recoveryOS access are verified before denial is enabled.
- Apple silicon is used if FileVault-stage enforcement is in scope. An Intel pilot must clearly state that FileVault unlock precedes the second login gate.
- Device identifiers in attestation remain disabled unless a separate privacy approval justifies them.
- No chat, application, browser, family schedule, IP/MAC, or other product data is sent to the provider.
- A same-session rollback and a no-network recovery drill both pass before any denial window is tested.

## Consequences

The current Stage 06/06A active-session warning and re-lock behavior remains the honest supported mechanism. It continues to evaluate the signed schedule locally and offline, but cannot prevent initial macOS authentication.

Managed identity is not added to the product roadmap as an implementation dependency. A future pilot can test narrower online authentication behavior, but cannot be marketed or displayed as full scheduled login coverage without new platform evidence and a separate architecture/security approval.

No installer is produced because no executable or installed configuration changed. This ADR is the single feasibility artifact; the Stage 06B document tracks scope, validation, and review steps without creating a second dossier.

## Claim-to-source ledger

| Decision-critical claim | Primary or representative source |
| --- | --- |
| Platform SSO requires device management and a compatible IdP extension; login policies start at macOS 15 | Apple Platform SSO deployment guide |
| Password-mode policies can independently require authentication at FileVault, Login Window, and unlock | Apple Platform SSO configuration documentation and Extensible SSO schema |
| `NonPlatformSSOAccounts` excludes named local accounts from the policies | Apple Platform SSO configuration documentation and Extensible SSO schema |
| Offline grace is measured in days after successful Platform SSO authentication; without enabled grace, required authentication denies offline access | Apple Platform SSO deployment guide and Extensible SSO schema |
| Platform SSO provides no weekly/day/time schedule field | Apple Extensible SSO schema (complete published profile contract reviewed) |
| Platform SSO FileVault policy is available only on Apple silicon | Apple Extensible SSO schema |
| PRK/recoveryOS can recover a system when live IdP authentication is unavailable | Apple Platform SSO deployment guide and FileVault security guide |
| Microsoft requires Intune/Company Portal and distinguishes Secure Enclave from password synchronization | Microsoft Intune Platform SSO guide |
| Okta requires its Device Access/Verify and MDM integration | Okta Platform SSO documentation |
| Jamf Connect can deny local authentication or permit fallback, and FileVault unlock precedes its login window | Jamf Connect local/network and FileVault documentation |
| No native family weekly Login Window condition was found in the provider paths reviewed | Inference from the cited Microsoft, Okta, and Jamf configuration/condition documentation; this is not a universal impossibility claim |

## Authoritative sources reviewed

Reviewed 2026-09-03. Apple sources govern platform capability; vendor sources describe representative implementations.

- [Apple Platform SSO for macOS](https://support.apple.com/guide/deployment/platform-sso-for-macos-dep7bbb05313/1/web/1.0)
- [Apple: Configuring Platform Single Sign-on](https://developer.apple.com/documentation/devicemanagement/configuring-platform-single-sign-on)
- [Apple device-management schema: Extensible SSO](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.extensiblesso.yaml)
- [Apple device-management schema: Login Window](https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.loginwindow.yaml)
- [Apple: Managing FileVault in macOS](https://support.apple.com/en-lamr/guide/security/sec8447f5049/web)
- [Apple: Disable automatic login when FileVault is on](https://support.apple.com/en-us/102001)
- [Microsoft: Configure Platform SSO for macOS devices](https://learn.microsoft.com/en-us/intune/intune-service/configuration/platform-sso-macos)
- [Microsoft: Platform SSO scenarios for macOS devices](https://learn.microsoft.com/en-us/intune/device-configuration/settings-catalog/configure-platform-sso-scenarios-macos)
- [Microsoft: Conditional Access conditions](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-conditions)
- [Okta: Platform Single Sign-On for macOS](https://help.okta.com/oie/en-us/content/topics/oda/macos-pw-sync/about-psso.htm)
- [Okta: Platform SSO version history](https://help.okta.com/oie/en-us/content/topics/oda/macos-pw-sync/about-psso-version-history.htm)
- [Jamf Connect: Local and network authentication](https://learn.jamf.com/r/en-US/jamf-connect-documentation-current/Local_and_Network_Authentication_Management_Settings)
- [Jamf Connect: FileVault-encrypted computer logins](https://learn.jamf.com/r/en-US/jamf-connect-documentation-current/Logins_on_FileVault_Encrypted_Computers)
- [Jamf Connect: Disable automatic FileVault login](https://learn.jamf.com/r/en-US/jamf-connect-documentation-current/Disabling_Automatic_FileVault_Login)
- [Jamf Connect: Recover a locked computer](https://learn.jamf.com/r/en-US/jamf-connect-documentation-current/Disabling_Jamf_Connect_on_Locked_Computers)
