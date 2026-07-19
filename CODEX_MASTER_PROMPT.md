# Codex Master Build Prompt — Parental Control System

## 1. Role and operating mode

You are the lead software architect, security engineer, release engineer, and implementation agent for a greenfield, privacy-preserving, cross-platform parental-control system.

Repository:

- GitHub: `bilalalissa/Parental-Control-System`
- Default branch: `main`
- The repository is public. Never commit credentials, signing certificates, provisioning profiles, APNs keys, device identifiers from real family devices, chat history, IP/MAC-address logs, screenshots containing private data, or any other secret or personally identifiable information.
- Working product name: **Parental Control System**
- Temporary reverse-DNS identifier prefix: `com.bilalalissa.parentalcontrol`
- Replace the working name or identifier only through a documented architecture decision.

The system has one parent/controller application and several child endpoint applications:

1. **Parent Controller for macOS**, optimized for Apple silicon.
2. **macOS Child Agent**, shipped as a universal application for Apple silicon and Intel Macs.
3. **Windows Child Agent**, initially for Windows x64, with ARM64 readiness documented.
4. **iPadOS Child App**, designed for iPad Pro and implemented only through public Apple APIs.
5. Optional, separately approved **supervised iPad MDM track** for features that a normal iPad app cannot provide.

Work in strict, reviewable stages. Complete only one stage at a time. At the end of every stage, produce installable developer artifacts, tests, documentation, and a GitHub pull request, then stop for developer testing. Do not begin the next stage until the developer explicitly approves the current stage.

---

## 2. Product mission

Build a parent-controlled system in which the main macOS application can pair with enrolled child devices and provide a clear, honest view of each device’s status and permitted activity.

Required product capabilities, where the operating system allows them:

- Secure device enrollment and pairing.
- Current online/offline status and last-seen time.
- Device boot time and uptime.
- Best-effort offline duration based on the last successful heartbeat.
- Logged-in/logged-out or active-session status on desktop operating systems.
- Device name, model, operating-system version, architecture, local IP addresses, and available network-interface MAC addresses.
- Current foreground application and list of running user applications on macOS and Windows.
- Browser-tab metadata only through an explicitly installed, visible browser extension on supported desktop browsers.
- Parent-child text chat.
- Weekly allowed-use windows.
- Daily usage quota.
- Bedtime or blocked periods.
- One-time bonus time.
- Parent-triggered lock, logoff, restart, or shutdown when supported.
- Advance warnings before enforcement.
- Local enforcement when the controller is offline, using the last valid signed policy.
- Visible endpoint status and child-readable schedule.
- Endpoint settings remain read-only to the child unless:
  - the parent approves a change remotely; or
  - an authorized adult enters a local security code in the endpoint application.
- Automatic startup using supported operating-system mechanisms.
- Original icon sets for the parent application and endpoint applications.
- Audit history for policy changes, overrides, commands, connection events, and enforcement results.

Do not describe a device as “powered off” merely because it is unreachable. Show `Offline` plus the last-seen timestamp. Use `Shutdown confirmed` only when the endpoint acknowledged a shutdown command or sent a reliable shutdown event before disconnecting.

---

## 3. Safety, transparency, and non-goals

This is a transparent parental-control product for devices owned or lawfully administered by the parent or guardian. It is not a covert surveillance product.

Never implement any of the following:

- Hidden or disguised installation.
- Stealth persistence.
- Keylogging.
- Screen capture or continuous screenshots.
- Microphone or camera recording.
- Clipboard capture.
- Reading email, messages, documents, passwords, form fields, or file contents.
- TLS interception or installation of a man-in-the-middle root certificate.
- Browser-history scraping outside the declared browser-extension permission model.
- Private Apple APIs.
- Security bypasses, kernel exploits, credential theft, anti-malware evasion, or disabling built-in platform security.
- An arbitrary remote shell, command prompt, PowerShell execution, AppleScript execution, or unrestricted process launcher.
- Remote file browsing or file transfer in the initial product.
- A hidden master override code.
- Hard-coded credentials or default production passwords.

The endpoint application must be visible in the installed-app list. The child-facing UI must identify that parental controls are active, show the current schedule, explain what metadata is shared, and provide a chat/request-more-time interface.

Document that a child with local administrator/root access can ultimately remove or alter desktop software. Strong desktop enforcement requires that the child use a standard, non-administrator OS account. Do not attempt to defeat an authorized local administrator.

---

## 4. Platform capability contract

Treat platform limitations as product requirements. Never fake or overstate a capability.

### macOS endpoint

Supported design:

- Universal `arm64` and `x86_64` build.
- System LaunchDaemon for privileged, boot-time work.
- Per-user LaunchAgent or login item for UI/session interaction.
- XPC or another authenticated local IPC boundary between privileged and user components.
- Public macOS APIs only.
- Running-app and foreground-app metadata.
- Desktop browser tabs only through explicit Safari Web Extension or Chromium/Firefox WebExtension plus native messaging.
- Lock, logoff, restart, and shutdown through supported APIs or narrowly scoped privileged helper operations.
- Startup item registration through current Service Management APIs where available.
- Visible background-item status and clear installation/uninstallation documentation.

### Windows endpoint

Supported design:

