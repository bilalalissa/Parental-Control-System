# Changelog

All notable approved stage deliverables are recorded here. The project uses staged release-candidate versions; approval does not imply merge or public release.

## 0.6.3-rc.1 — 2026-09-04

Status: **STAGE-06C merged; unreleased**

- Records a no-go for automatic integration with the evaluated ARRIS NVG448BQ firmware because no documented least-privilege API is available and the supported time-profile feature is documented as unreliable.
- Defines a WAN-only, per-device safety contract that preserves authenticated local controller access, requires IPv4/IPv6 parity and explicit Wi-Fi/Ethernet identity mapping, and uses router-owned hard expiry and recovery.
- Documents a cautious manual verification path for the existing gateway and conditional MikroTik RouterOS/OpenWrt adapter paths that require separate hardware/configuration approval.
- Creates no router login, credential, configuration change, network inspection, executable, installer, or external service dependency; the reviewable feasibility dossier is the sole Stage 06C artifact.
- Approved with `APPROVED: STAGE-06C 0.6.3-rc.1` and separately authorized for merge with `MERGE` on 2026-09-04; no router adapter or release is implied.

## 0.6.2-rc.1 — 2026-09-03

Status: **STAGE-06B merged; unreleased**

- Evaluates Apple Platform SSO and representative managed-identity paths without creating an external account, managed user, enrollment, profile, credential, or product integration.
- Records a conditional go for a separately approved online managed-identity pilot with a locally exempt adult recovery administrator, but a no-go as a replacement for the current local-first, offline weekly-schedule authority.
- Documents the absence of a weekly schedule in Platform SSO policy, the fail-open/fail-unavailable offline tradeoff, FileVault and Intel limitations, account migration and rollback risks, and a recovery-first pilot matrix.
- Produces a reviewable feasibility dossier rather than an installer because no runtime source or installed component changes in this stage.
- Approved with `APPROVED: STAGE-06B 0.6.2-rc.1` and separately authorized for merge with `MERGE` on 2026-09-04; no managed-identity pilot or release is implied.

## 0.6.1-rc.5 — 2026-09-03

Status: **STAGE-06A merged; unreleased**

- Records the Stage 06A no-go result for selectively denying Login Window access to an ordinary local child account through manual third-party MDM enrollment while guaranteeing local adult recovery.
- Keeps managed pre-login enforcement visibly unconfigured while preserving supported active-session re-locking through public macOS mechanisms.
- Separates scheduled-window time from daily active-use quota, bonus time, temporary allowance, and the effective limiting rule in the child app and menu-bar helper.
- Preserves endpoint identity, pairing, protected state, and the installed browser extension during in-place upgrades.
- Developer physical testing passed build `6105`; approved with the exact command `APPROVED: STAGE-06A 0.6.1-rc.5` on 2026-09-03. Approval does not imply merge, release, or authorization of later-stage work.
- Separately authorized for merge with the exact command `MERGE` on 2026-09-03; no release or later-stage work is implied.

## 0.6.0-rc.9 — 2026-08-31

Status: **STAGE-06 merged; unreleased**

- Recreates the visible per-user child helper registration after an in-place package upgrade instead of retaining a stale interrupted launchd job.
- Reconnects authenticated local XPC clients after the privileged child daemon is restarted, restoring session reporting and durable allowlisted action delivery without re-pairing.
- Strengthens the disposable package-upgrade check to require a healthy helper and a real graphical session report after both a double install and an isolated daemon restart.
- Preserves the endpoint identity, signed policy, pairing, current browser-profile extension installation, and all existing Stage-06 scope boundaries.
- Approved after physical-device retesting with the exact command `APPROVED: STAGE-06 0.6.0-rc.9` on 2026-09-01; approval does not imply merge or release.
- Separately authorized for merge with the exact command `MERGE` on 2026-09-01; no release or later-stage work is implied.

## 0.6.0-rc.5 — 2026-08-30

