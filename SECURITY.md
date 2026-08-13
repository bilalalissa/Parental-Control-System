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
