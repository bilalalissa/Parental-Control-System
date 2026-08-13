# STAGE-01 — Apple-silicon Parent Controller shell

- Version: `0.1.0-rc.2`
- Branch: `stage/01-controller-shell`
- Status: `CHANGES_REQUESTED`
- Platform: Apple-silicon macOS 14 or newer

## Objective and included scope

Deliver a native SwiftUI controller shell with local SQLite migrations, synthetic device data, dashboard, device details, schedule editor, chat and audit shells, settings, storage/retention controls, accessibility identifiers, a supported startup-at-login option, and an original controller icon.

## Exclusions

No LAN hub, pairing, endpoint connection, real chat transport, application or browser monitoring, command execution, policy signing/enforcement, privileged helper, relay/cloud service, MDM, or Stage 02+ behavior is included. All displayed family/device content is synthetic.

## Delivered

- Native SwiftUI `WindowGroup` and Settings scenes with dashboard, device detail, schedule, chat, audit, storage, retention, and privacy surfaces.
- Local SQLite schema migrations, bounded synthetic fixtures, and schedule-revision pruning.
- Distinct macOS, Windows, and standard-iPad capability combinations with explicit iPad limitations and approximate presence.
- Deterministic schedule validation, cross-midnight support, overlap rejection, warnings, quotas, and lock as the safe default.
- Stable accessibility identifiers, a visible Service Management start-at-login control, and one canonical original vector icon.
- Constrained two-worker SwiftPM build/run/package scripts and path-scoped macOS CI.

## Developer feedback revision

The `0.1.0-rc.2` retest adds three explicit chat audiences: direct, family group, and parent announcement. Family group and announcement modes address every synthetic child device and show the exact recipients. Composed items are visibly labeled as local previews and are never reported as transmitted or queued while Stage 02 transport remains out of scope. This revision also replaces the shelter/compass icon with a new original connected-family constellation derived from the single canonical SVG source.

Until the replacement RC is built and verified, the artifact details below describe the prior `0.1.0-rc.1` candidate retained under the replace-after-verification rule.

## Local verification

Tested on Apple silicon with macOS 26.5.2, Xcode 26.6, and Swift 6.3.3. No simulator was used.

- `npm test`: 24 passed; one Windows-only cleanup test skipped on macOS.
- `swift format lint --recursive apps/controller-macos/Sources apps/controller-macos/Tests`: passed without findings.
- `swift test` with project-owned cache, security, configuration, scratch, and module-cache paths plus `--jobs 2`: 10 tests in three suites passed.
- `./script/package_release.sh`: built the Release app, generated its icon, applied an ad-hoc signature, created one DMG, and passed `hdiutil verify`.
- `codesign --verify --deep --strict`: passed for the loose app and the read-only mounted DMG copy.
- `file` and `lipo -archs`: confirmed one thin arm64 Mach-O executable.
- `./script/build_and_run.sh --verify`: final committed app remained running after foreground launch, then was stopped.
- DMG mount smoke test: contained `Parental Control.app` and an `/Applications` link; packaged app architecture and signature checks passed.

The macOS accessibility inspection service did not attach within 90 seconds and was stopped without changing system permissions. Automated accessibility-identifier tests passed; visual and keyboard navigation remain on the manual checklist. The start-at-login toggle was not changed locally because that would modify the developer account's login items; its supported status/error handling compiled and is included for manual verification.

## Artifact and signing

- Artifact: `ParentalControlController-0.1.0-rc.1-arm64.dmg`
- Purpose: Apple-silicon macOS developer-test installer image
- SHA-256: `d66078dfc0c65b11a77c8313bb50049bc0d507b7b23e5324575f10f0bf1a28cc`
- Embedded source revision: `4148c6ab4020`
- App size before packaging: 2.3 MB
- DMG size: 1.4 MB
- Signing: ad-hoc; no Team ID, Developer ID signature, notarization, or restricted entitlements

## Installation and rollback

1. Open the DMG and drag **Parental Control.app** to **Applications**.
2. Launch the app from Applications. Because this is ad-hoc signed and not notarized, macOS may require an explicit developer-test approval.
3. To uninstall, quit Parental Control and move the app from Applications to Trash.
4. Optional data reset: after confirming the SQLite preview data is no longer wanted, remove `~/Library/Application Support/ParentalControlController` manually. The project cleanup tool intentionally does not delete user application data.

## Manual developer checklist

1. Verify the dashboard clearly says the data is synthetic and local-only.
2. Inspect macOS, Windows, and iPad device details; confirm iPad does not claim app/tab monitoring, shutdown, uptime, or reliable login state.
3. Confirm an offline device shows `Offline` plus last-seen time without claiming it is powered off.
4. Edit and save a valid schedule, then create overlapping windows and confirm validation blocks the save.
5. Confirm chat and remote-action controls are disabled pending Stage 02.
6. Open Settings and verify retention ranges, privacy disclosure, and start-at-login status text.
7. If desired, enable and disable start at login, approving it in System Settings when requested, and confirm any error is shown rather than hidden.
8. Navigate primary controls with keyboard and VoiceOver and confirm labels/identifiers are meaningful.
9. Quit, relaunch, and confirm the locally saved schedule remains available.
10. Uninstall using the steps above and report whether Gatekeeper, startup, layout, or accessibility behavior differs from this evidence.

## Resource and cleanup evidence

- Free disk before work: 12 GiB.
- Project-owned output before work: none; repository size was 652 KiB.
- Peak temporary project output: approximately 227 MiB across the one SwiftPM build tree, loose app, and packaging output.
- Five-minute idle sample: 11 readings at 30-second intervals; average reported CPU was 0.0%, below the 1% target.
- Idle RSS: peak 75,648 KiB (73.9 MiB), settling to 60,192 KiB (58.8 MiB), below the 250 MiB target.
- Free disk after cleanup: 13 GiB.
- Retained repository paths: one 1.4 MB DMG and its 4 KiB checksum under `.artifacts/release-candidate/` for developer testing.
- Retained application data: 156 KiB of bounded synthetic SQLite data under `~/Library/Application Support/ParentalControlController`; it is not build output and is left for developer testing.
- Removed: Derived Data/SwiftPM caches, package staging, loose app, nested accidental module cache, temporary mount/icon output, and the exact `/private/tmp/parental-control-module-cache` created during diagnosis.
- Project-started processes after checks: none.
- Simulator/emulator state: not used or changed.
- Resource-budget exceptions: none.

CI evidence is reported on the Stage 01 draft pull request and is intentionally not duplicated as a generated repository artifact.
