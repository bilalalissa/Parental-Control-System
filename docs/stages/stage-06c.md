# STAGE-06C — Router-level per-device WAN pause feasibility

- Version: `0.6.3-rc.1`
- Branch: `stage/06c-router-wan-pause`
- Status: `MERGED`
- Authorized: `2026-09-04` via `AUTHORIZE ROADMAP AMENDMENT: INSERT STAGE-06C ROUTER-LEVEL WAN PAUSE BEFORE STAGE-07` and `PROCEED: STAGE-06C`
- Evidence type: official-source review plus credential-free, read-only local compatibility probe; no router mutation
- Canonical decision: [ADR-0003](../adr/0003-router-level-wan-pause-feasibility.md)

## Objective

Determine whether the family's current router can pause external Internet access for one selected child endpoint for a bounded period while preserving the authenticated local Parent Controller path and automatic recovery.

## Included scope

- ARRIS NVG448BQ firmware compatibility based on official ISP/manufacturer material and a credential-free local probe.
- Separation of local LAN control traffic from forwarded WAN traffic.
- Wi-Fi/Ethernet identity mapping and IPv4/IPv6 bypass analysis.
- Router-owned hard expiry, idempotency, failure reporting, adult recovery, and essential-service requirements.
- A safe manual evaluation checklist for the current gateway.
- Conditional documented-API alternatives for a later, separately approved physical lab.
- Focused architecture, capability, privacy, threat-model, and repository-test updates.

## Excluded scope

- Entering or storing the Device Access Code, Wi-Fi secret, router administrator password, API token, or household client identifiers.
- Logging into the router, submitting a form, changing Access Control, firewall, DHCP, DNS, IPv6, time, or any other router state.
- Reverse-engineering or automating undocumented CGI/HTML endpoints.
- Network-content inspection, DNS history, URL/domain logging, TLS interception, packet capture, or unrelated device inventory.
- A Parent Controller feature, router adapter, endpoint change, installer, extension update, external service, or new dependency.
- Purchasing/recommending hardware, configuring a downstream router, Network Extension work, MDM work, Stage 07, or any later feature.

## Assumptions

- The Parent Controller remains the local policy authority and may use Wi-Fi or Ethernet.
- The child may also have multiple interfaces or a private/randomized Wi-Fi address.
- An unattended pause must recover even if the controller exits, sleeps, or loses power.
- The adult retains lawful router administration and an independent recovery connection.
- Official vendor/ISP documentation is authoritative; a private endpoint observed in HTML is not a supported API.

## Acceptance criteria

1. Produce an evidence-backed go/no-go decision for the exact gateway without submitting credentials or changing state.
2. Define a WAN-only adapter contract that preserves authenticated LAN control and covers IPv4, IPv6, Wi-Fi, and Ethernet.
3. Require router-owned hard expiry and explicit fail-safe recovery, not a controller-only countdown.
4. Define essential-service, least-privilege, audit, privacy, idempotency, and ambiguous-result behavior.
5. Document an honest manual path and conditional alternatives without claiming implementation or recommending procurement.
6. Update the roadmap and canonical security/privacy/capability documents.
7. Pass dependency-free repository tests with no product runtime or installed-device change.
8. Provide one reviewable source dossier with a SHA-256 checksum.

## Resource limits and execution plan

- Documentation and Node repository checks only; no Swift/Xcode build, simulator, VM, container, daemon, browser driver, or router login.
- At most two test workers.
- No dependency installation or generated package output.
- Preserve the approved Stage 06A application package and Stage 05 extension ZIP; neither is a Stage 06C artifact.
- Cleanup is limited to the explicitly named temporary probe files and repository-owned paths reported by `npm run cleanup:list`.
- Existing installed Parent Controller/hub processes are developer-owned and remain untouched.

## Findings

The developer approved this dossier with `APPROVED: STAGE-06C 0.6.3-rc.1` and separately authorized its merge with `MERGE` on 2026-09-04. The approval accepts the compatibility finding; it does not claim router enforcement or authorize unsupported ARRIS automation.

The current ARRIS firmware exposes documented interactive Access Control but has no documented least-privilege automation API. The protected page is backed by an HTML/CGI login flow. SaskTel also warns that Time of Day Profiles are not working properly, use UTC rather than Saskatchewan time, and have a workaround that is not guaranteed.

These facts make automatic integration a no-go. Scraping the page would require the gateway's broad Device Access Code, bind the product to undocumented behavior, and provide neither transactional verification nor trustworthy router-owned expiry. No executable or installer can honestly improve that constraint.

Documented REST/RPC, routed-forwarding filters, and router-local scheduling on platforms such as MikroTik RouterOS or supported OpenWrt hardware make a later adapter feasible in principle. That remains unverified until a separately approved physical lab proves the complete safety matrix.

## Decision summary

