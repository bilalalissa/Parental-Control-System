# Canonical protocol contract

[`message.schema.json`](message.schema.json) is the single canonical wire-envelope definition. Implementations may generate platform types from it in temporary or platform-required generated locations; copied schema variants are not authoritative.

## Envelope rules

Every message carries a UUID message ID, protocol version, device ID, UTC timestamp, optional expiry, monotonic per-sender sequence, allowlisted type, bounded object payload, and authentication metadata. Production messages use TLS 1.3 where supported and an Ed25519 signature over a documented canonical encoding introduced before networking is implemented.

Messages fail closed when they are malformed, expired, replayed, signed by an unknown/revoked key, out of the negotiated protocol range, or unsupported by the destination. Stage 04 adds allowlisted app-activity delta/configuration, chat, and more-time request messages. Stage 05 adds allowlisted browser-tab update/configuration messages containing only browser, pseudonymous profile, title, query/fragment-free origin, active state, and observation time. It also permits authenticated parent-only `chat.mutation` edit/delete operations tied to an existing message ID; deletion clears the body and leaves a visible tombstone. Stage 06 adds authenticated `time.request-resolution` messages so an approval or rejection is durably reflected on the child endpoint. Chat receipts may use `queued`, `sent`, `delivered`, `read`, or `failed`; other command receipts use `accepted`, `started`, `succeeded`, `failed`, `expired`, `unsupported`, or `denied`. Receipt and audit payloads identify the original message without copying sensitive content.

The protocol deliberately has no arbitrary shell, script, file-browsing, or unrestricted process command.

## Versioning

### Stage-06D browser policy extension

The existing signed `browser.configuration` envelope may carry `websitePolicy`, a UTF-8 JSON string with `{version, domains}`. Version is a positive JavaScript-safe integer. Domains are unique sorted lowercase ASCII DNS names (international names must be explicit punycode), at most 256 entries and 32 KiB total domain bytes, with labels of 1–63 characters and names of at most 253 bytes. URLs, IP literals, wildcards, local names, paths and query strings are invalid. An explicit newer empty list removes restrictions; absence preserves the existing policy. Scope is domain plus subdomains, future main-frame/subframe navigation only. Old endpoints lack the `browser-website-policy` capability and cannot be targeted through the new control.

The signed `browser.update` envelope may carry `protectionReports`, a UTF-8 JSON array of at most 32 reports: browser, pseudonymous profile, version, state, observedAt. JSON dates use Foundation's default seconds-since-2001 encoding inside this string; envelope UTC dates remain unchanged. This field is independent of tab-sharing consent. Profile reports age out of current status after 180 seconds or immediately when the device is offline. No blocked-request data is transmitted.

Native messages add `policy.ack` with policyVersion and policyState. The allowlisted host checks the browser's signed executable and extension identity, stamps receipt time locally and accepts acknowledgements only for the currently desired version. `configuration.query` returns the root-persisted websitePolicy even when tab sharing is disabled. Browser dynamic-rule readback precedes success acknowledgement; this is not tamper-proof attestation.

Stage 00 defines protocol `1.0`. Additive optional fields require a minor-version review. Removing or changing field semantics requires a new major version and mixed-version tests. Capability negotiation, not platform guessing, controls which typed messages are offered.