Status: **STAGE-06 ready for developer retest**

- Drives Parent presence from an observable five-second clock so a child with no fresh authenticated heartbeat ages from Online to Offline after the existing 75-second threshold without requiring navigation.
- Migrates pending requests for revoked, unpaired, or replaced device identities to non-actionable history and defensively excludes them from global and per-device badges.
- Bounds the Parent navigation sidebar, paired-device list, detail pane, and minimum window width so divider resizing preserves labels and cannot consume the detail pane.
- Retains all rc.4 schedule, request-decision, reconnect, enforcement, and appearance behavior; no network-filtering or later-stage capability was added.

## 0.6.0-rc.4 — 2026-08-30

Status: **STAGE-06 ready for developer retest**

- Coalesces repeated child time requests so only the newest pending request contributes to the Devices badge, and adds explicit authenticated approval or rejection with durable child-visible status.
- Ages presence defensively, rejects implausible future timestamps, and makes the endpoint reconnect after stale controller contact instead of remaining attached to a dead connection.
- Re-arms an active signed schedule restriction when the graphical child session becomes active after login or unlock; the app does not replace or bypass macOS login authentication.
- Adds system-adaptive Light and Dark appearances with explicit System, Light, and Dark choices in both visible apps.
- Continues to defer app/site/IP filtering and timed Internet pause until a separately approved privileged filtering design includes authorization, recovery, audit, and controller-connectivity safeguards.

## 0.6.0-rc.3 — 2026-08-27

Status: **STAGE-06 ready for developer retest**

- Adds Devices and per-device pending-time-request badges that clear only after the controller queues a signed grant and acknowledges the request.
- Adds a live child restriction countdown in the visible app and a persistent, visible menu-bar helper; the existing generic pre-enforcement panel remains in place.
- Shows only bounded private/link-local addresses and available non-zero MAC addresses from physical `enN` interfaces, stored locally and labeled informational rather than identity.
- Keeps the visible login helper alive in the graphical session and makes the installed child bundle root-owned and non-writable by standard users; an authorized administrator can still uninstall it.
- Defers app/site blocking and timed internet pausing because those are separately approved, higher-impact enforcement features.

## 0.6.0-rc.2 — 2026-08-27

Status: **STAGE-06 ready for developer retest**

- Replaces the root-daemon-to-login-helper transient enforcement handoff with a bounded, persisted, authenticated XPC event queue plus a systemwide wake signal, so warnings and actions survive helper timing and restart races.
- Evaluates accepted direct actions promptly and adds a visible grace warning when a newly applied schedule is already restrictive.
- Converts approved child time requests into a signed, expiring allow interval and gives the child visible local confirmation; macOS remains responsible for authentication and unlocking.

## 0.6.0-rc.1 — 2026-08-26

Status: **STAGE-06 ready for developer test**

- Adds canonical Ed25519-signed per-device schedules with deterministic IANA-time-zone evaluation, precedence golden tests, version replay/tamper rejection, and root-protected offline persistence.
- Adds bounded warnings and grace, daily active-session quota, bonus revisions, protected six-digit adult override with three-attempt/five-minute lockout, clock-change fail-closed behavior, and sleep/reboot continuity.
- Adds allowlisted Lock, Log Out, Restart, and Shut Down requests with capability checks, expiry, receipts, content-free audit records, parent confirmation for high-impact actions, and no force behavior.
- Adds visible parent schedule/action controls and a read-only child policy/override view. Lock preserves applications; loginwindow confirmation dialogs preserve macOS unsaved-work handling for logoff/restart/shutdown.
- Retains the Stage-05 visible extension and packages a current-version companion ZIP for clean-install developer testing; no browser permissions or collection scope changed.

## 0.5.0-rc.9 — 2026-08-26

Status: **STAGE-05 merged after developer physical retest and approval**