- **Current ARRIS gateway:** no-go for automation; manual-only.
- **Private CGI/HTML automation:** prohibited.
- **Product capability:** remain unavailable and explain why; do not show a success state or Pause button.
- **Future adapter:** conditional only for a documented, least-privilege local API with WAN-only IPv4/IPv6 filters and router-owned expiry.
- **Installer:** none. Stage 06C changes no executable or installed component.

## Required physical matrix for any later adapter

| Case | Required result |
| --- | --- |
| Child on approved Wi-Fi identity | External IPv4 and IPv6 denied; parent LAN remains reachable |
| Child on approved Ethernet identity | Same result; mapping is explicit rather than inferred |
| Child changes interface | Only pre-approved mappings are affected; UI reports unmapped interface honestly |
| Private/random Wi-Fi address changes | No false claim; adult must re-identify and approve the new mapping |
| Parent uses Wi-Fi | Parent-to-child authenticated LAN path and gateway recovery remain reachable |
| Parent uses Ethernet | Same preservation requirement |
| Controller quits/sleeps/loses power | Router removes the pause at absolute expiry |
| Router reboots during pause | Lease either resumes safely or fails open with an audited explicit result; never remains indefinite |
| IPv4 disabled/enabled | IPv6 cannot bypass restriction |
| IPv6 disabled/enabled | IPv4 cannot bypass restriction |
| DHCP renewal | Address assignment remains available and identity does not drift silently |
| DNS and time behavior | Required recovery/time services work without granting general WAN access |
| Cancel repeated or retried | Idempotent cancellation removes only the tagged lease |
| Ambiguous API response | UI reports unknown and directs the adult to router verification |
| Credential revoked | Capability disables; existing lease still expires on-router |
| Adult recovery | Independent local administrator removes the rule without the Parent Controller |

## Developer review checklist

1. Confirm no household serial number, router MAC, credential, client address, or host name appears in the repository.
2. Confirm no router login, authenticated request, form submission, or configuration mutation occurred.
3. Confirm the current gateway is labeled manual-only rather than supported.
4. Confirm hard expiry is owned by the router and capped at eight hours in the future contract.
5. Confirm the Parent Controller LAN path is excluded from child WAN rules on both controller interfaces.
6. Confirm both IP families and every approved child interface must pass physical tests.
7. Confirm the adapter will collect no content, packets, DNS history, URLs, or unrelated client inventory.
8. Confirm any hardware/configuration test requires a new explicit authorization and independent adult recovery.

## Rollback

No device or router rollback is required because nothing was installed or configured. Repository rollback is a normal Git revert. The approved Stage 06A installer remains the latest application artifact.

## Security and privacy

The proposed adapter would add a privileged local router trust boundary. The future credential must be least-privilege and Keychain-only, and the API must expose typed lease operations rather than general router administration. Only pseudonymous mapping and bounded lease/audit state may be retained. Packet data, destinations, DNS history, credentials, and household inventory remain excluded.

The read-only probe intentionally stopped at the credential form. Its temporary response files are not stage artifacts and are deleted before handoff.

## Validation commands

```sh
npm test
git diff --check
npm run cleanup:list
```

Actual WAN restriction, parent-LAN preservation, IPv4/IPv6 parity, interface roaming, router reboot, hard expiry, and adult recovery remain unverified until a separately approved physical router-adapter stage.

## Candidate evidence

- `npm test`: 54 passed, 0 failed, 1 Windows-only cleanup test skipped on macOS.
- Focused Stage 06C tests: 4 passed, 0 failed.
- `git diff --check`: passed.
- Stage tracker and repository JSON parsing: passed.
- Local Markdown link validation: included in the repository test and passed.
- Scoped household-identifier and private-key/token scan of changed source documents: no disclosed household identifier or secret.
- Dossier artifact: `docs/adr/0003-router-level-wan-pause-feasibility.md`.
- Dossier SHA-256: `118af1a1d731e297d6eaff44e87879edb4657441160c9081cdbecede567c5b3c`.
- Signing and entitlements: not applicable to a Markdown feasibility artifact.

## Resource evidence

- Free disk before work: 14 GiB on the repository volume.
- Repository size before work: 27 MiB; retained project-owned artifacts: 15 MiB.
- Peak temporary build size: 0 bytes; no native build is in scope.
- Free disk after validation and cleanup: 14 GiB.
- Cleanup result: all explicitly named read-only probe responses deleted; `npm run cleanup:list` found no repository-owned generated output.
- Retained product artifacts: the approved Stage 06A package and Stage 05 browser-extension ZIP remain because Stage 06C does not replace either installable product.
- Project processes started by this stage: none.
- Existing installed Parent Controller/hub processes: developer-owned and deliberately untouched.
- Simulator/emulator/VM/container state: not used.
- Resource-budget exception: none; the 5 GiB floor remained satisfied.
