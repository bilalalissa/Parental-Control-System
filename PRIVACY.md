# Privacy Principles

This project is designed for transparent parental controls, not covert surveillance.

## Data minimization

The planned controller stores operational data locally. Endpoints send only enabled, platform-supported fields needed for status, policy, safety actions, and family communication. Detailed application and tab metadata is optional per device, bounded, and retained for a short configurable period.

The project does not collect keystrokes, screenshots, camera or microphone recordings, clipboard contents, messages from other applications, documents, passwords, form fields, cookies, page contents, private browsing sessions, command-line arguments, or arbitrary files. Browser metadata is limited to the browser, a pseudonymous profile, title, origin/domain, active state, and timestamp; query strings and fragments are removed.

## Storage and transport

- Controller and hub device, app-activity, chat, receipt, request, and audit records use local SQLite storage in a mode-0700 application-support directory.
- Secrets and private keys must use platform secure storage.
- Controller/endpoint transport must be authenticated and encrypted.
- Logs and queues must be bounded, redacted, and pruned.
- Diagnostic bundles must be user-triggered, reviewable, sanitized, temporary, and compressed only once.
- Synthetic fixtures are the only device/user data allowed in this public repository.

Bonjour discovery, pairing, app activity, browser metadata, chat, and requests stay on the authenticated local network. Stage 04 app activity is limited to regular application names, bundle identifiers, foreground state, and observation time. It excludes command lines, executable paths, window/document titles, and content. Stage 05 browser sharing is off by default and requires a visible Chrome/Edge extension. It sends only browser, pseudonymous local profile, tab title, HTTP(S) origin, active state, and observation time; the extension filters private tabs and strips paths, queries, fragments, credentials, and other page data before native messaging. Chat contents are stored only in protected local controller/endpoint storage; audit logs and generic notifications record no message content. The public repository, logs, and audit details do not retain pairing codes, certificate private keys, family network addresses, real device identifiers, tab titles/origins, or chat contents.

Stage 05 defaults to seven days for app and browser metadata and thirty days for chat; app and browser retention are independently configurable from one to thirty days per device. Either metadata collection can be disabled immediately, clearing its retained records for that device. Browser snapshots are capped at 128 records per device. Queues, activity lists, browser records, chat history, requests, receipts, and audit records have tested bounds.

## Transparency and control

The installed endpoint must identify itself, show that parental controls are active, explain what it shares, show the effective schedule, and offer a way to contact the parent or request time. Child settings are read-only; changes require authenticated adult approval and any administrator authorization required by the operating system.

Unreachable devices are displayed as `Offline` with a last-seen time. The system must never infer that an offline device is powered off.

## iPadOS limitations

A standard iPadOS app cannot continuously report presence, hardware MAC address, reliable uptime, desktop login state, foreground apps, browser tabs, or perform global logout, restart, or shutdown. The project will use only public Family Controls APIs and will label presence as approximate.
