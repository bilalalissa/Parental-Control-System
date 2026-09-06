# STAGE-06E — macOS application-use restrictions

- Version: `0.6.5-rc.2` (build `6502`)
- Branch: `stage/06e-macos-app-use-restrictions`
- Status: `READY_FOR_RETEST`
- Authorized on 2026-09-05 with `AUTHORIZE ROADMAP AMENDMENT: INSERT STAGE-06E MACOS APP-USE RESTRICTIONS BEFORE STAGE-07` and `PROCEED: STAGE-06E`.

## Objective and included scope

Allow a parent to select recently observed, signed third-party macOS applications and distribute a versioned app-use policy through the existing authenticated LAN. The child caches the policy in root-protected configuration, validates the running bundle's signing identifier and Team ID, visibly asks a matching application to quit after launch, and locks the session if the application remains running after five seconds. Configuration delivery and enforcement outcomes are authenticated and audited.

Rules remain active when optional application-name sharing is disabled and while the parent is offline. A newer empty policy removes all app-use rules. System, Apple, login/recovery, Finder/Dock, and parental-control components are unconditionally excluded. The child account must be a standard non-administrator and an adult recovery administrator must remain available.

## Platform boundary and exclusions

This local ad-hoc build has no Apple Endpoint Security entitlement. It cannot authorize or deny execution before launch, and a restricted app may appear briefly before the visible per-user helper requests a normal quit. If normal termination is refused, the safe fallback is session lock rather than force-kill, protecting unsaved work. A device administrator can bypass or remove this enforcement.

Excluded: Endpoint Security/system extensions; kernel-level pre-launch denial; force termination; command-line/path-only rules; Apple/system-app restriction; administrator resistance; hidden monitoring; screen/keystroke/content collection; WAN pause; browser changes; MDM; Windows/iPad work; Stage 07.

## RC1 feedback and RC2 correction

Physical testing showed that both the Discord app policy and YouTube website policy reached the child, but Discord stayed open without a notice or enforcement event and the enrolled Arc profile reported `Not reporting`. The application failure was a real RC1 lifetime bug: the helper weakly retained `NSRunningApplication` while awaiting XPC status, allowing the callback to exit before enforcement. RC2 instead carries immutable PID, bundle identifier and normalized bundle path, reacquires that PID after the reply, and validates the live bundle and current signing identity before acting. The delayed close check also reacquires the PID and rejects reuse or replacement.

The Stage 06D extension and domain-rule implementation are not changed in Stage 06E. RC2's child upgrade ends only any pre-upgrade `ParentalControlBrowserHost` process, so the already-installed extension's next native request launches the replacement host. It does not close, reload, remove or reinstall Arc, Chrome, Edge, Brave, Firefox, or an extension. Declarative rules govern new navigation and frames; already-loaded YouTube content is not retroactively closed and must be tested with a new navigation or ordinary page refresh.

## Acceptance criteria

1. Parent selection is limited to observed apps with exact bundle/signing/Team identity; protected or unsigned identities cannot be selected.
2. Policy versions are monotonic, bounded to 32 rules and 12 KiB, signed in transit, cached root-only, and reject rollback/conflict.
3. A selected app launch triggers a visible warning and ordinary quit request. A refusal produces one bounded session-lock fallback, not a repeated lock loop.
4. Unselected apps continue to launch. A same-bundle/different-Team identity does not match. An empty newer policy restores access.
5. Rules continue with activity sharing disabled and across parent disconnect/restart; upgrade preserves pairing and existing schedule/browser policy.
6. Parent audit records distinguish policy queueing, quit request, confirmed close, and lock fallback. No command line, document/window content, or mutable app path is transmitted.
7. Controller arm64 and child universal binaries build into one selectable unsigned/ad-hoc developer package with SHA-256 verification. Physical standard-user testing remains required.

## Resource and cleanup limits

