# STAGE-06E — macOS application-use restrictions

- Version: `0.6.5-rc.4` (build `6504`)
- Branch: `stage/06e-macos-app-use-restrictions`
- Status: `READY_FOR_RETEST`
- Authorized on 2026-09-05 with `AUTHORIZE ROADMAP AMENDMENT: INSERT STAGE-06E MACOS APP-USE RESTRICTIONS BEFORE STAGE-07` and `PROCEED: STAGE-06E`.
- Browser-compatibility amendment authorized on 2026-09-06 with `AUTHORIZE STAGE-06E SCOPE AMENDMENT: HARDEN DOMAIN ENFORCEMENT FOR YOUTUBE, RESTORED TABS, AND SPA NAVIGATION IN ENROLLED BROWSERS; USE LOCAL HOSTNAME MATCHING ONLY, WITH NO CONTENT INSPECTION.` and `PROCEED: STAGE-06E 0.6.5-rc.3 BROWSER COMPATIBILITY FIX`.

## Objective and included scope

Allow a parent to select recently observed, signed third-party macOS applications and distribute a versioned app-use policy through the existing authenticated LAN. The child caches the policy in root-protected configuration, validates the running bundle's signing identifier and Team ID, visibly asks a matching application to quit after launch, and locks the session if the application remains running after five seconds. Configuration delivery and enforcement outcomes are authenticated and audited.

Rules remain active when optional application-name sharing is disabled and while the parent is offline. A newer empty policy removes all app-use rules. System, Apple, login/recovery, Finder/Dock, and parental-control components are unconditionally excluded. The child account must be a standard non-administrator and an adult recovery administrator must remain available.

## Platform boundary and exclusions

This local ad-hoc build has no Apple Endpoint Security entitlement. It cannot authorize or deny execution before launch, and a restricted app may appear briefly before the visible per-user helper requests a normal quit. If normal termination is refused, the safe fallback is session lock rather than force-kill, protecting unsaved work. A device administrator can bypass or remove this enforcement.

Excluded: Endpoint Security/system extensions; kernel-level pre-launch denial; force termination; command-line/path-only rules; Apple/system-app restriction; administrator resistance; hidden monitoring; screen/keystroke/content collection; WAN pause; Safari/private/guest browser coverage; request or traffic inspection; managed extension deployment; MDM; Windows/iPad work; Stage 07. The RC3 amendment is limited to local HTTP(S) hostname matching in explicitly enrolled profiles.

## RC1/RC2 feedback and RC3 correction

Physical testing showed that both the Discord app policy and YouTube website policy reached the child, but Discord stayed open without a notice or enforcement event and the enrolled Arc profile reported `Not reporting`. The application failure was a real RC1 lifetime bug: the helper weakly retained `NSRunningApplication` while awaiting XPC status, allowing the callback to exit before enforcement. RC2 instead carries immutable PID, bundle identifier and normalized bundle path, reacquires that PID after the reply, and validates the live bundle and current signing identity before acting. The delayed close check also reacquires the PID and rejects reuse or replacement.

RC2 repaired the native host upgrade but physical testing showed a narrower browser gap: Arc acknowledged the `youtube.com` policy while a restored YouTube application shell and same-document navigation remained usable. The earlier declarative rules covered network navigation frames, but browser restoration, service-worker-backed application shells and SPA history transitions do not reliably create a new main-frame request.

RC3 keeps declarative rules and adds an independent local tab reconciliation layer. It reads only the browser-provided tab URL, parses the HTTP(S) hostname locally, discards path/query/fragment values, and compares the hostname to the cached bare-domain policy. Matching new navigation, active/restored tab or SPA URL changes are redirected to the bundled static `blocked.html` page. It does not inspect page content, requests, response data, cookies, traffic or DNS, and transmits no new URL fields. The installer places the Chromium source at the stable root-owned read-only path `/Library/Application Support/ParentalControlBrowserExtension/Chromium`. Because browsers cannot silently repoint an existing unpacked extension, RC3 needs one adult-supervised move from the previous manually selected directory to that stable path. Future installer replacements keep the same path and require only a normal full browser restart.