- Windows Service with automatic startup for protected background operations.
- Per-user tray or desktop UI launched at user logon.
- Authenticated named-pipe IPC between service and UI.
- Session-change notifications for logon, logoff, lock, and unlock.
- Running-app and foreground-window metadata.
- Browser tabs only through explicit browser extensions and native messaging.
- Lock, logoff, restart, and shutdown through documented Windows APIs.
- Installer requires administrator elevation.
- Service files, configuration, and IPC endpoints protected with least-privilege ACLs.
- Child account is expected to be a standard user.

### iPadOS standard-app track

A normal iPadOS app is not an always-running desktop agent. Implement only what Apple permits:

- SwiftUI application.
- Family Controls authorization.
- Device Activity schedules and monitoring.
- Managed Settings shields for selected applications, categories, and web domains.
- Managed Settings UI and Shield Action extensions.
- Parent-child chat through the application and APNs/local notifications.
- Best-effort presence only. Background execution and notification delivery are not continuous or guaranteed.
- No hardware MAC address from the normal app.
- No reliable system uptime.
- No desktop-style logged-in/logged-out state.
- No list of currently open applications.
- No current browser-tab list.
- No ordinary-app ability to shut down, restart, or globally log out the iPad.
- No claim that the app starts as a persistent agent at boot.
- App/category selections that depend on Apple privacy-preserving tokens must be selected and authorized on the iPad through the supported Family Controls flow.
- Distribution requires Apple approval for the Family Controls entitlement. A simulator or development archive is not equivalent to an installable production build.

### Optional supervised iPad MDM track

Do not start this track without explicit approval after the standard iPadOS stages.

A supervised-device MDM implementation may add supported device-management functions such as managed app installation, some device-information queries, device lock, restart, or shutdown. It still must not claim access to current apps or browser tabs. It requires a separate MDM server design, APNs MDM credentials, signed enrollment profiles, TLS hosting, supervision/enrollment procedures, and careful certificate handling.

All MDM credentials and real device identifiers must remain outside the public repository and must be supplied only through secure local configuration or GitHub Actions secrets.

---

## 5. Recommended architecture

Use a monorepo with explicit platform boundaries and a shared protocol.

Recommended top-level layout:

```text
/
├── AGENTS.md
├── README.md
├── SECURITY.md
├── PRIVACY.md
├── LICENSE
├── .editorconfig
├── .gitignore
├── .github/
│   ├── workflows/
│   ├── ISSUE_TEMPLATE/
│   └── pull_request_template.md
├── apps/
│   ├── controller-macos/
│   └── endpoint-ipados/
├── agents/
│   ├── endpoint-macos/
│   └── endpoint-windows/
├── browser-extensions/
│   ├── webextension/
│   └── safari/
├── services/
│   ├── controller-hub/
│   └── relay/                  # future, do not implement early
├── packages/
│   ├── protocol/
│   ├── policy-engine-spec/
│   ├── test-fixtures/
│   └── design-assets/
├── installers/
│   ├── macos/
│   ├── windows/
│   └── ipados/
├── docs/
│   ├── architecture/
│   ├── adr/
│   ├── security/
│   ├── privacy/
│   ├── stages/
│   ├── testing/
│   ├── installation/
│   └── releases/
└── tools/
```

### Parent Controller

Prefer a native Swift/SwiftUI macOS application. The controller UI may launch or communicate with a local controller-hub service. The hub owns:

- Device connections.
- Pairing.
- Local database.
- Policy distribution.
- Command queue.
- Chat routing.
- Audit log.
- Capability negotiation.
- Optional LAN discovery.

Use SQLite for local persistence. Enable migrations from the first schema version. Store sensitive local controller secrets in Keychain, not SQLite.

The parent controller is the authority. The initial product is **LAN-first**. Child agents should make outbound authenticated connections to the controller, avoiding open unauthenticated inbound administration ports on child devices. Prepare protocol abstractions for a future relay, but do not build a public-cloud relay until its dedicated stage is approved.

### macOS endpoint

Prefer native Swift for the macOS UI, daemon, LaunchAgent, and platform adapters. Build one universal package containing:

- A visible endpoint app.
- A system daemon for boot-time heartbeat, protected policy storage, command validation, and privileged enforcement.
- A per-user helper for session metadata, chat notifications, warnings, and user-level actions.
- Authenticated IPC.
- A documented uninstaller requiring administrator authorization.

### Windows endpoint

Prefer C# on the current supported .NET LTS release, pinned in `global.json`, with:

- Windows Service.
- Per-user WPF or WinUI desktop/tray app; choose one and record the decision.
- Authenticated named-pipe IPC.
- WiX-based MSI or another well-supported installer technology; choose and document.
- Secure storage through DPAPI or Windows Credential Manager.
- Event Log integration and structured local logs.

### iPadOS endpoint

Use Swift/SwiftUI and the Screen Time technology frameworks:

- FamilyControls.
- DeviceActivity.
- ManagedSettings.
- ManagedSettingsUI.
- App extensions required for monitoring and shields.
- APNs and local notifications for chat and parent-approved changes.
- Keychain for device identity.
- App Group storage for the app and extensions.

### Shared protocol

Define an inspectable, versioned protocol before production agents:

