# STAGE-06 — macOS policy enforcement

- Version: `0.6.0-rc.3`
- Branch: `stage/06-macos-policy-enforcement`
- Status: `READY_FOR_DEVELOPER_RETEST`
- Platform: Apple-silicon Parent Controller and universal Apple-silicon/Intel macOS Child Endpoint on macOS 14 or newer

## Objective, scope, and acceptance

Implement one local-first signed-policy path from the paired Parent Controller to the visible macOS child endpoint. Included are deterministic schedule/quota evaluation, warning offsets, grace, lock-first enforcement, explicitly confirmed logoff/restart/shutdown, bonus time, expiring immediate actions, a protected rate-limited adult override, wall-clock discontinuity detection, sleep/resume and reboot continuity, offline enforcement, authenticated receipts, content-free audit records, and visible read-only child status.

Acceptance requires policy golden vectors, daylight-saving and cross-midnight behavior, warning timing, signature tamper and version-replay rejection, protected cached state, three-attempt adult-code rate limiting, documented unsaved-work behavior, isolated typed-action tests, runtime/resource measurements, a clean-install package for both affected apps, checksums, bounded output, and no Stage-07 work.

Excluded are Windows/iPad work, public relay/cloud services, arbitrary commands or scripts, force quit/force shutdown, hidden UI or persistence, screenshots, camera/microphone recording, clipboard/keystroke/content collection, browser-permission expansion, remote policy editing by the child, a universal override code, and attempts to resist an authorized local administrator.

Assumptions: the parent is the paired local authority; the child account is a standard non-administrator; the package is installed by an administrator; macOS notification, sound, screen-lock, save-confirmation, and authorization behavior remains authoritative; the last valid signed policy may be enforced while the controller is unavailable.

Resource limits are one checkout, one stage branch, two build workers, sequential endpoint architectures, one project-owned build tree, no VM/container/simulator/worktree, at least 5 GiB free, and one current PKG/extension-ZIP candidate set after verification.

## Delivered behavior

- `HubCore` owns the canonical Swift policy model and deterministic sorted-key/ISO-8601 signing representation. The controller's existing Ed25519 authority signs each per-device policy; the endpoint verifies the paired key, key identifier, device identifier, signature, time zone, bounded fields, and strictly increasing version.
- Evaluation precedence is adult override, authenticated immediate action, signed exception, blocked interval, daily quota plus bonus, recurring allowed window, then default restriction. Golden tests cover this order, IANA time zones, daylight-saving transitions, and cross-midnight windows.
- The endpoint stores only the current signed policy and bounded runtime state under its root-protected Application Support directory with mode `0700`/`0600`. Cached policy signatures are re-verified at daemon startup. Tampered caches are not loaded.
- A 15-second event-driven scheduler evaluates locally with a continuous monotonic clock. Daily active-session quota, warning issuance, grace start, adult override, and enforcement state persist. Sleep is excluded from active-session accounting; reboot preserves quota and grace and re-issues an active restriction for the new login session. Material wall-clock discontinuity fails closed until a fresh higher-version signed policy arrives.
- Parent controls create one schedule per selected paired macOS child, including weekly allowed windows, daily quota, one-to-sixty-minute warning, zero-to-fifteen-minute grace, bonus minutes, and a safe default action. A newly applied policy rotates a random six-digit local adult verifier; only the salted SHA-256 verifier is transported/stored.
- The visible child app shows policy version, current decision/action/reason, clock trust, and override expiry. Settings are read-only. Three bad adult-code attempts in five minutes cause a five-minute lockout; a correct code grants a bounded 15-minute local override.
- Immediate actions are allowlisted, signed, replay-protected, capability-checked, and expire after two minutes in the controller queue (the endpoint rejects any action beyond fifteen minutes). Offline device buttons are disabled. High-impact actions require explicit parent confirmation.
- Endpoint acceptance receipts and parent audit records contain command type/state metadata but no policy explanation, adult code, chat body, application name, tab title/origin, device network address, or family content.
- Physical rc.1 feedback showed that transport and endpoint receipts succeeded but the root daemon's transient session notification could be missed by the logged-in helper. rc.2 persists a bounded queue of typed warning/action/clock/bonus events, wakes the helper through the systemwide Darwin notification center, and retains startup/periodic claims so a late helper cannot lose an event.
- Direct actions are evaluated and queued immediately upon authenticated acceptance instead of waiting for the next 15-second policy tick. A newly blocked schedule also emits a visible grace warning before enforcement.
- Approving a child's time request now publishes a signed, bounded allow exception through the approval expiry, in addition to the existing bonus quota. The child receives a visible local approval notice; macOS is not programmatically unlocked.
- rc.3 shows the pending-request count on the Parent Devices navigation item and on the requesting device. Granting is idempotently disabled while in flight, and the request is marked resolved only after the signed policy and adult-verifier operations succeed.
- rc.3 projects the next signed-policy restriction with active-session quota semantics. The child app displays a live one-second countdown; the visible login helper also provides a persistent menu-bar countdown outside the child app while retaining the existing generic pre-enforcement panel.
- rc.3 reports only bounded private/link-local addresses and available non-zero MAC addresses from physical `enN` interfaces. The Parent labels MAC data informational and never uses it for pairing or identity; public and virtual-interface addresses are discarded before transport and again before local persistence.
- The visible login helper is kept alive by launchd, while the installed child bundle is root-owned and non-writable by standard users. Ordinary app/helper termination is recovered without hiding the software. Authorized administrators retain normal macOS control and the visible uninstaller.
- App/site blocking and timed internet pausing remain excluded from this bounded retest. They require separately approved, higher-impact policy, Network Extension/authorization, recovery, and false-positive work.