Physical RC3 feedback found an installer lifecycle regression: if the visible Child app was open during an in-place update, the old ad-hoc process survived while its bundle and the daemon's exact XPC client manifest were replaced. The old process could then remain indefinitely at `Connecting to the protected endpoint service…`, even though the new daemon and helper had been installed.

RC4 detects only the exact package-owned Child executable in the current console session and requests its normal termination before payload replacement. It never force-kills the UI; if it does not exit within five seconds, the installer stops with a readable instruction instead of replacing a running client. A separate atomic `root:wheel` mode `0600` marker records that the UI was open. After replacing and restarting the daemon and helper, postinstall validates the marker owner, mode, console UID and ten-minute age, consumes it, and relaunches the new Child app in that user's GUI context. This changes no endpoint identity, pairing, schedule, app policy, website policy or collected data.

## Acceptance criteria

1. Parent selection is limited to observed apps with exact bundle/signing/Team identity; protected or unsigned identities cannot be selected.
2. Policy versions are monotonic, bounded to 32 rules and 12 KiB, signed in transit, cached root-only, and reject rollback/conflict.
3. A selected app launch triggers a visible warning and ordinary quit request. A refusal produces one bounded session-lock fallback, not a repeated lock loop.
4. Unselected apps continue to launch. A same-bundle/different-Team identity does not match. An empty newer policy restores access.
5. Rules continue with activity sharing disabled and across parent disconnect/restart; upgrade preserves pairing and existing schedule/browser policy.
6. Parent audit records distinguish policy queueing, quit request, confirmed close, and lock fallback. No command line, document/window content, or mutable app path is transmitted.
7. Controller arm64 and child universal binaries build into one selectable unsigned/ad-hoc developer package with SHA-256 verification. Physical standard-user testing remains required.
8. Enrolled browser profiles enforce exact and subdomain hostname rules during ordinary navigation, restored-tab startup and SPA URL changes, show only a local static block page, reject lookalike domains, and continue with optional tab sharing or the parent connection disabled.

## Resource and cleanup limits

Use no more than two build workers, one checkout, one Stage-06E derived-data tree, one current macOS installer and one current pair of browser test packages. Keep at least 5 GiB free. Run unit/protocol tests before the universal Release build. Remove project-owned `dist`, derived data and package staging after verifying the replacement candidate; replace the previous browser packages only after RC3 verification and do not touch installed developer processes or simulator data.

## Manual developer test checklist

1. Leave the RC3 Child app open, then install the Child Endpoint from `ParentalControlSystem-0.6.5-rc.4.pkg` in place without uninstalling or unpairing. Confirm the old window closes, the RC4 window reopens, and the same child returns Online without showing a persistent protected-service connection message.
2. Use a standard child account and retain a separate adult administrator. Open one signed third-party test app once so its exact identity appears in Devices > Application-use restrictions.
3. Select that app and apply the policy. Confirm the audit reports queued/delivered policy metadata without paths or content.
4. Leave the selected app open while applying the policy. It must show the visible restriction banner and receive a normal quit request promptly (the bounded reconciliation scan is at most 15 seconds). Re-launch it and confirm launch notification enforcement also works. Confirm a `quit-requested` and then `closed` audit event.
5. With unsaved content in an explicitly disposable test document, cancel/refuse the app's quit prompt. After five seconds the session should lock once. Sign back in and close the app; confirm there is no recurring five-second schedule lock loop.
6. Launch an unselected signed third-party app: it remains available. Apple/system and Parental Control apps are marked Protected and cannot be selected.
7. Disable application-name sharing: the selected app remains restricted. Disconnect the parent: cached restriction remains. Reconnect and verify the device returns Online.
8. Complete the one-time Chromium transition. Fully quit Arc/Chrome/Edge/Brave. Open its extension page, remove the older unpacked test copy, enable Developer Mode, choose **Load unpacked**, and select `/Library/Application Support/ParentalControlBrowserExtension/Chromium`. Reopen the browser and confirm the profile changes from `Setup required` to the current policy acknowledgement. Repeat per tested profile. Do not copy this folder into Downloads or modify its root-owned contents.
9. Test all three paths with `youtube.com`. For an already-loaded/SPA-style app shell, first remove the rule, open YouTube, then apply the rule while the tab remains open; it must redirect to the visible local block page. For restoration, remove the rule, open YouTube, configure the browser to restore tabs, quit it, apply `youtube.com` while it is closed, then reopen it; the restored tab must redirect after extension startup. A fresh navigation must also redirect. Confirm `notyoutube.com` remains allowed. Add `youtu.be` separately when that short-link host must also be denied.
10. Disable optional browser-tab sharing and disconnect the parent: cached hostname enforcement continues. No page content, path, query, fragment, cookie, DNS history or traffic payload appears in the parent, audit or endpoint logs.
11. Reinstall the RC4 child component in place once with the Child app open and once with it closed. The open app must be normally replaced and relaunched; the closed app must remain closed. Pairing, schedule, browser policy, endpoint identity, app policy and the stable extension path remain. No new extension-path selection is required after the RC3 migration.
12. Apply empty app and website policies: the formerly restricted app and a new browser navigation work normally.
13. Record CPU/memory over five idle minutes and report OS, hardware, app bundle ID, expected result, observed result, and only the bounded relevant audit/log lines.