- HTTPS for enrollment and ordinary request/response operations.
- Secure WebSocket for live presence, commands, command receipts, snapshots, and chat.
- JSON payloads validated by JSON Schema or OpenAPI components.
- Explicit protocol version and capability negotiation.
- Every message has:
  - `messageId`
  - `protocolVersion`
  - `deviceId`
  - `sentAtUtc`
  - `expiresAtUtc` where applicable
  - `sequence`
  - `type`
  - `payload`
  - authentication/integrity metadata
- Commands are typed and allowlisted. No arbitrary command execution.
- Commands are idempotent where possible.
- Receipts distinguish `accepted`, `started`, `succeeded`, `failed`, `expired`, `unsupported`, and `denied`.
- Unknown fields are handled safely.
- Incompatible protocol versions fail closed with a user-readable error.

Initial command allowlist:

- `requestSnapshot`
- `sendChatMessage`
- `applyPolicy`
- `requestPolicyStatus`
- `lockSession`
- `logoffSession`
- `restartDevice`
- `shutdownDevice`
- `grantBonusTime`
- `revokeBonusTime`
- `rotateLocalOverrideVerifier`
- `requestAgentDiagnostics`

Diagnostics must be bounded and privacy-safe. They may include application version, component health, recent error codes, and sanitized logs. They must not expose arbitrary files or secrets.

---

## 6. Enrollment and trust model

Implement explicit pairing. A device is never trusted solely because it is on the same network.

Recommended flow:

1. Parent selects **Add device** in the controller.
2. Controller creates a single-use enrollment invitation with:
   - short human-readable code;
   - QR representation;
   - controller identity fingerprint;
   - expiration no longer than 10 minutes.
3. Endpoint displays the controller identity and asks for adult confirmation during installation/enrollment.
4. Endpoint creates its own asymmetric device key in secure platform storage.
5. Controller and endpoint establish a TLS-protected channel, verify the invitation, exchange public keys, and bind a unique device identity.
6. Controller issues a scoped device credential or certificate.
7. Enrollment invitation is invalidated immediately.
8. Every subsequent connection authenticates both controller and device.
9. Re-pairing or controller transfer requires adult authorization and is audit logged.

Security requirements:

- TLS 1.3 where supported.
- Per-device credentials.
- Keychain on Apple platforms.
- DPAPI or Windows Credential Manager on Windows.
- No reusable pairing code.
- Rate-limit pairing attempts.
- Replay protection through sequence numbers, expiration, and unique message IDs.
- Certificate or key rotation support.
- Revocation support.
- Controller-side device removal invalidates future connections.
- Endpoint reset requires local administrator or adult override.
- Never log private keys, tokens, complete pairing codes, or override codes.

---

## 7. Local adult security code

The endpoint UI is child-readable but settings are not child-editable.

Implement two adult authorization paths:

1. **Remote parent approval**: a signed, authenticated approval from the paired controller.
2. **Local adult security code**: manually entered in the endpoint UI and validated by the privileged component or secure app component.

Rules:

- No built-in default code.
- Parent creates or rotates the code from the controller or during adult-authorized setup.
- Store only a memory-hard verifier, not plaintext. Use an appropriate platform-supported password hashing/KDF design and record the parameters.
- Rate-limit attempts.
- Introduce increasing delay after failures.
- Audit successful and failed authorization attempts without recording the attempted code.
- Adult authorization creates a short-lived scoped session, not unlimited permanent access.
- High-impact actions such as unpairing, disabling enforcement, changing the child account mapping, or uninstalling still require OS administrator authorization where applicable.
- A forgotten code is recovered through an authenticated parent-controller reset or administrator-assisted re-enrollment. Do not create a universal backdoor.

---

## 8. Device telemetry and privacy model

Use capability-driven snapshots so every platform reports only what it can reliably provide.

Common snapshot fields:

- `deviceId`
- `displayName`
- `agentVersion`
- `protocolVersion`
- `platform`
- `osVersion`
- `architecture`
- `model`
- `hostName` when permitted
- `bootId`
- `bootTimeUtc` when permitted
- `uptimeSeconds` when permitted
- `presenceState`
- `lastSeenUtc`
- `sessionState`
- `activeUserDisplayName` with privacy controls
- `networkInterfaces`
- `foregroundApplication`
- `runningApplications`
- `browserTabs`
- `effectivePolicyVersion`
- `enforcementState`
- `capabilities`
- `limitations`
- `health`

Network interface data:

- Include interface name/type, private IP, and MAC only where supported and explicitly enabled.
- Do not treat randomized Wi-Fi addresses as permanent identity.
- Do not use MAC address as an authentication credential.
- The controller may display the observed network peer address separately from the endpoint-reported local addresses.
- Public IP lookup is out of scope for the LAN-first product.

Application metadata:

- Desktop running-app entries may include bundle/package ID, process display name, executable signature/publisher when available, foreground flag, and start time.
- Do not collect command-line arguments.
- Do not collect window text except a browser-tab title supplied by the approved extension.
- Do not collect document names from application windows.
- Default retention for detailed application activity should be short and configurable.
- Make activity collection individually toggleable per child device.

Browser extension rules:

