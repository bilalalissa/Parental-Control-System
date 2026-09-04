# Security Policy

## Supported versions

The project is pre-release. Only the latest stage branch and the default branch receive security fixes.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability or include family data, credentials, device identifiers, network addresses, chat content, screenshots, signing material, or pairing codes in a report.

Use GitHub's private vulnerability reporting feature for this repository. Include the affected commit, impact, prerequisites, a minimal reproduction using synthetic data, and any suggested mitigation. If private reporting is unavailable, open a public issue containing no exploit or sensitive detail and ask the maintainer for a private contact channel.

Maintainers should acknowledge a report within seven days, keep the reporter informed, and coordinate disclosure after a fix is available. This is a target, not a service-level guarantee.

## Security boundaries

- The software is for devices owned or lawfully administered by a parent or guardian.
- Endpoints must remain visible and disclose what is collected.
- Commands are typed and allowlisted; arbitrary shell or process execution is prohibited.
- Pairing is explicit, per-device, mutually authenticated, expiring, and replay protected.
- Secrets belong in Keychain, DPAPI, or Windows Credential Manager—not in source, logs, fixtures, or local SQLite.
- An authorized desktop administrator can remove the software. The project will not attempt to defeat one.
- Standard iPadOS limitations are security boundaries, not obstacles to bypass.

See the [threat model](docs/architecture/threat-model.md) and [privacy policy](PRIVACY.md) for the complete Stage 00 posture.

In Stage 02, initial pairing combines a pinned TLS 1.3 server identity with a rate-limited one-use code and a self-signed Ed25519 device announcement. Subsequent messages require the stored per-device public key, monotonic sequence, unique message ID, bounded timestamp/expiry, and allowlisted message type. GUI-to-hub IPC is loopback-only and HMAC-authenticated with an ephemeral session key delivered through a private child-process pipe.

Stage 05 app-activity, browser, chat, receipt, configuration, and more-time request messages remain typed and allowlisted. Offline envelopes have signed expiries and replay protection; controller and endpoint queues are bounded. Protected endpoint XPC authorizes activity updates only from the signed login helper, browser operations only from the exact signed/root-protected installed native host, and chat/time/read operations only from the signed visible child app. The native host independently accepts only the fixed extension origin launched by a valid signed Google Chrome, Microsoft Edge, or Arc process at its expected application path. Browser records are re-sanitized at every boundary. Logs and audit records omit chat text, tab titles, and origins.

Stage 06 nests an Ed25519-signed, strictly versioned per-device policy inside the existing authenticated TLS envelope. The endpoint verifies the paired controller key before installation and again when loading the root-protected cache after daemon restart; tampered or replayed policies fail closed. Immediate actions are typed, capability-checked, signed, short-lived, and audited. High-impact actions require parent confirmation and map only to standard macOS confirmation dialogs; force behavior and arbitrary execution are absent. Adult override uses a rotated salted verifier, constant-time comparison, three attempts per five minutes, and a five-minute lockout. Receipts acknowledge endpoint acceptance, not completion of a user-cancellable macOS action.

Stage 06A evaluates an optional third-party MDM boundary without creating an account, enrollment, credential, or configuration profile. Apple's documented Login Window allow/deny lists do not selectively cover ordinary local accounts and have no weekly schedule or automatic expiry. Broad local-login denial, scheduled MDM scripts, cloud-only recovery, and vendor API credentials that expose destructive commands are rejected. Stage 06B separately evaluates managed identity under its own threat model and explicit authorization.

Stage 06B evaluates that managed-identity proposal without creating external or installed state. Platform SSO can require live IdP authentication and exempt a local adult recovery account, but it cannot evaluate the locally signed weekly schedule while offline. Day-based offline grace can bypass a blocked time; disabling grace denies all offline login. A physical pilot remains separately gated and must use a synthetic managed child on non-primary hardware, an excluded local adult administrator, verified FileVault PRK/recoveryOS recovery, minimal attestation, and same-session rollback. Scheduled identity-account automation and product integration remain prohibited.

Stage 06C evaluates a local router enforcement boundary without authenticating to or changing the router. The current ARRIS NVG448BQ is manual-only because it has no documented least-privilege API or reliable hard-expiring lease. The project will not store its broad Device Access Code or automate its private CGI/HTML interface. Any later adapter requires a dedicated Keychain-held principal, typed tagged leases, WAN-forwarding-only IPv4/IPv6 rules, exact approved Wi-Fi/Ethernet identity mapping, router-owned maximum-eight-hour expiry, independent adult recovery, and explicit verification that the authenticated local controller path remains reachable. Network-content inspection and unrelated client inventory are prohibited.

Stage 06D selects Network Extension content filtering for domain/WAN enforcement and Endpoint Security authorization for application launches. Both are visible system extensions with Apple-controlled entitlements, explicit same-Team App IDs, matching Developer ID profiles, and supported activation. The current signing Mac does not meet that gate, so the stage exposes no operational control and produces no installer. Future rules remain typed and signed; app matching uses code identity, domain matching is normalized and content-free, WAN leases expire within eight hours, failures open safely, and an independent administrator recovery path is mandatory.