## Unsaved-work and action behavior

- **Lock** is the default. The logged-in helper starts the system Screen Saver engine. Applications remain open; the project does not terminate processes or discard documents. The effective password requirement remains the Mac's system setting.
- **Log Out**, **Restart**, and **Shut Down** are optional, explicit high-impact actions. The helper asks `loginwindow` to show the corresponding standard macOS confirmation dialog. The project does not use immediate/forced variants. Application save prompts, cancellation, and any unsaved-work warning remain controlled by macOS and the applications.
- An authenticated receipt means the endpoint accepted the typed action, not that the user confirmed the subsequent macOS dialog or that the machine powered off. Presence continues to report only `Online` or `Offline` plus last seen.

## Verification evidence

- Controller/hub: 42 tests in 12 suites passed, including LAN-metadata sanitization/persistence, request acknowledgement, policy precedence/signatures/warnings, authenticated IPC, TLS, persistence bounds, approved-time behavior, and existing Stage-05 regressions.
- Endpoint: 20 tests in 3 suites passed, including projected schedule/quota countdown behavior, bounded physical-interface collection, real TLS policy delivery, protected cached-policy verification, tamper/version replay, durable warning/action handoff, direct action, grace, reboot, sleep/resume, adult-code lockout, and clock-change fail-closed behavior.
- Full repository suite: 40 tests passed and the Windows-only cleanup test was skipped on macOS. Both Swift format linters, shell syntax, browser JavaScript syntax, JSON validation, launch-plist lint, `git diff --check`, and the bounded secret-pattern scan passed.
- The retained PKG was expanded and its packaged Parent Controller and Child Endpoint passed deep/strict code-signature verification. Both embed version `0.6.0-rc.3`, build `6003`, and source commit `0821b812f770`. The parent executable is `arm64`; the child executable and its daemon, login helper, control tool, and browser native host are universal `x86_64 arm64`.
- `ParentalControlSystem-0.6.0-rc.3.pkg`: SHA-256 `c49dcd41a13e7b4afc470f56538faac33f0ceaf3a3763448b440122f8aff54a8`; contained apps/helpers are ad-hoc signed; the product package is unsigned and not notarized.
- `ParentalControlBrowserSharing-0.6.0-rc.3.zip`: SHA-256 `c59ba729fda1a455298f87cf976c1f3b613d988a4e36c83a060fa7c3f2056f99`; ZIP integrity and its exact eight expected extension files passed; it contains no signing-key file extensions.
- An isolated unpaired RC3 daemon smoke run completed normally in 6.11 seconds with 0.01 seconds user CPU and 0.01 seconds system CPU. The sandbox did not expose peak-RSS statistics; the temporary root was removed immediately.
- GitHub macOS CI run `33141714497` passed in 3m09s, independently repeating repository/Swift tests and lint, building the selectable package, checking universal slices and choices, clean-installing the default Parent, clean-installing/diagnosing/uninstalling the customized Child, uploading the bounded candidate set, and cleaning generated output.
- Physical-device installation, policy timing, warning UI, OS confirmation dialogs, sleep/reboot, and offline enforcement remain developer-test evidence and are not claimed by local automation.

## Clean-install developer checklist