- Separate, visible installation and permission disclosure.
- Support Chrome and Edge first; Firefox and Safari may follow in separately approved work.
- Use native messaging to the local endpoint agent.
- Collect only the active tab or explicitly requested open-tab list.
- Default fields: browser, profile pseudonym, tab title, origin/domain, active flag, and timestamp.
- Remove URL fragments and query strings.
- Private/incognito browsing is excluded.
- Never read page contents, form fields, cookies, stored passwords, or network traffic.
- Parent can disable browser-tab collection independently of app monitoring.
- Endpoint UI shows whether the extension is installed and whether tab sharing is active.

Presence:

- Desktop heartbeat target: every 15 seconds while connected.
- Controller marks a desktop endpoint stale after 45 seconds and offline after 75 seconds, configurable.
- iPad presence is approximate and must be labeled as such.
- Persist connection intervals and explicit shutdown/logoff events.
- Calculate “offline for” from last seen, not as proof of power state.

---

## 9. Policy and schedule engine

Create a platform-neutral policy specification and deterministic reference tests before implementing platform enforcement.

Policy supports:

- Weekly allowed-use windows.
- Daily maximum active-use quota.
- Bedtime/blocked periods.
- One-time date-specific exceptions.
- Bonus minutes.
- Parent immediate lock.
- Parent temporary unlock.
- Enforcement action:
  - warn only;
  - lock;
  - logoff;
  - shutdown.
- Warning offsets, defaulting to 15, 5, and 1 minute.
- Grace period.
- Per-device timezone.
- Policy version and signature.
- Effective date.
- Expiration or review date.
- Child-readable explanation.

Policy evaluation must cover:

- Time zones.
- Daylight-saving transitions.
- Midnight crossing.
- Multiple allowed windows in one day.
- Sleep and resume.
- Reboot.
- Controller unavailable.
- Device clock moved forward or backward.
- Monotonic elapsed time.
- Network loss during a warning period.
- Policy update race conditions.
- Replayed or older policy.
- Manual parent command conflicting with schedule.
- Bonus-time exhaustion.
- Multiple logged-in desktop sessions.

Recommended precedence:

1. Valid short-lived adult local override.
2. Latest authenticated parent immediate command.
3. One-time signed exception.
4. Explicit blocked/bedtime interval.
5. Daily quota.
6. Recurring allowed-use window.
7. Default deny outside allowed windows.

Document any changes to this precedence in an ADR.

Enforcement behavior:

- Default action is lock, not shutdown.
- Never silently destroy unsaved work.
- Show warnings with exact remaining time.
- Attempt graceful logoff/shutdown first.
- Forced termination is a separate, disabled-by-default setting with prominent warning.
- Record command acceptance and final result.
- Cache the last valid signed policy locally and enforce it while offline.
- Reject expired, invalidly signed, or older policy versions.
- Detect suspicious wall-clock rollback and use monotonic time plus last trusted controller time when possible.
- If safe evaluation is impossible, apply the documented conservative behavior and show the reason.

iPadOS maps the schedule to Device Activity and Managed Settings shields. It does not pretend to perform desktop login/logout or device shutdown in the standard-app track.

---

## 10. Chat

Initial chat is text-only.

Requirements:

- One conversation per child device.
- Controller-to-endpoint and endpoint-to-controller.
- Delivery states: queued, sent, delivered, read, failed.
- Offline queue with bounded retention.
- Local notifications on supported platforms.
- APNs for iPad.
- Message timestamps in UTC, displayed in local time.
- Message length limit.
- No attachments in the initial implementation.
- No links automatically opened.
- No arbitrary HTML.
- Messages encrypted in transit and protected at rest using platform storage/database encryption strategy.
- Clear retention setting and delete-conversation action.
- Audit log records message metadata, not duplicate message contents.

---

## 11. User experience

### Parent Controller screens

At minimum:

1. **Dashboard**
   - device cards;
   - online/offline/approximate status;
   - last seen;
   - logged-in state where supported;
   - uptime;
   - active user;
   - foreground app;
   - next restriction;
   - policy health.
2. **Device details**
   - hardware/OS;
   - IP/MAC data with availability explanation;
   - component versions;
   - capabilities and limitations;
   - running apps;
   - browser tabs where enabled;
   - connection history;
   - enforcement history.
3. **Schedule**
   - weekly editor;
   - quota;
   - bedtime;
   - one-time exception;
   - bonus time;
   - warning/action settings;
   - preview of effective policy.
4. **Chat**
5. **Actions**
   - refresh;
   - lock;
   - logoff;
   - restart;
   - shutdown;
   - grant time;
   - rotate local code;
   - unpair.
   - destructive actions require confirmation and show support/limitations.
6. **Audit log**
7. **Settings**
   - startup;
   - retention;
   - network/listen settings;
   - export diagnostics;
   - update channel.

### Endpoint UI

At minimum:

- Visible status: connected, disconnected, or approximate.
- Device name and controller name/fingerprint.
- Today’s allowed time and remaining quota.
- Next warning or restriction.
- Current enforcement state.
- Chat.
- Request more time.
- Privacy disclosure: exactly what is currently shared.
- Agent/component health.
- Adult unlock entry.
- Read-only settings for a child.
- Clear error messages if a service, extension, entitlement, or permission is missing.

### Accessibility and localization

- Support keyboard navigation and screen readers.
- Avoid color-only status.
- Use semantic labels.
- Centralize strings for future localization.
- Use locale-aware date/time formatting.
- Store timestamps in UTC.

### Icons and brand assets

Create original, simple, non-infringing icon artwork:

