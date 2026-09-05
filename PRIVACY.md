# Privacy Principles

This project is designed for transparent parental controls, not covert surveillance.

## Data minimization

Stage-06D's amended browser-only scope applies adult-selected bare domains through declarative browser rules. No request/page content, blocked URL history, DNS logs, forms or cookies are collected. Rules are independent of tab-sharing consent. Profile coverage reports contain only browser name, a pseudonymous profile identifier, policy version, outcome and timestamp. Known-browser detection checks fixed application locations, not profile contents. Private/guest sessions are excluded and remain unprotected gaps. Reports are bounded (24 enrolled profiles plus known browsers) and replaced, not an unbounded history. Browser publisher services, if separately authorized, receive extension code for signing/publication—not family policies or browsing data.

The planned controller stores operational data locally. Endpoints send only enabled, platform-supported fields needed for status, policy, safety actions, and family communication. Detailed application and tab metadata is optional per device, bounded, and retained for a short configurable period.

The project does not collect keystrokes, screenshots, camera or microphone recordings, clipboard contents, messages from other applications, documents, passwords, form fields, cookies, page contents, private browsing sessions, command-line arguments, or arbitrary files. Browser metadata is limited to the browser, a pseudonymous profile, title, origin/domain, active state, and timestamp; query strings and fragments are removed.

## Storage and transport

- Controller and hub device, app-activity, chat, receipt, request, and audit records use local SQLite storage in a mode-0700 application-support directory.
- Secrets and private keys must use platform secure storage.
- Controller/endpoint transport must be authenticated and encrypted.
- Logs and queues must be bounded, redacted, and pruned.
- Diagnostic bundles must be user-triggered, reviewable, sanitized, temporary, and compressed only once.
- Synthetic fixtures are the only device/user data allowed in this public repository.

Bonjour discovery, pairing, app activity, browser metadata, chat, and requests stay on the authenticated local network. Stage 04 app activity is limited to regular application names, bundle identifiers, foreground state, and observation time. It excludes command lines, executable paths, window/document titles, and content. Stage 05 browser sharing is off by default and requires a visible Chrome/Edge/Arc extension. It sends only browser, pseudonymous local profile, tab title, HTTP(S) origin, active state, and observation time; the extension filters private tabs and strips paths, queries, fragments, credentials, and other page data before native messaging. Chat contents are stored only in protected local controller/endpoint storage; audit logs and generic notifications record no message content. The public repository, logs, and audit details do not retain pairing codes, certificate private keys, family network addresses, real device identifiers, tab titles/origins, or chat contents.

Stage 05 defaults to seven days for app and browser metadata and thirty days for chat; app and browser retention are independently configurable from one to thirty days per device. Either metadata collection can be disabled immediately, clearing its retained records for that device. Browser snapshots are capped at 128 records per device. Queues, activity lists, browser records, chat history, requests, receipts, and audit records have tested bounds.

Stage 06 adds one current per-device signed policy and a small protected runtime record containing quota timing, warning/grace state, clock continuity, and a salted adult-code verifier. The six-digit adult code is displayed only in the parent UI and is not written to endpoint logs, audit records, or the repository. Policy/action receipts contain state metadata, not family explanations or private activity. No Stage-06 action expands application, browser, chat, screenshot, microphone, camera, clipboard, keystroke, or content collection.

Stage 06A is a source-only feasibility review. It creates no third-party MDM account, APNs certificate, enrollment profile, API key, device record, or external data transfer. A future separately approved MDM test would necessarily disclose limited device and management inventory to that vendor; it must use synthetic account names, exclude chat/app/browser/family content, document vendor retention, and delete the test record afterward. The local-first product must continue working without the vendor.

Stage 06B is also source-only. It creates no IdP/MDM account, managed identity, SSO extension, registration, attestation, profile, credential, device record, or external data transfer. A separately approved Platform SSO pilot would disclose a synthetic account and limited device/registration state to the named providers. Device identifiers in attestation remain disabled unless separately justified. The pilot must exclude real names and all chat, app, browser, schedule, network-address, and family content; document provider purpose and retention; and delete the synthetic identity and device record after rollback. The local-first product continues without the provider.

Stage 06C is source-only. It creates no router login, credential, configuration, firewall rule, device mapping, packet capture, traffic record, external account, or installer. Network-content inspection is prohibited. The named router's serial number, gateway MAC, household client addresses, host names, and access credentials are excluded from the public repository. A later adapter may retain only a pseudonymous approved client mapping and bounded lease/audit state. It may not retain DNS history, destinations, URLs, packet data, unrelated client inventory, or router credentials outside Keychain. All control stays on the local network.

Stage 06D is source-only while Apple signing readiness is blocked. Entitlement templates contain no credentials, and provisioning profiles, certificates, private keys, Team credentials, notarization secrets, device addresses, and physical-test logs must never enter the repository. A later approved filter may retain only adult-entered normalized domain rules, selected application code identities, bounded lease metadata, and redacted receipts. It may not retain URLs, paths, queries, DNS or browsing history, packets, payloads, unrelated destinations, or unrelated process events. No network-content inspection is permitted.

## Transparency and control

The installed endpoint must identify itself, show that parental controls are active, explain what it shares, show the effective schedule, and offer a way to contact the parent or request time. Child settings are read-only; changes require authenticated adult approval and any administrator authorization required by the operating system.

Unreachable devices are displayed as `Offline` with a last-seen time. The system must never infer that an offline device is powered off.

## iPadOS limitations

A standard iPadOS app cannot continuously report presence, hardware MAC address, reliable uptime, desktop login state, foreground apps, browser tabs, or perform global logout, restart, or shutdown. The project will use only public Family Controls APIs and will label presence as approximate.
