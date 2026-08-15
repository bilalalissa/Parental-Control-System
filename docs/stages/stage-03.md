# STAGE-03 — Universal macOS Child Agent foundation

- Version: `0.3.0-rc.2`
- Branch: `stage/03-macos-child-agent`
- Status: `MERGED`
- Platform: Apple-silicon and Intel macOS 14 or newer

## Objective and scope

Deliver a visible universal macOS child endpoint with a boot LaunchDaemon, login LaunchAgent helper, authenticated local XPC, explicit administrator pairing, authenticated LAN heartbeat, bounded device/uptime/session/network/health metadata, protected configuration, bounded redacted logs, a read-only child dashboard, a distinct endpoint icon, one selectable administrator `.pkg` containing the Parent Controller and Child Endpoint roles, and a visible endpoint uninstaller.

App monitoring, browser tabs, chat, schedules, enforcement, screenshots, keystrokes, content collection, arbitrary commands, public relay, cloud storage, covert behavior, and Stage 04+ work are excluded.

## Delivered design

- One SwiftPM endpoint package reuses the canonical Stage 02 `HubCore` protocol, Ed25519 envelopes, replay defense, TLS 1.3 certificate pinning, adaptive heartbeats, delta snapshots, and receipts.
- The daemon starts at boot through a LaunchDaemon. The per-user helper starts for Aqua login sessions and reports public active/inactive session transitions through a launchd Mach service. The installed app remains visible in Applications and shows a read-only disclosure dashboard.
- XPC clients explicitly connect to the privileged system launchd domain. The daemon resolves the kernel-supplied peer PID through the Security framework, then verifies effective UID, live code signature, signing identifier, exact installed executable path, root ownership, and non-writable app/binary modes. Session writes are helper-only; the visible app and typed diagnostic tool have status-only access. Rejections go only to the existing bounded/redacted endpoint log. A future Developer ID signature will add a stable team anchor.
- Administrator pairing uses one typed allowlisted tool. The one-use pairing invitation is stored mode `0600` in a mode `0700` root-owned directory and removed after acceptance. No general shell or process-launch interface exists.
- The device Ed25519 private key is the only new persistent endpoint secret and stays in Keychain. The dashboard/helper have no IPC password and do not access Keychain, minimizing password prompts during routine use.
- Metadata is bounded to 16 active non-loopback interfaces and eight addresses per interface. MAC addresses are display metadata only, never identity. Logs rotate across three 2 MiB files, redact secret-like fields, and truncate event data.
- Connection recovery uses bounded three-attempt bursts with two-second spacing, then a 60-second backoff. Identity/connection initialization errors no longer terminate the daemon or its XPC status service. Installer daemon bootstrap and package creation also use at most three attempts with short delays and fail closed.
- One product archive contains two explicit component choices. Parent Controller is selected by default; Child Endpoint is deselected by default and must be chosen through Customize. This supplies the previously missing parent installer without silently installing endpoint privileges on a parent Mac.
- Apple-silicon and Intel Release builds run sequentially with two workers. Four executables are combined once, verified as `x86_64 arm64`, and per-architecture build trees are deleted before packaging.

## Verification evidence

| Check | Result |
| --- | --- |
| Repository tests | 26 passed; one Windows-only cleanup test skipped on macOS (27 total). |
| Stage 02 controller/hub regression | 25 tests in 9 suites passed. |
| Stage 03 endpoint suite | 6 tests passed, including real pinned-TLS pairing, heartbeat, invitation consumption, and controller revocation. |
| Formatting | Swift format lint passed for controller core and endpoint sources/tests. |
| Configuration/log tests | Mode `0700`/`0600`, monotonic sequence persistence, pairing expiry, XPC authorization, metadata bounds, rotation, and redaction passed. |
| Universal verification | Child app, daemon, login helper, and typed pairing tool each report `x86_64 arm64`. |
| Package inspection | Product distribution, default/child selections, both component payloads, root-owned BOMs, launchd plists, postinstall, uninstaller syntax, and strict nested code signatures verified. |
| Disposable CI installation | Child-only selection installed; authenticated non-root `status` returned healthy/unpaired JSON; system daemon was running; endpoint uninstall removed exact files; default selection then installed only the Parent Controller. |
| Visible UI smoke | Final dashboard launched and remained running without an installed service; it truthfully displayed service unavailability. |
| Uninstalled resource sample | Idle daemon 13,872 KiB RSS / 0.0% CPU; login helper 32,704 KiB / 0.0%; combined about 45.5 MiB. Visible dashboard 90,752 KiB / 0.0%. |

The integration tests required permitted Keychain access because they create and remove an isolated TLS test identity. No Keychain password was entered. CI performed a real administrator install/status/uninstall/default-parent-install sequence on an ephemeral Apple-silicon macOS runner. The developer subsequently approved the physical parent/child result; Intel hardware execution and in-place upgrade from rc.1 were not separately reported.

## Developer test result

- Approved on 2026-08-15 with `APPROVED: STAGE-03 0.3.0-rc.2`.
- Merged on 2026-08-15 after the separate `MERGE` command.
- The developer confirmed the selectable parent and child installation paths, endpoint service status, token creation, physical-device pairing, bounded password-prompt behavior, revocation, unpairing, and successful fresh re-pairing.
- Closing **Parental Control Child.app** correctly leaves the child online because the visible dashboard and persistent LaunchDaemon have separate lifecycles. Offline means the authenticated daemon heartbeat has stopped, not that the dashboard window is closed.
- No additional code or artifact was required after physical testing; the approved package and checksum remain unchanged.

## Release candidate