- Replaces the legacy synthetic-device sidebar plus separate bottom paired-device panel with one canonical real paired-device sidebar/detail workflow.
- Removes only the exact fixed Stage-01 preview rows from upgraded controller databases; synthetic fixtures remain available to tests and explicit mock tooling.
- Adds one native `DesignSystem` target shared by the Parent Controller and visible Child app, with near-black navy surfaces, warm coral emphasis, monospaced editorial headings, restrained borders, and preserved native accessibility behavior.
- Applies the corresponding self-contained visual language to the visible Chromium extension popup without changing its permissions, collection, identity, or privacy behavior.
- Developer physical retest passed and `0.5.0-rc.9` received exact Stage-05 approval.

## 0.5.0-rc.8 — 2026-08-26

Status: **STAGE-05 ready for developer retest**

- Delivers incoming child-chat feedback through the visible child app's ordinary macOS notification banner and default system sound while silently priming existing history and leaving the stable raw LaunchAgent free of notification-center calls.
- Gives application and retained browser-tab observations independent bounded vertical scrolling with visible indicators instead of truncating each list to eight rows.
- Classifies observed YouTube origins and conservative game origins/app identities, displays truthful inline alert badges, and emits generic parent notifications with a per-device/per-kind thirty-minute cooldown.
- Keeps notification content generic and continues to exclude message text, full URLs, page content, private tabs, logs, screenshots, and microphone capture.

## 0.5.0-rc.7 — 2026-08-23

Status: **STAGE-05 ready for developer retest**

- Removes unsupported `UNUserNotificationCenter` access from the raw logged-in LaunchAgent, fixing the physically confirmed ten-second crash loop while retaining system sound and automatic local speech for typed announcements.
- Adds an installed-helper survival check to CI so packaging cannot pass while session/application collection is unavailable.
- Retains a bounded, deduplicated list of recently observed open-tab title/origin pairs with configurable one-to-thirty-day retention; this does not import browser history or collect full URLs/content.
- Adds explicit YouTube and ordinary HTTPS game-origin coverage and labels active state honestly as active when observed.

## 0.5.0-rc.6 — 2026-08-16

Status: **STAGE-05 ready for developer retest**

- Fixes the physical rc.5 failure where the controller's three-second helper-readiness deadline expired and terminated the helper while macOS was still displaying the first-use Keychain authorization dialog.
- Gives the one in-flight helper launch a bounded 90-second, asynchronous human-response grace period while retaining immediate failure when the helper actually exits.
- Keeps passive polling non-launching, preserves existing Keychain items and pairings, and shows an explicit waiting-for-Keychain status during pairing-code creation.

## 0.5.0-rc.5 — 2026-08-16

Status: **STAGE-05 ready for developer retest**

- Stops the Parent Controller's passive five-second status refresh from relaunching a failed or authorization-denied hub, eliminating the reproduced unbounded Keychain password prompt loop.
- Keeps one bounded hub start on app launch and permits a later retry only after an explicit parent action or app relaunch; cancelling an authorization request now leaves the hub unavailable without generating more prompts.
- Supports one stable local Apple Development signing identity for physical-device candidates so approved Keychain access can survive subsequent rebuilt installers, while retaining credential-free ad-hoc signing as the CI fallback.
- Preserves existing controller Keychain items, pairings, and local family data; this repair does not reset or delete credentials.

## 0.5.0-rc.4 — 2026-08-16

Status: **STAGE-05 ready for developer retest**

- Fixes the physically reproduced Parent Controller race in which concurrent initial status and pairing-code requests could launch two hub helpers with different ephemeral IPC keys.
- Coalesces concurrent hub startup requests into one launch, accepts a runtime file only when its process ID belongs to that launch, and terminates/clears a failed launch before a bounded retry.
- Adds focused concurrency and retry regression tests while preserving the rc.3 browser, chat, speech, unread, mutation, and presence behavior.

## 0.5.0-rc.3 — 2026-08-16

Status: **STAGE-05 ready for developer retest**

