# STAGE-03 — Universal macOS Child Agent foundation

- Version: `0.3.0-rc.1`
- Branch: `stage/03-macos-child-agent`
- Status: `READY_FOR_DEVELOPER_TEST`
- Platform: Apple-silicon and Intel macOS 14 or newer

## Objective and scope

Deliver a visible universal macOS child endpoint with a boot LaunchDaemon, login LaunchAgent helper, authenticated local XPC, explicit administrator pairing, authenticated LAN heartbeat, bounded device/uptime/session/network/health metadata, protected configuration, bounded redacted logs, a read-only child dashboard, a distinct endpoint icon, one administrator `.pkg`, and a visible uninstaller.

App monitoring, browser tabs, chat, schedules, enforcement, screenshots, keystrokes, content collection, arbitrary commands, public relay, cloud storage, covert behavior, and Stage 04+ work are excluded.

## Delivered design

- One SwiftPM endpoint package reuses the canonical Stage 02 `HubCore` protocol, Ed25519 envelopes, replay defense, TLS 1.3 certificate pinning, adaptive heartbeats, delta snapshots, and receipts.
- The daemon starts at boot through a LaunchDaemon. The per-user helper starts for Aqua login sessions and reports public active/inactive session transitions through a launchd Mach service. The installed app remains visible in Applications and shows a read-only disclosure dashboard.
- XPC verifies the kernel-supplied effective UID and PID, the code-signing identifier, the exact installed executable path, root ownership, and non-writable app/binary modes. Session writes are helper-only; the visible app has status-only access. A future Developer ID signature will add a stable team anchor.
- Administrator pairing uses one typed allowlisted tool. The one-use pairing invitation is stored mode `0600` in a mode `0700` root-owned directory and removed after acceptance. No general shell or process-launch interface exists.
- The device Ed25519 private key is the only new persistent endpoint secret and stays in Keychain. The dashboard/helper have no IPC password and do not access Keychain, minimizing password prompts during routine use.
- Metadata is bounded to 16 active non-loopback interfaces and eight addresses per interface. MAC addresses are display metadata only, never identity. Logs rotate across three 2 MiB files, redact secret-like fields, and truncate event data.
- Connection recovery uses bounded three-attempt bursts with two-second spacing, then a 60-second backoff. Installer daemon bootstrap and package creation also use at most three attempts with short delays and fail closed.
- Apple-silicon and Intel Release builds run sequentially with two workers. Four executables are combined once, verified as `x86_64 arm64`, and per-architecture build trees are deleted before packaging.

## Verification evidence

| Check | Result |
| --- | --- |
| Repository tests | 25 passed; one Windows-only cleanup test skipped on macOS (26 total). |
| Stage 02 controller/hub regression | 25 tests in 9 suites passed. |
| Stage 03 endpoint suite | 6 tests passed, including real pinned-TLS pairing, heartbeat, invitation consumption, and controller revocation. |
| Formatting | Swift format lint passed for controller core and endpoint sources/tests. |
| Configuration/log tests | Mode `0700`/`0600`, monotonic sequence persistence, pairing expiry, XPC authorization, metadata bounds, rotation, and redaction passed. |
| Universal verification | Child app, daemon, login helper, and typed pairing tool each report `x86_64 arm64`. |
| Package inspection | Expanded payload, BOM, launchd plists, postinstall, uninstaller syntax, and strict nested code signatures verified. |
| Visible UI smoke | Final dashboard launched and remained running without an installed service; it truthfully displayed service unavailability. |
| Uninstalled resource sample | Idle daemon 13,872 KiB RSS / 0.0% CPU; login helper 32,704 KiB / 0.0%; combined about 45.5 MiB. Visible dashboard 90,752 KiB / 0.0%. |

The integration tests required permitted Keychain access because they create and remove an isolated TLS test identity. No Keychain password was entered. The final root installation, pre-login boot start, Aqua login start, real session transition, Intel hardware execution, upgrade, and clean uninstall have not been performed locally; those remain developer/CI physical-machine checks.

