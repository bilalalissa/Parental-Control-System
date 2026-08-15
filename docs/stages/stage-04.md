# STAGE-04 — macOS app activity and chat

- Version: `0.4.0-rc.1`
- Branch: `stage/04-macos-activity-chat`
- Status: `READY_FOR_DEVELOPER_TEST`
- Platform: Parent Controller on Apple silicon; Child Endpoint universal `arm64`/`x86_64`; macOS 14 or newer

## Objective and scope

Deliver configurable, event-driven macOS application-name activity and authenticated family communication over the existing local-first controller/hub/endpoint architecture.

Included: foreground/running regular-application names and bundle identifiers, one-to-thirty-day activity retention, immediate disable and pruning, direct chat, family group chat, parent announcements to all paired children, generic notifications, request-more-time, delivery states, bounded persistent offline queues, controller/child views, and content-free audit metadata.

Excluded: command lines, executable paths, window/document titles or contents, browser tabs, attachments, HTML, automatically opened links, screenshots, keystrokes, clipboard, camera/microphone, policy enforcement, remote actions, public relay, hosted storage, and Stage 05+ work.

## Delivered design

- The login helper uses public `NSWorkspace` launch, termination, and activation notifications. It reports at most 64 regular applications as name, bundle identifier, foreground state, and observation time; it does not continuously poll processes.
- Activity is capability-negotiated and sent as signed bounded deltas. Parent controls enable/disable collection and select one-to-thirty-day retention, seven days by default. Disabling clears retained activity for the device.
- Direct messages use one device thread. Family group messages fan out as separately authenticated per-device envelopes sharing one thread ID; child replies remain in that family thread. Announcements fan out to all paired child devices and remain parent-only.
- Chat uses `queued`, `sent`, `delivered`, `read`, and `failed` state. Controller queues are capped at 100 envelopes per device; endpoint views are capped at 200 messages and outbound queues at 100 items. Chat retention is thirty days.
- Endpoint messages and outbound items persist through daemon restarts in a mode-`0600` file under the existing mode-`0700` protected root. Controller chat/activity stays in local SQLite in a mode-`0700` application-support directory. Logs and audit rows omit message text.
- The visible child app provides Status, Chat, Request Time, and Privacy tabs. Notification permission is requested only when that visible app opens; the login helper never triggers a background permission prompt. Notifications show generic text and require an active logged-in user.
- Request-more-time records requested minutes and metadata but does not grant time or imply enforcement. Schedule enforcement remains a later stage.
- Offline signed envelopes remain replay-protected and fail after their explicit expiry; future timestamps and duplicate IDs/sequences still fail closed.
- Unpaired daemon startup no longer initializes the endpoint Keychain identity, avoiding an unnecessary secure-storage access before pairing.

## Verification evidence

| Check | Result |
| --- | --- |
| Repository tests | 26 passed; one Windows-only cleanup test skipped on macOS (27 total). |
| Controller/hub suite | 26 tests in 9 suites passed. |
| Endpoint suite | 7 tests passed, including live pinned-TLS pairing, parent→child group message, child→parent reply, request-time delivery, queue persistence, bounds, disable, and pruning. |
| Formatting/static checks | `swift format lint` and `git diff --check` passed. |
| Protocol contract | Canonical schema accepts the new allowlisted activity/configuration/chat/time-request types; invalid fixtures continue to fail closed. |
| Universal verification | Child app, daemon, login helper, and typed control tool each report `x86_64 arm64`. |
| Bundle/package verification | Embedded versions and commit, strict nested ad-hoc signatures, selectable choices XML, both component payloads, and SHA-256 verified. |
| Resource spot sample | Unpaired daemon: 14,467,072-byte maximum RSS and effectively zero CPU over five seconds. Login helper: 33,200 KiB RSS and 0.0% CPU after five seconds. Combined about 46.2 MiB. |

The resource run is a short local idle spot sample, not the five-minute production target measurement. It remains well below the 200 MiB combined endpoint target. The final installer was not installed locally because the development Mac has an existing approved controller installation and data; the draft PR CI is configured to perform disposable child install/status/uninstall and default-parent install checks. Those checks must be reported separately and not treated as local physical-hardware evidence.

## Release candidate

- Artifact: `.artifacts/release-candidate/ParentalControlSystem-0.4.0-rc.1.pkg`
- Purpose: selectable Parent Controller or universal visible macOS Child Endpoint
- SHA-256: `923bfa5a5071f44b4d5c8d026451302e26b5d714993ceaeb0d8f080c3aaef104`
- Embedded source commit: `b05435532fcc`
- App/executable signing: local ad-hoc signatures; no Team ID or restricted entitlements
- Installer signing/notarization: unsigned and not notarized because no Developer ID Installer identity is available

This single package replaces the Stage 03 local candidate. No duplicate `.app`, `.pkg`, `.dmg`, archive, or extracted package is retained after cleanup.

