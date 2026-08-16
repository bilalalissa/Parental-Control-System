# Capability matrix

This matrix is the truthful Stage 04 capability contract and forward plan.

| Capability | Parent Controller (Apple silicon) | macOS child endpoint | Windows child endpoint | Standard iPadOS child app | Optional supervised iPad MDM |
| --- | --- | --- | --- | --- | --- |
| Visible installed UI | Native SwiftUI | Required | Required | Required | MDM profile plus visible child app where applicable |
| Local controller authority | Yes | No | No | No | No |
| Local SQLite operational store | Yes | Endpoint cache only | Endpoint cache only | App Group storage where supported | Server/profile specific |
| Secure secret storage | Keychain | Keychain | DPAPI/Credential Manager | Keychain | External certificate lifecycle required |
| Authenticated LAN pairing/status | Hub role | Outbound endpoint | Outbound endpoint | While app/framework delivery permits | Supported management channel |
| Offline signed-policy enforcement | Authority/source | Planned | Planned | Family Controls schedules/shields | Supported restrictions |
| Continuous presence | Controller itself | Heartbeat-based | Heartbeat-based | **No; approximate only** | Management check-in is not continuous app presence |
| Boot time / reliable uptime | Local Mac only | Stage 03+ | Planned | **Not available** | Device information only where supported |
| Login/logout/lock state | Local Mac only | Stage 03+ session state | Planned | **Not available** | Not desktop session semantics |
| Foreground/running applications | Controller process only | Stage 04 candidate; names/bundle IDs only | Metadata planned | **Not available** | **Not available** |
| Browser-tab metadata | Controller browser is out of scope | Visible Chrome/Edge extension only | Visible Chrome/Edge extension only | **Not available** | **Not available** |
| Hardware MAC metadata | Local interfaces | Optional display metadata | Optional display metadata | **Not available** | Only if a supported command returns it; never identity |
| Text chat | Parent UI | Stage 04 candidate; direct/group/announcement | Planned | While active; notifications best effort | Through visible child app only |
| Request more time | Stage 04 request display; decision/enforcement later | Stage 04 candidate | Planned | Planned with Family Controls flow | Through visible child app only |
| Lock | Local controller session only | Supported API planned | Supported API planned | Shielding only; not global device lock | Supported command only after approval |
| Logoff | Local controller session only | Planned | Planned | **Not available** | **Not available as desktop logoff** |
| Restart/shutdown | Local controller Mac only | Explicit supported action | Explicit supported action | **Not available** | Supported supervised commands only |
| Startup | Login item | launchd/Service Management | Service plus per-user UI | **No persistent boot agent** | OS-managed profile/check-in |

Unknown and unsupported capabilities are disabled and explained in the controller UI. An unreachable endpoint is `Offline`, never inferred to be powered off.