## Release candidate

- Artifact: `.artifacts/release-candidate/ParentalControlChild-0.3.0-rc.1-universal.pkg`
- SHA-256: populated after the source commit and final verified rebuild
- App and executable signing: local ad-hoc signatures, no Team ID or restricted entitlements
- Installer signing/notarization: unsigned and not notarized because no Developer ID Installer identity is available

Only this Stage 03 installer and checksum are retained. The prior Stage 02 local DMG was removed after the replacement package verified.

## Installation and pairing

1. Open the `.pkg` and approve the administrator installation. This visibly installs **Parental Control Child.app**, its boot daemon, and its login helper.
2. Open the Parent Controller and create a one-time pairing token.
3. Run `sudo parental-control-agentctl pair --invitation "$TOKEN"`.
4. Run `sudo launchctl kickstart -k system/com.bilalalissa.ParentalControlAgent.daemon`.
5. Open **Parental Control Child** from Applications. Because the candidate is ad-hoc signed and not notarized, macOS may require explicit approval to install or open it.

## Uninstallation / rollback

Run:

```sh
sudo "/Applications/Parental Control Child.app/Contents/Resources/uninstall.sh"
```

The script stops the exact project launchd/process labels and removes the app, launchd manifests, helper/tool, protected endpoint directory, logs, and endpoint Keychain item. This local endpoint data deletion is intentional and not recoverable unless separately backed up.

## Manual developer checklist

1. Verify the package checksum, install on Apple-silicon macOS 14+, and confirm the app is visible in Applications.
2. Restart the Mac. Before login, confirm the daemon is loaded; after an Aqua login, confirm exactly one per-user helper runs.
3. Confirm initial installation and two routine restarts do not repeatedly request a Keychain password. Report any SecurityAgent prompt with the exact step.
4. Pair using a fresh controller token; confirm the real macOS endpoint appears, the invitation cannot be reused, and device/OS/architecture/uptime/network/health fields update.
5. Switch active user sessions if available; confirm active/inactive transitions are truthful and helper health expires if the helper is stopped. A plain screen lock may remain `active` because no undocumented lock notification is used.
6. Stop the controller or LAN, confirm `Offline` plus last contact is shown without claiming power-off, then restore connectivity and confirm bounded retry recovery.
7. Revoke the endpoint in the controller and confirm its traffic is rejected; explicitly pair again only with a new token if continuing tests.
8. Confirm child settings are read-only and no app monitoring, tabs, chat, policy action, or enforcement appears.
9. On an Intel Mac or CI runner, install and launch the same package and repeat startup/pairing smoke checks.
10. Run the bundled uninstaller, restart/login, and confirm the exact app, jobs, helper/tool, support directory, logs, and endpoint key are gone.

## Known limitations

- This is a developer candidate without Developer ID signing or notarization. XPC therefore relies on kernel peer identity plus exact root-protected installed paths and ad-hoc identifiers; production team-anchored signature requirements remain release-hardening work.
- No schedule or contact record is available yet, so the dashboard says so instead of presenting invented state.
- Session transitions use supported `NSWorkspace` notifications and require the login helper; pre-login and exact lock state remain `unknown`/active rather than being inferred from undocumented signals.
- The controller does not yet render every new snapshot field in its UI; the signed deltas are persisted by the Stage 02 hub. Controller endpoint-detail expansion belongs to the stage that consumes those fields.
- Actual administrator install/upgrade/uninstall, boot/login behavior, and Intel execution require developer or CI testing.

## Failure evidence to collect

- `/var/log/com.bilalalissa.ParentalControlAgent.daemon.log`
- `/Library/Application Support/ParentalControlAgent/Logs/agent.log*` after reviewing for private family metadata
- `launchctl print system/com.bilalalissa.ParentalControlAgent.daemon`
- `launchctl print gui/$(id -u)/com.bilalalissa.ParentalControlAgent.user`
- The failing command, macOS version, hardware architecture, package checksum, and whether a Keychain/SecurityAgent prompt appeared
