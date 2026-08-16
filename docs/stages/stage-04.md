# STAGE-04 — macOS app activity and chat

- Version: `0.4.0-rc.3`
- Branch: `stage/04-macos-activity-chat`
- Status: `READY_FOR_RETEST`
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

## rc.2 feedback corrections

- The controller hub now listens on stable LAN port `49171`. Already-paired rc.1 endpoints transparently migrate from their stored ephemeral port after upgrading, while the TLS certificate fingerprint and signed device/controller identities remain pinned. The endpoint integration test stops and recreates the hub, then proves the same pairing reconnects without a new token.
- The child postinstall refreshes the current GUI launch-agent registration and starts it with the same bounded three-attempt/two-second-delay policy as the daemon. The launch agent also restarts after abnormal termination, resolving the observed `helperHealthy:false` state after upgrade.
- The paired-device row now uses a dedicated labeled expansion button, separate Revoke/Unpair actions, and a labeled activity toggle. This removes the nested interactive `DisclosureGroup` label that remained collapsed under both pointer and accessibility activation.
- No activity fields were broadened. The child status and parent database continue to accept only application name, bundle identifier, foreground state, and observation timestamp.

## rc.3 feedback correction

- Physical Intel-device logs proved the signed visible child app was rejected only because macOS reported its canonical signed bundle path (`/Applications/Parental Control Child.app`) while the daemon expected only the inner executable path. Signature validity, signing identifier, root ownership, and protected permissions all passed.
- XPC authorization now narrowly accepts either canonical installed representation for the child identifier: the root-protected application bundle or its inner main executable. It still requires a valid signature, the exact child signing identifier, a non-root caller, and protected ownership/permissions; arbitrary paths remain rejected.
- Regression coverage exercises both accepted child paths and rejection outside `/Applications`.

## Verification evidence

| Check | Result |
| --- | --- |
| Repository tests | 28 passed; one Windows-only cleanup test skipped on macOS (29 total). |
| Controller/hub suite | 26 tests in 9 suites passed. |
| Endpoint suite | rc.3 affected XPC authorization test passed locally. The unchanged live-pairing test could not bind port `49171` while the developer Mac's installed hub was running; all 8 endpoint tests then passed on the isolated macOS CI runner. |
| Formatting/static checks | `swift format lint` and `git diff --check` passed. |
| Protocol contract | Canonical schema accepts the new allowlisted activity/configuration/chat/time-request types; invalid fixtures continue to fail closed. |
| Universal verification | Child app, daemon, login helper, and typed control tool each report `x86_64 arm64`. |
| Bundle/package verification | CI and local inspection verified embedded `0.4.0-rc.3`/build `4003`, the tested PR merge commit, strict nested ad-hoc signatures, universal slices, selectable choices XML, both component payloads, and SHA-256. |
| Resource spot sample | Unpaired daemon: 14,467,072-byte maximum RSS and effectively zero CPU over five seconds. Login helper: 33,200 KiB RSS and 0.0% CPU after five seconds. Combined about 46.2 MiB. |

The resource run is a short local idle spot sample, not the five-minute production target measurement. It remains well below the 200 MiB combined endpoint target. The final installer was not installed locally because the development Mac has an existing approved controller installation and data; the draft PR CI is configured to perform disposable child install/status/uninstall and default-parent install checks. Those checks must be reported separately and not treated as local physical-hardware evidence.

## Release candidate

- Artifact: `.artifacts/release-candidate/ParentalControlSystem-0.4.0-rc.3.pkg`
- Purpose: selectable Parent Controller or universal visible macOS Child Endpoint
- SHA-256: `f4b4c3924114cbff7c1dc00ff13c5f788ccbe32a84d7b07e724e6d56bd4fee37`
- Embedded head source commit: `26df6922fb22`
- App/executable signing: local ad-hoc signatures; no Team ID or restricted entitlements
- Installer signing/notarization: unsigned and not notarized because no Developer ID Installer identity is available

This single package replaces the rejected Stage 04 rc.2 candidate. No duplicate `.app`, `.pkg`, `.dmg`, archive, or extracted package is retained after cleanup.

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

1. Install the default parent role and customized child role; confirm both visible apps report `0.4.0-rc.3`.
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
- The rc.2 feedback run began with 8.7 GiB free and 9.3 MiB of retained project output. Generated output peaked near 506 MiB (450 MiB derived data, 20 MiB `dist`, 27 MiB expanded inspection, and the 9.3 MiB RC); the lowest observed free space was 7.8 GiB.
- Final rc.2 cleanup restored 8.3 GiB free and retains only the 9.3 MiB package plus checksum. One explicit administrator ownership repair was required for stale repository-owned `dist/ParentalControlController.app` output from the earlier package run; the generated tree was then rebuilt and removed normally.
- The rc.3 diagnosis began with 8.2 GiB free and 9.3 MiB retained output. Local targeted test output peaked at 188 MiB; free space measured 5.6 GiB, so the release build moved to the isolated CI runner rather than risking the 5 GiB floor. After project cleanup and local package inspection, 5.6 GiB is free and only the 9.2 MiB rc.3 package/checksum remain. No simulator, VM, container, or project-started process remains.

## Failure evidence to collect

- `/var/log/com.bilalalissa.ParentalControlAgent.daemon.log`
- `/Library/Application Support/ParentalControlAgent/Logs/agent.log*` after reviewing for family metadata
- `launchctl print system/com.bilalalissa.ParentalControlAgent.daemon`
- `launchctl print gui/$(id -u)/com.bilalalissa.ParentalControlAgent.user`
- `parental-control-agentctl status`
- Exact sender/audience/delivery state without copying private chat text
- macOS version, hardware architecture, package checksum, and whether a Keychain or notification prompt appeared
