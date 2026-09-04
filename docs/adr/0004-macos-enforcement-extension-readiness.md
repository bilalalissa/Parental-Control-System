# ADR-0004 — macOS application, website, and network enforcement readiness

- Status: blocked pending Apple-managed capabilities and distribution signing
- Stage: STAGE-06D
- Version: `0.6.4-rc.1`
- Date: 2026-09-04

## Context

The Parent Controller needs three high-impact controls for a paired macOS child: deny selected application launches, deny selected website domains, and pause external Internet access for a bounded period. The authenticated local parent connection must remain available, restrictions must expire safely, and the implementation must not inspect content or pretend that an unsigned helper can enforce device-wide policy.

Apple's supported boundaries are system extensions. A content filter provider is a Network Extension system extension and requires the [`com.apple.developer.networking.networkextension`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension) entitlement. Application execution authorization uses Endpoint Security and requires Apple's restricted [`com.apple.developer.endpoint-security.client`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client) entitlement. Apple documents the embedding, activation, same-team signing, provisioning, and user/administrator approval model in [Installing system extensions and drivers](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers), [System Extensions](https://developer.apple.com/documentation/systemextensions), [TN3134](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment), and [Provisioning with managed capabilities](https://developer.apple.com/help/account/reference/provisioning-with-managed-capabilities/).

The development Mac currently has no valid code-signing identity, no matching Developer ID provisioning profiles, and the installed Parent Controller is ad-hoc signed with no Team Identifier. These are external Apple account/distribution prerequisites, not conditions source code can bypass.

## Decision

Adopt an entitlement-gated, three-component design, but do not build or distribute an installer until the readiness checker and signed physical activation tests pass.

1. The visible universal child application is the containing host. It embeds and requests activation of two visible system extensions, explains why they are required using `NSSystemExtensionUsageDescription`, and reports pending, approved, denied, replaced, or failed state honestly. It has no hidden installation path.
2. A Network Extension content filter enforces normalized domain deny rules and a bounded WAN-pause lease. It receives typed policy over authenticated local IPC and does not export, persist, or display flow contents.
3. An Endpoint Security client authorizes process execution for the configured standard child account. It evaluates stable code identity, not display name or mutable filesystem path.
4. The existing privileged service verifies the Parent Controller's signed, versioned policy before passing a minimal typed rule set to either extension. Extensions reject stale, malformed, replayed, unsigned, or over-broad policy.

The canonical bundle identifiers are:

| Component | Bundle identifier | Required entitlement |
| --- | --- | --- |
| Child host | `com.bilalalissa.ParentalControlChild` | `com.apple.developer.system-extension.install` |
| Network filter | `com.bilalalissa.ParentalControlNetworkFilter` | `com.apple.developer.networking.networkextension = content-filter-provider-systemextension` |
| Execution filter | `com.bilalalissa.ParentalControlExecutionFilter` | `com.apple.developer.endpoint-security.client` |

All three must use explicit App IDs, matching Developer ID profiles, and the same Team ID. The final application and installer must pass strict signature inspection, Gatekeeper assessment, notarization, stapling, package expansion, and fresh-machine upgrade/uninstall tests.

## Application deny semantics

- A deny rule is scoped to the explicitly selected standard child account and records the application's signing identifier, Team ID where available, designated requirement, and a bounded policy version. A hash may supplement identity for unsigned software but is never the sole long-term identity.
- Rules do not rely on display names or paths. Updates that change identity become an explicit `needs review` result rather than matching unrelated software.
- macOS security, login, update, accessibility, networking, recovery, the child host, both extensions, and the authenticated parent-control service form a non-editable safety allowlist.
- Authorization callbacks must meet Apple's timing constraints. Cache entries are bounded and invalidated on policy change. Timeout, extension failure, corrupt state, or uncertain identity fails open and generates a bounded audit event; it never leaves the Mac unbootable.
- The product does not claim it can defeat an authorized local administrator. The child must use a standard account.

## Website-domain deny semantics

- The parent enters a hostname or registrable domain. Input is lowercased, IDNA-normalized, stripped of a trailing dot, length-checked, and rejected if it contains a scheme, credentials, port, path, query, fragment, wildcard, IP literal, or malformed label.
- A rule for `example.com` covers that exact domain and its subdomains on IPv4 and IPv6. It does not perform substring matching.
- The filter may use the destination hostname supplied by the supported Network Extension flow metadata. It must not decrypt TLS, inspect page content, read forms/cookies/passwords, capture packets, or create browsing history. If a destination cannot be attributed safely to a domain, the domain rule does not invent a match.
- DNS-over-HTTPS, encrypted client protocols, QUIC, VPNs, proxies, virtual machines, and alternate interfaces are explicit physical-test cases. The UI must not claim complete domain enforcement if Apple APIs cannot identify or filter a path.

## Bounded WAN pause semantics

- A pause lease contains the child device identity, issuing policy version, start, absolute expiry, monotonic-duration ceiling, creator, and idempotency key. Duration is capped at eight hours.
- The extension evaluates expiry locally. Controller exit, sleep, network loss, or restart cannot extend the lease. Reboot recovery accepts only the last valid signed unexpired lease and reconciles wall-clock changes against the bounded duration.
- External forwarding is denied for IPv4 and IPv6 while authenticated local Parent Controller communication remains permitted on the selected parent Wi-Fi or Ethernet interface.
- DHCP and local address configuration remain available. DNS and time traffic are allowed only to the configured local/system resolvers and time services needed for recovery; no broad destination exception may become a WAN bypass. Captive-portal and unusual enterprise-network behavior must be reported honestly.
- Expiry, adult cancellation, invalid policy, component failure, and uninstall all fail open. A separately documented administrator recovery command disables the extension without the Parent Controller.

## Privacy and audit

The policy stores only the adult-entered domain rules, stable application identities selected by the adult, lease metadata, receipts, and bounded/redacted failure records in local protected storage. The network filter records no URLs, paths, queries, DNS history, packets, payloads, browsing history, or unrelated destinations. Endpoint Security events not needed for a configured rule are discarded in memory. Provisioning profiles, certificates, private keys, Team credentials, device addresses, and physical-test logs are never committed.

## Distribution readiness gate

The developer must complete these actions in the Apple Developer account and on the signing Mac:

1. Maintain an active Apple Developer Program team and install a valid `Developer ID Application` identity with its private key.
2. Register the three explicit App IDs above.
3. Enable System Extension installation for the host identifier.
4. Enable the Network Extension content-filter provider capability and create its Developer ID provisioning profile.
5. Request and receive Apple's Endpoint Security client entitlement, then create the execution extension's Developer ID provisioning profile.
6. Download/install the three matching profiles locally. Do not add or paste them, certificates, private keys, or notarization credentials into the repository, issue tracker, or chat.
7. Run:

   ```sh
   script/check_stage06d_readiness.sh \
     --host-profile /private/path/Host.provisionprofile \
     --network-profile /private/path/Network.provisionprofile \
     --execution-profile /private/path/Execution.provisionprofile
   ```

The checker decodes profiles only inside a private temporary directory, verifies explicit identifiers, capabilities, and Team ID alignment, and prints no decoded entitlement data. Passing it proves structural readiness only; it does not prove that activation or enforcement works.

## Required physical acceptance matrix

| Case | Required result |
| --- | --- |
| Fresh install and upgrade | Explicit activation UI; existing pairing/policy retained; no repeated prompts |
| System-extension approval denied | Clear unavailable state; no controls or success receipts |
| App deny for selected standard child | Launch denied; other users and safety allowlist unaffected |
| App update or signature change | Re-evaluate identity and show `needs review`; never path-match |
| Domain deny in supported browsers | Exact domain and subdomains denied on IPv4/IPv6; unrelated sites work |
| YouTube and browser games | Configured domain rule applies without reading content or history |
| Encrypted DNS, QUIC, VPN/proxy, VM | Result reported accurately; no unverified completeness claim |
| WAN pause on Wi-Fi and Ethernet | External IPv4/IPv6 unavailable; authenticated parent LAN remains reachable |
| Controller on Wi-Fi and Ethernet | Control path remains reachable in both configurations |
| Controller quits, sleeps, or loses power | Pause expires locally at the signed hard deadline |
| Child sleeps/reboots and clock changes | No indefinite extension; valid remaining lease reconciles safely |
| DHCP, local DNS, and time recovery | Essential recovery traffic works without general WAN bypass |
| Extension crash/corrupt policy | Fail open, bounded audit, visible unavailable state |
| Adult cancel, uninstall, and recovery | Immediate safe recovery and no orphaned filter |
| Resource soak | Event-driven operation, bounded memory/CPU/storage, no unbounded flow log |

## Current result

`STAGE-06D 0.6.4-rc.1` is **BLOCKED** at distribution readiness. Entitlement templates and an offline readiness checker are reviewable source artifacts. There is no Stage 06D installer and no application UI may expose these controls as operational. Producing an ad-hoc package would be misleading because the system extensions could not activate with the required capabilities.

Work resumes on the same stage branch and pull request after the developer confirms that the identity and profiles are installed locally. A later signed implementation candidate must still pass every physical case above before approval.