Use no more than two build workers, one checkout, one Stage-06E derived-data tree and one current macOS installer. Keep at least 5 GiB free. Run unit/protocol tests before the universal Release build. Remove project-owned `dist`, derived data and package staging after verifying the replacement candidate; preserve browser test packages unchanged and do not touch installed developer processes or simulator data.

## Manual developer test checklist

1. Install Parent Controller and Child Endpoint from `ParentalControlSystem-0.6.5-rc.2.pkg` over RC1 without uninstalling or unpairing. Keep the browsers and installed extensions in place; do not reload an extension. Confirm the same child returns Online.
2. Use a standard child account and retain a separate adult administrator. Open one signed third-party test app once so its exact identity appears in Devices > Application-use restrictions.
3. Select that app and apply the policy. Confirm the audit reports queued/delivered policy metadata without paths or content.
4. Leave the selected app open while applying the policy. It must show the visible restriction banner and receive a normal quit request promptly (the bounded reconciliation scan is at most 15 seconds). Re-launch it and confirm launch notification enforcement also works. Confirm a `quit-requested` and then `closed` audit event.
5. With unsaved content in an explicitly disposable test document, cancel/refuse the app's quit prompt. After five seconds the session should lock once. Sign back in and close the app; confirm there is no recurring five-second schedule lock loop.
6. Launch an unselected signed third-party app: it remains available. Apple/system and Parental Control apps are marked Protected and cannot be selected.
7. Disable application-name sharing: the selected app remains restricted. Disconnect the parent: cached restriction remains. Reconnect and verify the device returns Online.
8. With the existing enrolled browser extension still installed, keep the browser open during the child upgrade. Within 90 seconds or after opening a new tab, the parent profile must change from `Not reporting`/`Setup required` to the current policy acknowledgement. Navigate a new tab to `https://youtube.com` (or ordinarily refresh an existing tab); the blocked page must not load. Existing loaded video/content is not retroactively closed.
9. Reinstall the child component in place: pairing, schedule, browser policy, endpoint identity and app policy remain. No repair invitation, browser restart, or extension reinstall/reload is required.
10. Apply empty app and website policies: the formerly restricted app and a new browser navigation work normally.
11. Record CPU/memory over five idle minutes and report OS, hardware, app bundle ID, expected result, observed result, and only the bounded relevant audit/log lines.

## Rollback

Apply empty newer app and website policies before reverting. Installing Stage 06D RC5 over Stage 06E RC2 is not a supported database downgrade because Stage 06E adds schema fields, but the new fields are additive and ignored by older code. The administrator uninstaller remains reserved for intentional endpoint removal and is not an upgrade path.

## Automated and artifact evidence

- Repository contracts: 69 passed, one Windows-only cleanup check skipped on macOS.
- Controller/hub: 54 Swift Testing cases plus four XCTest cases passed with two workers, including policy bounds, aggregate IPC budget, migration and exact identity persistence.
- Endpoint: 31 Swift Testing cases plus six XCTest cases passed with two workers, including identity mismatch, protected-app exclusion, rollback/persistence, XPC authorization and one-attempt-per-process/policy fallback gating.
- Swift formatting, shell syntax and Git whitespace checks passed.
- `ParentalControlSystem-0.6.5-rc.2.pkg` was built from commit `b6316b70c9a4`, checksum-verified, and its selectable choices passed `installer -showChoicesXML` validation.
- Parent binary is `arm64`; child app and helpers are universal `x86_64 arm64`. Both apps passed deep/strict code-signature verification.
- SHA-256: `20d64ba1390dd189f45b30d1471f36b3061100456f54bc4aae0dda04df4081ce`.
- Signing status: embedded apps/helpers use hardened-runtime ad-hoc signatures with no Team ID. The product package is unsigned and not notarized. No Endpoint Security entitlement is present or claimed.

Physical clean-install, in-place-upgrade, standard-user behavior, refusal/lock fallback and idle-resource evidence remain the developer test gate.

AWAITING DEVELOPER TEST RESULT