- Parent Controller icon.
- Child Agent icon.
- Optional browser-extension icon.
- Shared visual family with clear role distinction.
- Vector source in `packages/design-assets`.
- Generated macOS `.appiconset`/`.icns`, iPadOS AppIcon asset catalog, Windows `.ico`, installer images, and required PNG sizes.
- No text inside the icon.
- Include an asset-generation script and verify required sizes in CI.
- Do not use third-party trademarked artwork.

---

## 12. Logging, diagnostics, and audit

Use structured logs with severity and stable event IDs.

Rules:

- Redact secrets and authentication material.
- Redact full pairing/override codes.
- Avoid logging chat content by default.
- Avoid logging complete URLs.
- Rotate local logs and enforce size limits.
- Provide a user-triggered sanitized diagnostic bundle.
- Diagnostic bundles must be reviewable before export.
- On macOS, use unified logging where appropriate.
- On Windows, integrate with Event Log where appropriate.
- iPad logs remain bounded and privacy-safe.

Audit events include:

- Enrollment and unpair.
- Controller identity change.
- Policy created/changed/applied/rejected.
- Adult override success/failure.
- Manual action requested/accepted/completed/failed.
- Agent update.
- Service stopped or unhealthy.
- Permission/entitlement change.
- Browser extension connected/disconnected.
- Time-tampering warning.
- Data-retention deletion.

---

## 13. Engineering quality and security gates

For every production stage:

- Compile with warnings treated as errors where practical.
- Format and lint.
- Unit tests.
- Integration tests.
- Protocol contract tests.
- Policy golden tests.
- Installer smoke tests where the CI runner supports them.
- Static analysis.
- Dependency vulnerability scan.
- Secret scan.
- License inventory.
- SBOM generation.
- SHA-256 checksums for artifacts.
- Reproducible build notes.
- No critical or high-severity unresolved security findings without explicit developer acceptance.
- No test disabled merely to make CI green.
- No placeholder “success” when the native toolchain or signing environment is unavailable.

Use a threat model covering:

- Malicious device on the LAN.
- Stolen enrollment code.
- Replay.
- Compromised child standard account.
- Child attempting to stop UI or service.
- Local administrator.
- Tampered policy/database.
- Clock rollback.
- Controller loss.
- Controller database theft.
- Malicious browser-extension message.
- Dependency compromise.
- Update-package tampering.
- Public-repository secret exposure.

Use least privilege. Privileged components must expose narrow, allowlisted operations over authenticated IPC. UI processes must never run as root/LocalSystem.

---

## 14. Build, packaging, signing, and releases

### General

- Semantic versioning.
- Stage release candidates may use `v0.x.0-rc.n`.
- Embed application version, protocol version, and build commit.
- Produce checksums and release notes.
- Produce install and uninstall instructions.
- Never place signing material in the repository.
- Use GitHub Actions secrets only after the developer configures them.
- Unsigned or ad-hoc developer builds must be labeled clearly.

### macOS

Produce:

- Parent Controller `.app` archive and developer `.pkg` or `.dmg`.
- Universal macOS Child Agent `.pkg`.
- Uninstaller or documented administrator removal tool.
- Architecture verification with `lipo` or equivalent.
- Code-signing verification steps.
- Notarization only after Developer ID credentials are configured securely.

### Windows

Produce:

- x64 MSI.
- Portable diagnostic build only if useful, but it must not bypass installation/service security.
- Installer log instructions.
- Authenticode signing only after a signing certificate is configured securely.

### iPadOS

Produce:

- Simulator build for automated UI/testing where useful.
- Xcode archive or development `.ipa` only when valid signing is configured.
- TestFlight/App Store distribution only after identifiers, profiles, APNs, and Family Controls entitlement are approved.
- Never call an unsigned simulator bundle an installable iPad release.

### GitHub Actions

Create platform-appropriate workflows:

- Documentation/protocol checks on Linux.
- macOS build/test on macOS runners.
- Windows build/test on Windows runners.
- iPad simulator/build checks on macOS runners.
- Artifact upload for every stage candidate.
- Release workflow triggered manually after approval.
- Concurrency controls to prevent duplicate release jobs.
- Minimal permissions.
- Pinned third-party actions by commit SHA where practical.
- Dependency caching without caching secrets.

---

## 15. Git and GitHub workflow

For each stage:

1. Synchronize from `main`.
2. Create branch `stage/<stage-id>-<short-name>`.
3. Create or update `docs/stages/<stage-id>.md`.
4. Implement only that stage’s approved scope.
5. Add tests and documentation.
6. Run all relevant checks.
7. Build developer artifacts.
8. Commit with focused messages.
9. Push the branch.
10. Open a draft pull request.
11. Include:
    - objective;
    - architecture decisions;
    - changed files/components;
    - security/privacy impact;
    - exact test commands and results;
    - artifact names and checksums;
    - installation steps;
    - uninstallation/rollback steps;
    - manual test checklist;
    - known limitations;
    - screenshots without private data.
12. Set project status to `READY_FOR_DEVELOPER_TEST`.
13. Stop.

Do not merge a stage PR or begin the next stage without explicit approval.

Track current state in `docs/stages/stage-status.json`:

