# Capability matrix

This matrix is the truthful Stage 06 capability contract and the Stage 06A/06B feasibility result.

| Capability | Parent Controller (Apple silicon) | macOS child endpoint | Windows child endpoint | Standard iPadOS child app | Optional supervised iPad MDM |
| --- | --- | --- | --- | --- | --- |
| Visible installed UI | Native SwiftUI | Required | Required | Required | MDM profile plus visible child app where applicable |
| Local controller authority | Yes | No | No | No | No |
| Local SQLite operational store | Yes | Endpoint cache only | Endpoint cache only | App Group storage where supported | Server/profile specific |
| Secure secret storage | Keychain | Keychain | DPAPI/Credential Manager | Keychain | External certificate lifecycle required |
| Authenticated LAN pairing/status | Hub role | Outbound endpoint | Outbound endpoint | While app/framework delivery permits | Supported management channel |
| Offline signed-policy enforcement | Signs per-device policy | Stage 06 verified root-protected cache and local evaluator | Planned | Family Controls schedules/shields | Supported restrictions |
| Continuous presence | Controller itself | Heartbeat-based | Heartbeat-based | **No; approximate only** | Management check-in is not continuous app presence |
| Boot time / reliable uptime | Local Mac only | Stage 03+ | Planned | **Not available** | Device information only where supported |
| Login/logout/lock state | Local Mac only | Stage 03+ session state | Planned | **Not available** | Not desktop session semantics |
| Foreground/running applications | Controller process only | Stage 04 candidate; names/bundle IDs only | Metadata planned | **Not available** | **Not available** |
| Browser-tab metadata | Controller browser is out of scope | Stage 05 visible Chrome/Edge/Arc extension; title/origin only | Visible Chrome/Edge extension planned | **Not available** | **Not available** |
| Hardware MAC metadata | Local interfaces | Optional display metadata | Optional display metadata | **Not available** | Only if a supported command returns it; never identity |
| Text chat | Stage 05 direct/group/announcement with system-controlled sound and explicit read state | Stage 05 direct/group/announcement with system-controlled sound and explicit read state | Planned | While active; notifications best effort | Through visible child app only |
| Request more time | Stage 04 request display; decision/enforcement later | Stage 04 candidate | Planned | Planned with Family Controls flow | Through visible child app only |
| Lock | Sends authenticated typed request | Stage 06 system screen-saver lock path; open apps preserved | Supported API planned | Shielding only; not global device lock | Supported command only after approval |
| Logoff | Explicit confirmation required | Stage 06 documented loginwindow confirmation; never forced | Planned | **Not available** | **Not available as desktop logoff** |
| Restart/shutdown | Explicit confirmation required | Stage 06 documented loginwindow confirmation; never forced | Explicit supported action | **Not available** | Supported supervised commands only |
| Startup | Login item | launchd/Service Management | Service plus per-user UI | **No persistent boot agent** | OS-managed profile/check-in |
| Prevent ordinary local child login outside a weekly schedule | Not implemented | **Not provided by Stage 06; Stage 06A local-account and Stage 06B managed-identity paths do not meet the offline schedule requirement** | Planned policy enforcement does not imply pre-logon denial | **Not available to a normal app** | Not an iPad login concept |
| Require live IdP authentication for a managed child at Login Window | No product integration | **Conditionally available with macOS 15 Platform SSO Password policy, MDM, IdP, and compatible extension; unverified and not implemented** | Not evaluated | Not applicable | Not applicable |
| Evaluate the signed weekly schedule while offline at Login Window | Local policy exists but is not an authentication provider | **Not available through Platform SSO; offline grace is day-based and no-grace denies all offline login** | Not evaluated | Not applicable | Not applicable |
| Independent offline adult recovery from managed child login policy | Parent retains lawful administration | **Architecturally possible with excluded local administrator, FileVault PRK, and recoveryOS; unverified** | Not evaluated | Not applicable | Not applicable |

Unknown and unsupported capabilities are disabled and explained in the controller UI. An unreachable endpoint is `Offline`, never inferred to be powered off.

Stage 06A found that macOS `LoginWindow` payload `AllowList` and `DenyList` apply only to network and mobile accounts, not ordinary local accounts, and the payload contains no weekly schedule or automatic expiry. Broadly disabling local login would also threaten the required adult recovery administrator. Manual third-party MDM enrollment is therefore not represented as a supported local-child scheduling capability.

Stage 06B found that Platform SSO `RequireAuthentication` is a meaningful online authentication gate and that `NonPlatformSSOAccounts` can exempt a separate local adult recovery administrator. It still has no weekly time-window input, cannot consume the Parent Controller's signed policy, and offers only whole-day offline grace or total offline denial. The Platform SSO FileVault policy is limited to Apple silicon. The design is therefore a no-go for the exact local/offline schedule requirement and only a conditional candidate for a separately approved online pilot.
