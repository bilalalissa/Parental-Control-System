# STAGE-05 — Shared Chromium extension and macOS integration

- Version: `0.5.0-rc.1`
- Branch: `stage/05-chromium-extension`
- Status: `IMPLEMENTING`
- Platform: Chrome and Microsoft Edge on a universal macOS child endpoint; Parent Controller on Apple silicon; macOS 14 or newer

## Objective and scope

Deliver one visible Manifest V3 WebExtension source for Chrome and Edge, one packaged extension, and a narrowly authenticated macOS native-messaging host. When the parent explicitly enables sharing, collect at most 128 open HTTP(S) tab titles and query-free origins with browser, pseudonymous local profile, active state, and observation time. Exclude private tabs and clear retained metadata immediately when disabled.

Complete the deferred Stage 04 chat feedback: generic system-controlled arrival sound for both parent and child receivers, distinct `Sent`, `Delivered`, and `Read` indicators, durable acceptance before `Delivered`, and an explicit relevant-conversation visibility event before `Read`.

Excluded: Safari, browser history, page/document contents, full URLs or paths, query strings, fragments, forms, cookies, passwords, private browsing, downloads, bookmarks, network traffic, screenshots, keystrokes, clipboard, message contents in logs/audit/notification diagnostics, schedule enforcement, remote actions, public relay, cloud storage, and Stage 06+ work.

## Delivered design

- The shared extension requests only `tabs`, `storage`, `nativeMessaging`, and `alarms`. It filters private tabs, accepts only HTTP(S), converts URLs to origins, caps each update at 128 records, debounces change events by 500 ms, and performs one bounded 15-minute reconciliation.
- The deterministic extension identity is embedded as a public manifest key. The native-host manifest allows exactly that extension origin and points to one installed universal helper.
- The native host verifies the exact extension origin and the valid signed parent browser process at an expected Google Chrome or Microsoft Edge application path. Endpoint XPC independently restricts browser configuration and updates to the signed, root-protected installed host.
- Browser sharing defaults off. The parent enables it per child and chooses one-to-thirty-day retention; disabling clears endpoint memory and controller SQLite records. The visible child app and extension popup disclose the exact fields and exclusions.
- Browser records reuse the signed, replay-protected local TLS channel. Controller storage is bounded to 128 records per device and audit metadata omits titles and origins.
- A receiving child or parent uses an ordinary generic UserNotifications notification with the default sound. macOS notification permission, mute, Focus, and sound preferences remain authoritative.
- `Delivered` is set only after the receiving side durably saves the message and returns an authenticated receipt. `Read` is sent only when the receiver opens the relevant conversation; dashboard/status refreshes do not mark messages read.

## Verification evidence

Verification results, artifact hashes, signing status, CI evidence, and resource measurements will be completed before this stage changes to `READY_FOR_DEVELOPER_TEST`.

## Installation outline

1. Install the selectable macOS package, choosing the Parent Controller on the parent Mac and the Child Endpoint on the child Mac.
2. Extract the single browser-extension ZIP into one stable child-owned folder.
3. In Chrome or Edge, open the extensions page, enable Developer mode, choose **Load unpacked**, and select the extracted `ParentalControlBrowserSharing` folder. Do not enable the extension in private/incognito mode.
4. On the parent, expand the paired child in Devices and explicitly enable **Share browser tab titles and website origins**. Retention defaults to seven days.

## Known development-candidate limitations

- The extension is a developer package, not Chrome Web Store or Microsoft Edge Add-ons signed/distributed. Each browser profile must load it explicitly.
- The app/helper signatures are local ad-hoc signatures; the installer and ZIP are unsigned and not notarized.
- Browser collection depends on the visible extension, installed child endpoint, active paired daemon, and local LAN. There is no relay or background cloud delivery.
- Tab metadata is a current bounded snapshot, not browsing history or usage-duration accounting.