```json
{
  "currentStage": "STAGE-00",
  "status": "READY_FOR_DEVELOPER_TEST",
  "version": "0.0.1-rc.1",
  "pullRequest": null,
  "artifacts": [],
  "approvedByDeveloper": false
}
```

Allowed stage states:

- `PLANNED`
- `IMPLEMENTING`
- `READY_FOR_DEVELOPER_TEST`
- `CHANGES_REQUESTED`
- `READY_FOR_RETEST`
- `APPROVED`
- `MERGED`
- `BLOCKED`

---

## 16. Mandatory stage completion response

At the end of every stage, respond using this exact structure and then stop:

```text
STAGE COMPLETION REPORT

Stage:
Status: READY_FOR_DEVELOPER_TEST
Version:
Branch:
Pull request:
Commit:
Supported test platforms:
Artifacts:
- filename
- purpose
- SHA-256
- signed/unsigned status

Implemented:
- ...

Not implemented in this stage:
- ...

Automated checks:
- command: result

Installation:
1. ...

Uninstallation / rollback:
1. ...

Manual developer test checklist:
1. ...

Known limitations:
- ...

Security and privacy notes:
- ...

Logs to collect if a test fails:
- ...

Feedback format:
STAGE FEEDBACK
Stage:
Version:
Platform and OS:
Hardware:
Result: PASS | FAIL | PARTIAL
Steps performed:
Expected:
Observed:
Logs:
Screenshots:
Requested changes:
Decision: CHANGES_REQUIRED | APPROVED

AWAITING DEVELOPER TEST RESULT
```

Do not claim a test passed unless it actually ran. Separate:

- locally executed checks;
- CI checks;
- checks that require physical hardware;
- checks blocked by missing signing credentials or entitlements.

---

## 17. Feedback and approval loop

When the developer sends feedback:

1. Confirm the stage and artifact version.
2. Reproduce or analyze the issue.
3. Update the same stage branch and pull request.
4. Add a regression test when practical.
5. Build a new release candidate.
6. Update checksums, release notes, and test instructions.
7. Respond with `READY_FOR_RETEST`.
8. Stop again.

Do not broaden scope while fixing feedback.

Approval command:

```text
APPROVED: <STAGE-ID> <VERSION>
```

After exact approval:

1. Mark stage status `APPROVED`.
2. Ensure all required checks are green.
3. Update final stage documentation and changelog.
4. Merge only when the developer explicitly adds `MERGE`.
5. Tag/release only when the developer explicitly adds `RELEASE`.
6. Begin the next stage only when the developer explicitly adds `PROCEED`.

Example:

```text
APPROVED: STAGE-03 0.3.0-rc.2
MERGE
RELEASE
PROCEED
```

If approval is ambiguous, do not assume it.

---

## 18. Detailed implementation stages

### STAGE-00 — Repository foundation and architecture

Objective:

- Initialize the empty repository into a buildable, documented monorepo.
- Create `AGENTS.md`, README, SECURITY, PRIVACY, contribution guidance, codeowners suggestion, PR template, issue templates, stage tracker, ADR template, threat model, capability matrix, and protocol/policy specifications.
- Record stack decisions for macOS, Windows, iPadOS, controller hub, database, IPC, installers, and browser extensions.
- Create mocked device fixtures and contract tests.
- Create CI skeleton.
- Create icon design brief and placeholder vector assets generated in-repo, clearly marked as initial.
- No privileged enforcement yet.

Acceptance:

- Repository structure exists.
- Documentation accurately states iPad limitations.
- Protocol schemas validate.
- Policy reference tests cover schedule edge cases.
- CI runs documentation, schema, secret, and lint checks.
- Developer can review architecture before implementation.

Deliverable version: `0.0.1-rc.1`.

### STAGE-01 — Parent Controller macOS UI shell

Objective:

- Build the native SwiftUI Parent Controller shell for Apple silicon.
- Implement local SQLite migrations and repositories.
- Use mock device data only.
- Implement Dashboard, Device Details, Schedule Editor shell, Chat shell, Audit shell, Settings, and capability/limitation presentation.
- Add controller icon set.
- Add accessibility identifiers and basic UI tests.
- Add startup-at-login option for the parent UI, but do not claim boot-time child management yet.

Acceptance:

- App launches on a clean supported macOS test account.
- Mock devices render all capability combinations.
- Schedule editor validates inputs.
- Database migration tests pass.
- Developer `.app` archive and `.dmg` or `.pkg` are produced.

Deliverable version: `0.1.0-rc.1`.

### STAGE-02 — Controller hub, secure pairing, and mock live agent

Objective:

- Implement controller-hub service, authenticated local UI-to-hub IPC, device database, LAN discovery, one-time pairing, secure WebSocket transport, heartbeat, snapshots, command receipts, and mock-agent CLI.
- Use test credentials only.
- Add controller identity display and fingerprint.
- Add device revoke/unpair.
- Add structured audit log.
- No real privileged endpoint behavior.

Acceptance:

- Two mock agents can pair concurrently.
- Stolen/expired/replayed enrollment codes fail.
- Replayed messages fail.
- Offline/last-seen states update correctly.
- Controller restart preserves trusted devices and policies.
- Installable controller artifact contains or installs the hub correctly.
- Mock agent artifact is clearly labeled non-production.

Deliverable version: `0.2.0-rc.1`.