## Installation

1. Verify the SHA-256 checksum shown above.
2. On the parent Apple-silicon Mac, open the package and keep the default **Parent Controller** selection.
3. On each child Mac, open the same package, choose **Customize**, deselect **Parent Controller**, and select **Child Endpoint**.
4. Existing paired Stage 03 installations may be upgraded in place. If pairing is absent, create a fresh one-time token on the parent and run `sudo parental-control-agentctl pair --invitation "$TOKEN"` on the child, then `sudo launchctl kickstart -k system/com.bilalalissa.ParentalControlAgent.daemon`.
5. Open **Parental Control Child** once and choose whether to allow generic family notifications.

## Uninstallation / rollback

Run:

```sh
sudo "/Applications/Parental Control Child.app/Contents/Resources/uninstall.sh"
```

This intentionally removes the child app, launchd jobs, helper/tool, protected endpoint configuration, local endpoint chat queue, logs, and endpoint Keychain item. To roll back the parent, quit it and reinstall the approved Stage 03 package; preserve controller Application Support if its local pairing/chat history is needed.

## Manual developer checklist

1. Install the default parent role and customized child role; confirm both visible apps report `0.4.0-rc.1`.
2. Confirm existing Stage 03 pairing survives an in-place upgrade, or pair with a fresh one-time token.
3. Open several normal applications on the child. In Parent Controller → Devices, expand the child and confirm only names, bundle IDs, foreground state, and timestamps appear—never command lines, paths, window titles, or contents.
4. Disable **Share application names**. Confirm the child Privacy tab says sharing is disabled and retained activity disappears from the parent. Re-enable and test retention values from one to thirty days.
5. Send a direct parent message while online. Confirm child notification behavior, visible text, and delivered/read transitions.
6. Send a family group message with at least two paired children. Confirm each receives it and a child reply appears in the parent family group thread.
7. Send an announcement. Confirm every paired child receives it and it is clearly labeled as an announcement.
8. Disconnect or stop one child daemon, send a message, confirm `Queued`, restore the daemon/LAN, and confirm delivery without duplicate text. Do not infer power-off.
9. From the child, request 20 minutes with an optional note. Confirm the parent displays the pending request but does not automatically grant or enforce time.
10. Restart the child daemon while an outbound child message is queued and confirm the protected queue survives and later delivers.
11. Confirm routine daemon restarts and chat/activity use do not repeatedly request a Keychain password. Notification authorization should be requested only by the visible child app.
12. Confirm closing only the visible child window does not mark the endpoint offline; stopping the authenticated daemon eventually shows `Offline` plus last-seen time.
13. On an Intel Mac if available, repeat installation, activity, chat, restart, and uninstall checks.
14. Run the bundled uninstaller and confirm the exact app/jobs/helper/tool/protected endpoint directory are removed.

## Known limitations

- This is an ad-hoc-signed, installer-unsigned, non-notarized developer candidate.
- Local evidence covers Apple-silicon compilation/runtime and universal binary inspection. Intel execution requires physical Intel hardware or CI evidence.
- Notifications are best effort, generic, and require an active user session plus permission. There is no cloud push or public relay.
- Activity is current/recent metadata, not usage-duration accounting. Browser tabs remain unavailable until the separately approved visible-extension stage.
- Request-more-time is communication only; it does not alter a schedule because enforcement is excluded.
- Controller/endpoint local storage is protected by operating-system ownership and file modes; this candidate does not add field-level database encryption.

## Resource and cleanup evidence

- Free disk before Stage 04: 11 GiB; repository including the retained Stage 03 RC: 11 MiB; project-owned output: 7.7 MiB.
- Debug test output peaked near 358 MiB and was removed before the Release build.
- Peak final repository-owned generated output: about 467 MiB, including 458 MiB of derived output and a 20 MiB transient `dist` tree. Free disk remained 11 GiB, above the 5 GiB floor.
- Builds used two workers, one checkout, one macOS build tree, sequential endpoint architectures, no simulator, no VM, no container, and no worktree.
- Final cleanup retains only the 9.3 MiB package and checksum. No simulator/emulator was used.
- The resource daemon and helper processes were stopped. The pre-existing installed Parent Controller/Hub processes were not started by Stage 04 and were deliberately preserved.

## Failure evidence to collect

- `/var/log/com.bilalalissa.ParentalControlAgent.daemon.log`
- `/Library/Application Support/ParentalControlAgent/Logs/agent.log*` after reviewing for family metadata
- `launchctl print system/com.bilalalissa.ParentalControlAgent.daemon`
- `launchctl print gui/$(id -u)/com.bilalalissa.ParentalControlAgent.user`
- `parental-control-agentctl status`
- Exact sender/audience/delivery state without copying private chat text
- macOS version, hardware architecture, package checksum, and whether a Keychain or notification prompt appeared