## Rollback

Apply empty newer app and website policies before reverting. Installing Stage 06D RC5 over Stage 06E RC4 is not a supported database downgrade because Stage 06E adds schema fields, but the new fields are additive and ignored by older code. The administrator uninstaller removes the installer-owned stable extension source but cannot remove browser-profile registrations; remove those visibly in each browser when intentionally uninstalling.

## Automated and artifact evidence

- Repository contracts: 70 passed, one Windows-only cleanup check skipped on macOS. The focused browser suite includes 11 passing cases for policy validation/readback, privacy permissions, native outage behavior, restored tabs and SPA URL changes. Installer assertions additionally require bounded normal termination, no force-kill, a root-only relaunch marker and console-user relaunch.
- Controller/hub: 54 Swift Testing cases plus four XCTest cases passed with two workers, including policy bounds, aggregate IPC budget, migration and exact identity persistence.
- Endpoint: 31 Swift Testing cases plus six XCTest cases passed with two workers, including identity mismatch, protected-app exclusion, rollback/persistence, XPC authorization and one-attempt-per-process/policy fallback gating.
- Swift formatting, shell syntax and Git whitespace checks passed.
- `ParentalControlSystem-0.6.5-rc.4.pkg` was built from commit `eeafd66d4e3b`, checksum-verified, expanded-payload inspected, and its selectable choices passed `installer -showChoicesXML` validation. The embedded preinstall and postinstall scripts exactly match the reviewed source, the XPC client manifest is mode `0600`, and the payload includes the stable Chromium source and static block page.
- Parent binary is `arm64`; child app and helpers are universal `x86_64 arm64`. Both apps passed deep/strict code-signature verification.
- SHA-256: installer `3205eabbd709bc5e7dfb7dbd6812d7cea2f5727478df2c589b1840e35d45f9bb`; Chromium ZIP `d2026793705dfab2201d5f4790cbf5fdc215a9870bad885bafa658e99687a8d7`; Firefox XPI `0447bafd42d7df49956444c4ffd386db6989ff1386d13fed5580c2dac7f1964b`.
- Signing status: embedded apps/helpers use hardened-runtime ad-hoc signatures with no Team ID. The product package is unsigned and not notarized. The Firefox XPI is unsigned and temporary. No Endpoint Security entitlement is present or claimed.
- GitHub Actions run `34044737285` passed on its clean macOS rerun. It verified the default parent-only choice, a fresh child install, endpoint/helper health, exact protected-file permissions, a Child UI kept open across in-place reinstall and replaced by a new process, unchanged endpoint identity, daemon-only reconnect, package cleanup and uninstall. Contracts, POSIX/Windows cleanup safety and the repository secret scan also passed. The first attempt ended at the pre-existing parent-only assertion before reaching the child-upgrade test; the clean rerun passed that assertion and the complete new path.

Physical in-place upgrade with the RC3 Child UI left open, connection recovery, one-time stable extension-path migration, ordinary/restored/SPA YouTube enforcement, standard-user app behavior, refusal/lock fallback and idle-resource evidence remain the developer test gate. Local package inspection cannot prove the console-session relaunch; the updated macOS CI job and developer hardware test provide that evidence.

AWAITING DEVELOPER TEST RESULT