### STAGE-03 — macOS Child Agent foundation, universal build

Objective:

- Build universal macOS endpoint package for Apple silicon and Intel.
- Implement visible endpoint app, LaunchDaemon, per-user helper, secure IPC, pairing, heartbeat, device info, boot time/uptime, session state, local IP/MAC data, health, logs, and read-only child dashboard.
- Start daemon at boot and user component at login through supported Service Management/launchd design.
- Secure local configuration.
- Add endpoint icon set.
- Add administrator installer/uninstaller.
- Do not implement app monitoring, browser tabs, chat, or schedule enforcement yet.

Acceptance:

- Universal binaries verified.
- Works after reboot with no user initially logged in.
- Reports login, logout, lock, and unlock transitions.
- Child standard user cannot edit protected configuration or stop the system daemon through the UI.
- Administrator can uninstall cleanly.
- Pairing/revocation tests pass.
- Developer `.pkg` produced with checksum and signing status.

Deliverable version: `0.3.0-rc.1`.

### STAGE-04 — macOS app activity and chat

Objective:

- Add foreground/running application metadata using public APIs.
- Add configurable collection and retention.
- Add two-way text chat and notifications.
- Add request-more-time flow.
- Add controller views and audit events.
- Do not add browser tabs or enforcement yet.

Acceptance:

- Running-app list updates without command-line or document-content collection.
- Collection can be disabled and endpoint disclosure updates.
- Chat queues offline and reports delivery state.
- Retention deletion works.
- Controller and endpoint artifacts produced.

Deliverable version: `0.4.0-rc.1`.

### STAGE-05 — Desktop browser extension, macOS integration

Objective:

- Implement Chromium WebExtension for Chrome and Edge first.
- Add native-messaging host in the macOS agent.
- Report active/open tab metadata under the privacy rules.
- Keep incognito/private browsing excluded.
- Add install/status guidance and controller UI.
- Safari extension is optional inside this stage only if it does not jeopardize the approved scope; otherwise create a future stage proposal.

Acceptance:

- Extension requires explicit install and permission.
- Agent rejects messages from unapproved extension identities.
- Query/fragment and content are not collected.
- User can disable tab sharing.
- Uninstalling extension removes tab data after retention policy.
- Extension package and host configuration included.

Deliverable version: `0.5.0-rc.1`.

### STAGE-06 — macOS policy enforcement and tamper resistance

Objective:

- Implement signed policy storage and deterministic evaluation.
- Add warnings, lock, logoff, optional restart, optional shutdown, bonus time, immediate lock/unlock, and local adult override.
- Default to lock.
- Implement clock-change detection, sleep/resume handling, reboot persistence, offline policy enforcement, command receipts, and audit.
- Use narrow privileged operations.
- Add schedule preview and enforcement status to both apps.

Acceptance:

- Schedule golden tests pass.
- Warning timings work.
- Offline enforcement works.
- Old/replayed/tampered policy rejected.
- Child standard user cannot change schedule or protected policy.
- Adult code is rate-limited and never logged.
- Unsaved-work behavior is documented.
- Lock/logoff/shutdown tested separately.
- Updated controller and agent packages produced.

Deliverable version: `0.6.0-rc.1`.

### STAGE-07 — Windows Child Agent foundation

Objective:

- Build Windows Service and visible per-user UI.
- Implement secure pairing, heartbeat, device information, boot time/uptime, logon/logoff/lock/unlock state, local IP/MAC data, health, logs, protected configuration, and read-only child dashboard.
- Use authenticated named pipes.
- Create x64 administrator MSI and uninstaller.
- Update controller capability UI.
- No app monitoring, browser tabs, chat, or enforcement yet.

Acceptance:

- Service starts automatically before user logon.
- UI starts at child logon.
- Session transitions report correctly.
- Standard user cannot modify protected files, service configuration, or named-pipe authorization.
- Administrator uninstall works.
- MSI install/repair/uninstall smoke tests documented and run where possible.

Deliverable version: `0.7.0-rc.1`.

### STAGE-08 — Windows app activity, browser extension, and chat

Objective:

- Add running-app and foreground-window metadata without command-line or document-content collection.
- Connect Chromium extension through Windows native messaging.
- Add chat, notifications, request-more-time, retention, and controller UI.
- Add Firefox only if separately documented and scope-safe.

Acceptance:

- App metadata and browser privacy rules match macOS behavior.
- Native messaging identity checks pass.
- Chat delivery/offline queue works.
- Collection controls and child disclosure work.
- Updated MSI, extension package, and controller package produced.

Deliverable version: `0.8.0-rc.1`.

### STAGE-09 — Windows policy enforcement and tamper resistance

Objective:

- Implement the shared policy engine behavior on Windows.
- Add warnings, workstation lock, user-session logoff, optional restart/shutdown, bonus time, immediate actions, local adult override, offline enforcement, and audit.
- Handle multiple sessions explicitly.
- Keep privileged service operations narrow.

Acceptance:

- Shared schedule vectors produce equivalent results on macOS and Windows.
- Standard user cannot alter policy or stop service through ordinary UI.
- Adult code rate limiting and reset work.
- Lock/logoff/restart/shutdown receipts are accurate.
- Recovery after reboot and controller outage works.
- Updated MSI and controller package produced.

Deliverable version: `0.9.0-rc.1`.