- Replaces the child segmented-tab badge with an explicit accessible red unread counter and refreshes the visible child immediately when chat changes.
- Adds a macOS sound-effects fallback for child arrivals and speaks typed parent announcements once through local system speech without recording or creating audio files.
- Makes parent unread clearing conversation-specific and discoverable with per-audience/per-device counts plus automatic selection of an unread conversation.
- Adds authenticated, signed, replay-protected, parent-only edit/delete mutations with durable `Edited` and `Message deleted` state; logs and audits omit message content.
- Fixes exact app-bundle-path authorization, adds vendor Team ID validation, installs Arc's per-user native-host manifest, and uses the host-authenticated browser name for Chrome, Edge, or Arc.
- Preserves the developer-confirmed automatic online/offline detection and bounded reconnect behavior.

## 0.5.0-rc.2 — 2026-08-16

Status: **STAGE-05 ready for developer retest**

- Adds a short system alert confirmation after the parent or child sender successfully queues a chat message.
- Registers foreground notification delegates in both the visible child app and its logged-in helper so permitted arrival notifications can present their default sound while the app is open.
- Adds a persistent red unread counter to the Parent Controller Chat sidebar item and the child Chat tab, derived only from incoming messages that have not reached the Read state.
- Preserves the confirmed automatic child Online/Offline status behavior without changing presence or reconnect logic.

## 0.5.0-rc.1 — 2026-08-16

Status: **STAGE-05 ready for developer test**

- Adds one shared visible Manifest V3 Chrome/Edge extension and one packaged ZIP with a stable extension identity and explicit minimal permissions.
- Adds a universal macOS native-messaging host with exact extension-origin, browser signing/path, installed-host signing/path, and authenticated XPC checks.
- Adds opt-in, bounded, short-retention tab-title and query-free-origin metadata; private tabs, page content, paths, queries, fragments, forms, cookies, passwords, and network traffic remain excluded.
- Adds generic system-controlled arrival sound for both receiver directions and explicit conversation-visible Read receipts, while preserving content-free logs, audit rows, and notification diagnostics.
- Adds controller/child disclosures and controls, local SQLite migration/pruning, protocol types, installer/uninstaller integration, and privacy/security regression coverage.

## 0.4.0-rc.5 — 2026-08-16

Status: **STAGE-04 merged**

- Refreshes derived Online/Offline presence on the parent every five seconds without requiring UI interaction.
- Signals the daemon immediately when an established child connection closes, then preserves the bounded three-attempt, two-second retry sequence and 60-second cooldown.
- Adds deterministic regression coverage for parent presence publication and the sleep/wake reconnect policy.
- Approved by the developer with the exact command `APPROVED: STAGE-04 0.4.0-rc.5` and separately authorized for merge with `MERGE` on 2026-08-16; no release is implied.

## 0.4.0-rc.4 — 2026-08-15

Status: **STAGE-04 ready for developer retest**

- Replaced the visible child app's actor-isolated UserNotifications completion handler with the concurrency-safe async authorization API, preventing the confirmed Intel launch crash.
- Added source regression coverage and an installed-app CI launch-survival smoke test.

## 0.4.0-rc.3 — 2026-08-15

Status: **STAGE-04 ready for developer retest**

- Corrected the installed child app's authenticated XPC path validation to accept the root-protected signed application bundle path returned by macOS as well as its canonical inner executable path.
- Added regression coverage for both valid child code paths while continuing to reject paths outside the installed application.

## 0.4.0-rc.2 — 2026-08-15

Status: **STAGE-04 ready for developer retest**

- Restored automatic TLS-pinned endpoint reconnection after the parent controller restarts by migrating paired devices to a stable LAN service port.
- Reloaded and restarted the logged-in activity helper during upgrades, added bounded three-attempt startup, and configured launchd to recover it after abnormal termination.
- Replaced the inaccessible paired-device disclosure row with a dedicated accessible expansion button and activity-sharing control.

## 0.4.0-rc.1 — 2026-08-15