1. Verify the supplied PKG and extension ZIP SHA-256 values before opening either artifact.
2. On a parent Mac with no prior version, run the PKG with its default **Parent Controller** selection. On a child Mac with no prior version, run the same PKG, choose **Customize**, deselect Parent Controller, and select **Child Endpoint**.
3. Open both visible apps and confirm version `0.6.0-rc.3`. On the child run `parental-control-agentctl status`; capture only health, connection, policy, and session fields—not device/network identifiers.
4. Pair once with a new one-time code. Confirm the child is Online, then select it in the parent's single Devices list.
5. In Schedule choose a small test window that currently allows use, a 1-minute warning, a 15-second grace, and Lock. Choose **Sign and Apply Policy** and record the displayed adult override code privately.
6. Adjust the test window so it ends within the next few minutes. Confirm the child shows a generic warning, then locks only after the configured grace. Confirm open apps/documents remain present after unlocking.
7. Disconnect the parent from the LAN, leave the child running, and repeat an allowed-to-block transition. Confirm the cached policy still warns and locks. Reconnect afterward.
8. From the child, request 15 minutes. Without opening Chat, confirm a count badge appears on the Parent **Devices** tab and beside that child. Select the child, choose **Grant**, and confirm the button says **Granting…** briefly, the badge clears after success, and a new signed policy version arrives.
9. Set a restriction within a few minutes. Confirm the child app countdown changes once per second. Close the child app and confirm the visible menu-bar shield/hourglass remains, its countdown continues, and **Open Parental Control** reopens the app. Confirm the generic warning panel still appears before enforcement.
10. In Parent Devices, confirm the child shows only physical `enN` interface rows with private/link-local IP addresses. If macOS exposes a non-zero interface MAC, confirm it appears as informational. Public addresses and `utun`/`awdl`/`llw` rows must not appear.
11. From a standard child account, quit the visible child app and helper normally and confirm launchd restores the helper/menu item. Confirm the account cannot modify or remove the root-owned app bundle and cannot run the bundled uninstaller without administrator authorization. Do not test against an authorized administrator account.
12. Enter a wrong adult code three times on the child. Confirm the fourth attempt reports a five-minute lockout. After the lockout, enter the current correct code and confirm a 15-minute override is shown; do not share the code in logs/screenshots.
13. With the child Online, send **Lock Screen** and confirm it locks. For Log Out/Restart/Shut Down, verify only that the standard macOS confirmation dialog appears, then choose **Cancel** unless you have saved all work and intentionally want to continue.
14. Put the child to sleep for at least two minutes and wake it. Confirm no clock-tamper warning appears solely because of sleep and policy status remains present. Reboot once and confirm the signed policy version remains present and the current restriction is re-applied when appropriate.
15. Change the wall clock only on a disposable test account/Mac, if safe. Confirm a clock warning and fail-closed restriction, restore automatic time, reconnect, and apply a new policy version. Skip this check if changing time would disrupt other software.
16. Reconfirm Stage-05 chat, application-name sharing, and browser title/origin sharing. No new browser permission is expected.
17. Run the bundled administrator uninstaller on the child and confirm the visible app, launch jobs, command tool, protected endpoint state/policy, logs, native-host manifests, and endpoint Keychain item are removed. Browser extension removal remains per browser profile.

## Known limitations

- This is a developer candidate. The retained local build may use Apple Development or ad-hoc app/helper signing; the product PKG and extension ZIP are not Developer ID Installer signed, notarized, or store-published.
- Lock uses the public Screen Saver path because macOS exposes no general third-party API that guarantees the same semantics as the Apple-menu Lock Screen command. Its password timing follows System Settings.
- Logoff/restart/shutdown receipt state is acceptance-only. The standard confirmation dialog may be cancelled, and LAN loss still reports `Offline`, never inferred power state.
- Desktop enforcement actions require the visible per-user login helper and a logged-in graphical session. If no user session is available, an authenticated command may be accepted by the daemon without an OS dialog or screen transition.
- Policy timing resolution is 15 seconds. Active-use quota is based on the reported active login session, not keystrokes, content, or invasive idle monitoring.
- An authorized local administrator can remove or disable the endpoint. This project does not attempt to bypass administrator control.
- The visible helper is a normal macOS LaunchAgent. KeepAlive restores ordinary termination, and root ownership prevents standard-user modification/uninstall, but the project does not claim kernel-level or MDM-grade tamper proofing.
- MAC availability depends on macOS and the active interface. It is not a stable child identity and may be randomized, unavailable, or change across networks.
- The countdown is a projection from the current signed policy, active-session state, quota, and override. A newer signed policy or a session-state change can legitimately move it.

## Failure evidence to collect

- `parental-control-agentctl status`, redacting device/network identifiers and any adult code
- `launchctl print system/com.bilalalissa.ParentalControlAgent.daemon`
- `launchctl print gui/$(id -u)/com.bilalalissa.ParentalControlAgent.user`
- `/Library/Application Support/ParentalControlAgent/Logs/agent.log*` after reviewing for private family metadata
- macOS version, architecture, package checksums, exact test step, expected/observed result, and whether Focus/mute/notification settings were active
- Never attach the policy file, adult override code/verifier, device identity keys, private chat, private screenshots, tab titles/origins, or network addresses to a public issue