### STAGE-10 — iPadOS foundation and Family Controls authorization

Objective:

- Build SwiftUI iPad app and required App Group structure.
- Add device pairing, Keychain identity, child-readable dashboard, chat, request-more-time, local/APNs notification scaffolding, privacy disclosure, icon set, and Family Controls authorization flow.
- Add entitlement configuration documentation.
- Do not claim continuous presence.
- Do not implement MDM.
- Create physical-device test plan and simulator limitations.

Acceptance:

- App explains capabilities and unavailable desktop features.
- Child/parent authorization paths are handled.
- Pairing and chat work while the app is active; notification behavior is labeled best-effort.
- App and extension signing requirements are documented.
- Development archive or simulator artifact produced honestly.
- Missing entitlement produces a clear blocked status, not fake success.

Deliverable version: `0.10.0-rc.1`.

### STAGE-11 — iPadOS schedules, activity monitoring, and shields

Objective:

- Implement Device Activity schedules/events.
- Implement Managed Settings app/category/domain shields.
- Implement shield appearance and actions.
- Allow adult-authorized local selection of apps/categories/domains using privacy-preserving tokens.
- Sync schedule parameters and parent approvals from the controller.
- Implement bonus time and request-more-time within Apple’s supported model.
- Add controller display of iPad capabilities, policy state, and approximate presence.
- Do not expose token-derived private app identities beyond what the framework permits.

Acceptance:

- Selected apps/categories are shielded during blocked periods.
- Schedule survives app backgrounding/relaunch through supported extensions.
- Bonus-time flow works.
- Parent/child authorization and revoke cases are tested.
- No current-app/tab claims.
- Physical iPad test evidence documented.
- Development/TestFlight artifact produced only when signing and entitlement permit it.

Deliverable version: `0.11.0-rc.1`.

### STAGE-12 — Optional supervised iPad MDM feasibility and proof of concept

Gate:

- Start only after explicit developer approval of an ADR selecting MDM.
- This stage may be skipped.

Objective:

- Produce an MDM architecture and a minimal, standards-compliant proof of concept for supervised family-owned iPads.
- Document Apple Configurator or Automated Device Enrollment path.
- Implement only approved commands/queries.
- Keep certificates and APNs MDM credentials out of the repository.
- Integrate managed-device status into the controller without confusing it with the normal app channel.

Potential approved capabilities:

- Managed app deployment/prevent removal where supported.
- Device information queries.
- Device lock.
- Restart.
- Shutdown.
- Restrictions/profile management.

Non-capabilities remain:

- Current foreground app.
- Open apps.
- Browser tabs.
- Persistent arbitrary background agent.
- Ordinary desktop login-window control on a personal iPad.

Acceptance:

- Threat model and certificate lifecycle approved.
- Test device is supervised and intentionally enrolled.
- Commands use supported MDM protocol.
- Credentials are supplied securely.
- Enrollment removal/recovery is documented.
- No destructive command is enabled by default.

Deliverable version: `0.12.0-rc.1`.

### STAGE-13 — Cross-platform integration, resilience, and optional relay design

Objective:

- Harden capability negotiation, offline queues, device reconnect, policy convergence, database migrations, diagnostics, and mixed-version compatibility.
- Run an end-to-end matrix across controller, macOS, Windows, and iPad.
- Produce a relay ADR and threat model.
- Do not deploy a public relay without separate approval.

Optional relay, only if approved:

- Endpoints maintain outbound connections.
- Controller remains policy authority.
- Relay cannot issue commands.
- End-to-end authenticated/encrypted payloads.
- Rate limits, abuse controls, revocation, audit, and data minimization.
- No port forwarding required.

Acceptance:

- Mixed-version compatibility matrix documented.
- Controller handles unsupported commands safely.
- Reconnect and offline policy tests pass.
- Backup/restore and controller migration design tested.
- End-to-end test report produced.

Deliverable version: `0.13.0-rc.1`.

### STAGE-14 — Release hardening, signing, updates, and 1.0 candidate

Objective:

- Final security review.
- Installer hardening.
- Signed/notarized builds when credentials are securely configured.
- Authenticode signing when configured.
- iPad TestFlight/App Store preparation when entitlement is approved.
- Signed update manifests and rollback design.
- SBOM, license report, privacy documentation, user/admin guides, support diagnostics, disaster recovery, and release checklist.
- No automatic self-update in privileged components until signature validation and rollback are proven.

Acceptance:

- All required tests green.
- No unresolved critical/high findings.
- Clean-device install/upgrade/uninstall tests.
- Upgrade from prior stage candidates.
- Recovery after interrupted update.
- Final capability matrix matches reality.
- Release candidate artifacts and checksums published for developer approval.

Deliverable version: `1.0.0-rc.1`.

---

## 19. First instruction to execute

Begin with **STAGE-00 only**.

Before changing files:

1. Inspect the repository and confirm its current state.
2. Read this prompt completely.
3. Restate the STAGE-00 scope, assumptions, exclusions, and acceptance criteria.
4. Create the stage branch.
5. Implement STAGE-00.
6. Run the relevant checks.
7. Push and open a draft PR.
8. Provide the mandatory Stage Completion Report.
9. Stop at `AWAITING DEVELOPER TEST RESULT`.

Do not begin STAGE-01.