Status: **STAGE-04 ready for developer test**

- Added event-driven macOS foreground/running application metadata limited to names, bundle identifiers, state, and time; collection can be disabled and retention is configurable from one to thirty days.
- Added authenticated two-way direct chat, family group chat, parent announcements to all paired child devices, generic child notifications, and request-more-time.
- Added bounded persistent controller/endpoint offline queues, queued/sent/delivered/read/failed states, thirty-day chat pruning, audit metadata without message contents, and protected local storage permissions.
- Updated both visible SwiftUI apps and replaced the prior selectable package with one universal `0.4.0-rc.1` candidate.
- Browser tabs, schedule enforcement, remote actions, public relay, and cloud storage remain excluded.

## 0.3.0-rc.2 — 2026-08-15

Status: **STAGE-03 merged**

- Added the visible universal macOS Child Endpoint, boot daemon, login helper, authenticated protected XPC, explicit pairing, status/uptime/session/network/health reporting, bounded logs, installer, and uninstaller.
- Added the selectable combined package with the Parent Controller as the default role and the Child Endpoint available through Customize.
- Added bounded three-attempt startup and packaging retries with short delays and confirmed physical-device pairing, revocation, unpairing, re-pairing, and reduced routine Keychain prompts.
- App activity, browser tabs, chat, and enforcement remained excluded from Stage 03.

## 0.2.0-rc.1 — 2026-08-13

Status: **STAGE-02 merged**

- Added the local controller hub, one-time pairing, authenticated IPC, pinned TLS WebSocket transport, signed/replay-protected protocol envelopes, persistent bounded device state, receipts, and lightweight concurrent mock-agent coverage.
- Added Bonjour LAN discovery, adaptive heartbeats, delta snapshots, honest offline/last-seen behavior, revoke/unpair, and parent-process lifecycle management.
- Replaced the persistent GUI-to-hub IPC credential with a per-launch in-memory key transferred through a private pipe, preventing routine Keychain password prompts while retaining long-lived private identities in Keychain.
- Added an arm64, ad-hoc-signed developer-test DMG and protocol, persistence, IPC, transport, concurrency, resource, packaging, and lifecycle evidence.
- No privileged endpoint behavior, real monitoring, enforcement, public relay, container, or virtual machine is included.

## 0.1.0-rc.2 — 2026-08-13

Status: **STAGE-01 merged**

- Added the native Apple-silicon SwiftUI Parent Controller shell with dashboard, device, schedule, chat, audit, storage, and settings surfaces.
- Added local SQLite migrations, bounded synthetic fixtures, deterministic schedule validation, and automated capability/accessibility tests.
- Added truthful macOS, Windows, and standard-iPad capability displays without endpoint traffic, monitoring, or enforcement.
- Added a supported Service Management start-at-login control, an original canonical vector icon, constrained build/run scripts, and path-scoped macOS CI.
- Added an arm64, ad-hoc-signed developer-test DMG with SHA-256 verification.
- Added local-preview family group chat and all-device parent announcements in response to developer feedback.
- Replaced the original shelter icon with a new connected-family constellation design.

This release candidate is not Developer ID signed or notarized and contains no Stage 02 pairing or device-control behavior.

## 0.0.1-rc.1 — 2026-08-13

Status: **STAGE-00 approved**

- Established the local-first monorepo foundation and project documentation.
- Added canonical protocol and policy JSON Schemas with synthetic fixtures and deterministic golden-vector tests.
- Added architecture, capability, privacy, security, threat-model, contribution, ADR, and icon-design guidance.
- Added dry-run-first repository cleanup tools for POSIX and Windows, plus safety tests.
- Added resource-aware GitHub CI with minimal permissions, pinned actions, cancellation, and short failure-artifact retention.
- Added the MIT License, README, GitHub issue templates, pull-request template, and stage tracker.

No application runtime, privileged service, policy enforcement, installer, relay, MDM implementation, or production artifact is included in this version.
