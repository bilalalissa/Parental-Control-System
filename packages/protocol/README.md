# Canonical protocol contract

[`message.schema.json`](message.schema.json) is the single canonical wire-envelope definition. Implementations may generate platform types from it in temporary or platform-required generated locations; copied schema variants are not authoritative.

## Envelope rules

Every message carries a UUID message ID, protocol version, device ID, UTC timestamp, optional expiry, monotonic per-sender sequence, allowlisted type, bounded object payload, and authentication metadata. Production messages use TLS 1.3 where supported and an Ed25519 signature over a documented canonical encoding introduced before networking is implemented.

Messages fail closed when they are malformed, expired, replayed, signed by an unknown/revoked key, out of the negotiated protocol range, or unsupported by the destination. Stage 04 adds allowlisted app-activity delta/configuration, chat, and more-time request messages. Stage 05 adds allowlisted browser-tab update/configuration messages containing only browser, pseudonymous profile, title, query/fragment-free origin, active state, and observation time. Chat receipts may use `queued`, `sent`, `delivered`, `read`, or `failed`; other command receipts use `accepted`, `started`, `succeeded`, `failed`, `expired`, `unsupported`, or `denied`. Receipt payloads identify the original message without copying sensitive content.

The protocol deliberately has no arbitrary shell, script, file-browsing, or unrestricted process command.

## Versioning

Stage 00 defines protocol `1.0`. Additive optional fields require a minor-version review. Removing or changing field semantics requires a new major version and mixed-version tests. Capability negotiation, not platform guessing, controls which typed messages are offered.
