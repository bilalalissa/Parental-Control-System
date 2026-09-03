# ADR-0001: Reject selective local-account scheduling through the macOS Login Window MDM payload

- Status: Accepted for STAGE-06A feasibility
- Date: 2026-09-01
- Stage: STAGE-06A
- Owners: project maintainers

## Context

Stage 06 can warn and re-lock a logged-in standard child account, but it does not control authentication at the macOS Login Window. The developer authorized a bounded feasibility evaluation of manual enrollment with a third-party MDM before STAGE-07. The desired outcome was to deny only the child's ordinary local account outside a weekly schedule while ensuring that an adult recovery administrator can always log in.

Apple documents `com.apple.loginwindow` as a device-channel payload that can be manually installed on macOS. Its detailed property contract states that `AllowList` and `DenyList` contain user or group GUIDs and apply only to network accounts and mobile accounts. They do not selectively deny an ordinary local child account. The payload exposes no weekly schedule or automatic expiry. The broad `LocalUserLoginEnabled` setting is not an acceptable substitute because disabling local login would also threaten the local adult recovery path.

Manual Device Enrollment can make a modern Mac managed and supervised, but an authorized administrator can remove manually enrolled management. Non-removable enrollment requires Automated Device Enrollment. This project continues to treat administrator removal as an honest platform boundary rather than attempting to defeat it.

Sources reviewed on 2026-09-01:

- [Apple LoginWindow payload contract](https://developer.apple.com/documentation/devicemanagement/loginwindow)
- [Apple Login Window deployment settings](https://support.apple.com/en-gb/guide/deployment/dep2a822b29/1/web/1.0)
- [Apple MDM enrollment profile deployment](https://developer.apple.com/documentation/devicemanagement/deploying-device-management-enrollment-profiles)
- [SimpleMDM API reference](https://api.simplemdm.com/v1)
- [SimpleMDM enrollment options](https://simplemdm.com/features/device-enrollment/)
- [Jamf Now manual Mac enrollment](https://learn.jamf.com/r/en-US/jamf-now-documentation/Enrolling_a_Mac_Without_Using_Open_Enrollment)
- [Jamf Now product boundary](https://learn.jamf.com/r/en-US/jamf-now-documentation/About_Jamf_Now)

## Decision

Do not enroll a physical Mac or deploy a Login Window restriction for the proposed local-account design. It cannot satisfy the selective-account acceptance criterion, and a broad local-login denial cannot satisfy the mandatory local recovery criterion.

No MDM account, APNs certificate, API key, configuration profile, device record, or external identifier is created in STAGE-06A. No Parent Controller or child-endpoint code integrates with a vendor.

SimpleMDM remains only a researched candidate for a future, separately approved managed-account experiment because it documents link enrollment and per-device custom-profile assignment/removal. Its public API also exposes destructive device operations, including wipe. A future integration must demonstrate a credential restricted to the exact profile operations before any API key is stored or used. Jamf Now supports manual enrollment and custom profiles but currently documents no public API, so it is not suitable for Parent Controller automation.

## Alternatives considered

- **Use `DenyList` with the child's local short name:** rejected because Apple's detailed contract limits the key to network and mobile accounts.
- **Disable all local login with `LocalUserLoginEnabled`:** rejected because it can deny the adult recovery administrator and create a cloud-dependent lockout.
- **Push a scheduled MDM script that disables the local account:** rejected because it introduces arbitrary privileged scripting, unsafe rollback, and an external availability dependency contrary to the product security boundary.
- **Use a network/mobile account or Platform SSO:** potentially feasible, but it requires an identity service, account migration, FileVault/secure-token analysis, and a separately approved managed-identity stage.
- **Automated Device Enrollment:** improves enrollment persistence but does not change the local-account and scheduling limitations; it also requires Apple Business Manager or Apple School Manager and is outside this manual-enrollment stage.
- **Continue the Stage 06 local agent's warning and re-lock behavior:** remains the supported local-first option. It cannot honestly prevent a child who knows the local password from authenticating at the Login Window.

## Consequences

The feasibility stage ends without exposing a device or family data to a third party and without producing an installer. The requested pre-login guarantee remains unavailable for ordinary local accounts. Stage 07 remains gated.

A future proposal may evaluate managed network/mobile identity or Platform SSO, but it must preserve an offline adult recovery route, define FileVault behavior, avoid broad destructive credentials, and receive a new roadmap and external-service approval.

## Validation

- Repository tests require this limitation, recovery boundary, and absence of product integration to remain documented.
- `plutil`/configuration-profile deployment and physical enrollment are intentionally not run because the source-level platform gate fails first.
- No next implementation stage begins without explicit developer approval.