- Artifact: `.artifacts/release-candidate/ParentalControlSystem-0.3.0-rc.2.pkg`
- SHA-256: `9de8db9f7c12d1318110f335cffbe61b708cc61ae3c52af447be9389170c6dd5`
- Embedded source commit: `b7217f850f2c`
- App and executable signing: local ad-hoc signatures, no Team ID or restricted entitlements
- Installer signing/notarization: unsigned and not notarized because no Developer ID Installer identity is available

Only this Stage 03 installer and checksum are retained. The rc.1 child-only package and prior Stage 02 local DMG were removed after the replacement package verified.

## Installation and pairing

1. On the parent Apple-silicon Mac, open the `.pkg`, keep the default **Parent Controller** selection, and approve installation.
2. If rc.1 is present on the child Mac, run its bundled uninstaller first.
3. On the child Mac, open the same `.pkg`, choose **Customize**, deselect **Parent Controller**, select **Child Endpoint**, and approve installation.
4. On the child, run `parental-control-agentctl status`; expect JSON with `"daemonHealthy":true` and `"connectionState":"unpaired"`.
5. Open **Parental Control** on the parent and create a one-time pairing token.
6. On the child, run `sudo parental-control-agentctl pair --invitation "$TOKEN"`.
7. Run `sudo launchctl kickstart -k system/com.bilalalissa.ParentalControlAgent.daemon`.
8. Open **Parental Control Child** from Applications. Because the candidate is ad-hoc signed and not notarized, macOS may require explicit approval to install or open it.

## Uninstallation / rollback

Run:

```sh
sudo "/Applications/Parental Control Child.app/Contents/Resources/uninstall.sh"
```

The script stops the exact project launchd/process labels and removes the app, launchd manifests, helper/tool, protected endpoint directory, logs, and endpoint Keychain item. This local endpoint data deletion is intentional and not recoverable unless separately backed up.

To roll back the parent preview, quit it and remove only `/Applications/Parental Control.app`; its existing Stage 02 local Application Support data is retained so this retest does not silently destroy controller state.

## Manual developer checklist

1. Verify the package checksum. Install the default role on the parent and the customized Child Endpoint role on the child; confirm both apps are visible in Applications.
2. On the child, run `parental-control-agentctl status` and confirm the daemon is healthy rather than showing “Endpoint service unavailable.”
3. Restart the child Mac. Before login, confirm the daemon is loaded; after an Aqua login, confirm exactly one per-user helper runs.
4. Confirm initial installation and two routine restarts do not repeatedly request a Keychain password. Report any SecurityAgent prompt with the exact step.
5. Pair using a fresh controller token; confirm the real macOS endpoint appears, the invitation cannot be reused, and device/OS/architecture/uptime/network/health fields update.
6. Switch active user sessions if available; confirm active/inactive transitions are truthful and helper health expires if the helper is stopped. A plain screen lock may remain `active` because no undocumented lock notification is used.
7. Stop the controller or LAN, confirm `Offline` plus last contact is shown without claiming power-off, then restore connectivity and confirm bounded retry recovery.
8. Revoke the endpoint in the controller and confirm its traffic is rejected; explicitly pair again only with a new token if continuing tests.
9. Confirm child settings are read-only and no app monitoring, tabs, chat, policy action, or enforcement appears.
10. On an Intel Mac, install and launch the child choice from the same package and repeat startup/pairing smoke checks.
11. Run the bundled uninstaller, restart/login, and confirm the exact app, jobs, helper/tool, support directory, logs, and endpoint key are gone.

## Known limitations

- This is a developer candidate without Developer ID signing or notarization. XPC therefore relies on kernel peer identity plus exact root-protected installed paths and ad-hoc identifiers; production team-anchored signature requirements remain release-hardening work.
- No schedule or contact record is available yet, so the dashboard says so instead of presenting invented state.
- Session transitions use supported `NSWorkspace` notifications and require the login helper; pre-login and exact lock state remain `unknown`/active rather than being inferred from undocumented signals.
- The controller does not yet render every new snapshot field in its UI; the signed deltas are persisted by the Stage 02 hub. Controller endpoint-detail expansion belongs to the stage that consumes those fields.
- The rc.1 physical-child failure was reproduced in CI: PID-to-path inspection returned no path for the live XPC peer. rc.2 resolves the live peer through the Security framework; CI and the developer’s two-device retest confirm installed status succeeds.
- In-place upgrade from rc.1 and Intel hardware execution were not separately reported; rc.1 was removed before installing rc.2 on the tested child.

## Resource and cleanup evidence

- Free disk before this retest: 12 GiB; the 5 GiB safety floor was maintained. The final build completed with 11 GiB free.
- Repository before implementation: about 5.0 MiB; retained Stage 02 RC: 2.9 MiB; existing controller Application Support data: about 352 KiB.
- Peak retest repository/build footprint: about 460 MiB total, including 442 MiB under `.artifacts` and 434 MiB in project-owned derived output.
- Sequential builds used two workers, one checkout, no worktree, no simulator, no VM, and no container. Per-architecture Release trees were empty immediately after `lipo` and removed.
- After cleanup: 11 GiB free; repository 11 MiB; `.artifacts` 7.7 MiB containing only the current `.pkg` and checksum.
- `cleanup:list` reports no generated output. No controller, hub, mock, child app, daemon, or login-helper process remains. No simulator/emulator was used.

## Failure evidence to collect

- `/var/log/com.bilalalissa.ParentalControlAgent.daemon.log`
- `/Library/Application Support/ParentalControlAgent/Logs/agent.log*` after reviewing for private family metadata
- `launchctl print system/com.bilalalissa.ParentalControlAgent.daemon`
- `launchctl print gui/$(id -u)/com.bilalalissa.ParentalControlAgent.user`
- `parental-control-agentctl status`
- The failing command, macOS version, hardware architecture, package checksum, and whether a Keychain/SecurityAgent prompt appeared
