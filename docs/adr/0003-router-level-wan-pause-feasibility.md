# ADR-0003: Router-level bounded WAN pause

- Status: Proposed for developer review
- Date: 2026-09-04
- Stage: STAGE-06C
- Version: `0.6.3-rc.1`

## Context

The family wants the Parent Controller to pause external Internet access for one selected child Mac for a bounded period without breaking the authenticated local connection between that Mac and the controller. The controller may use Wi-Fi or Ethernet, and the child may also change between physical interfaces.

The evaluated gateway is an ARRIS NVG448BQ running the supplied `9.3.0h11d25` firmware. Its serial number, gateway MAC address, household client addresses, host names, and access credentials are deliberately excluded from this public repository.

This is a network-enforcement boundary, not a monitoring feature. Network-content inspection is prohibited. The design may decide whether selected traffic is forwarded to the WAN; it must not inspect content, collect destinations, intercept TLS, or retain browsing traffic.

## Evidence

### Evaluated ARRIS gateway

- SaskTel's [ARRIS NVG448 parental-control instructions](https://support.sasktel.com/app/answers/detail/a_id/25314/~/setting-up-parental-controls-on-your-arris-nvg448-gateway) document interactive administration at the local gateway and configuration under **Firewall → Access Control**. They require the gateway's Device Access Code for protected changes.
- The same SaskTel page explicitly warns that Time of Day Profiles are not working properly, that the gateway uses UTC rather than Saskatchewan time, and that its workaround is not guaranteed. This makes the built-in timer unsuitable as the safety mechanism for an automatic product action.
- Frontier's [NVG448 Wi-Fi administration instructions](https://frontier.com/helpcenter/internet/change-wifi-network-name-and-password) likewise describe browser-based local administration using credentials printed on the router label; they do not describe an automation API.
- The available [ARRIS/FCC NVG448BQ user material](https://fccid.io/GZ5NVG4XXQ/User-Manual/Users-Manual-NVG448BQ-pdf-3005892) is a quick-start document, not an API or transactional firewall contract.

A credential-free read-only compatibility probe was also performed on the local management interface. It confirmed the model/firmware page, a site-map entry for Access Control, and a password form posting to a CGI login handler. There is no documented least-privilege automation API, scoped token, lease resource, or transactional expiry mechanism. No credential was entered, no cookie or token was acquired, no form was submitted, and no router state was changed.

Absence of a documented API is not proof that private CGI calls are impossible. It is proof that this project cannot depend on them safely. Reverse-engineering or scraping that interface would require a broad Device Access Code, couple behavior to undocumented HTML/CGI details, and still not supply a dependable router-owned expiry.

### Conditional alternative platforms

- MikroTik documents a [RouterOS REST API](https://help.mikrotik.com/docs/spaces/ROS/pages/47579162/REST%2BAPI), [forward-chain firewall filters](https://help.mikrotik.com/docs/spaces/ROS/pages/48660574/Filter), and a router-local [Scheduler](https://help.mikrotik.com/docs/spaces/ROS/pages/40992881/Scheduler). Together these are sufficient primitives for a future, narrowly authorized physical feasibility test; they do not prove this product's adapter or recovery behavior.
- OpenWrt documents ACL-governed [uBus JSON-RPC over HTTP](https://openwrt.org/docs/techref/ubus) and the [uBus service model](https://openwrt.org/docs/guide-developer/ubus). A future adapter could be considered only on supported hardware with a narrowly scoped ACL and a router-local expiry mechanism.

These are compatibility candidates, not purchase recommendations or implemented integrations.

## Required enforcement contract

A future router adapter is acceptable only if every item below is demonstrated on non-primary test equipment.

1. **Selected endpoint only.** Resolve the paired endpoint to explicitly approved router client identities. Map every in-scope Wi-Fi and Ethernet interface; do not silently treat a randomized/private Wi-Fi address as stable identity.
2. **WAN-only placement.** Apply deny rules only to routed forwarding from the selected child to external networks. Preserve the authenticated local Parent Controller connection. Do not block same-LAN traffic to the Parent Controller, router administration, or the recovery workstation.
3. **Protocol parity.** Enforce both IPv4 and IPv6, including delegated/global IPv6 prefixes. A one-family rule is a bypass and must fail validation.
4. **Hard expiry on the router.** Create a maximum-eight-hour lease with a unique idempotency identifier and an absolute expiry interpreted by the router. The router itself must remove or disable the deny rule even if the controller quits, sleeps, changes interface, or loses power.
5. **Fail-safe recovery.** If creation, verification, renewal, or removal has an ambiguous result, the UI reports `Unknown—verify router`; it never claims `Paused`. A local adult must have a documented, independent removal path.
6. **Essential services.** Preserve DHCP and local address assignment. Preserve local DNS only where it is needed for the authenticated controller path or recovery; external DNS alone must not become an Internet bypass. Preserve time synchronization needed for correct hard expiry without granting general WAN access. The exact allowlist must be proven on the target router rather than inferred from port names.
7. **Least privilege.** Use a dedicated operation-scoped router principal that can manage only tagged pause leases for approved child identities. Store the credential in macOS Keychain. Never store the main Device Access Code, Wi-Fi password, or a general administrator credential in SQLite, preferences, logs, diagnostics, or source.
8. **Bounded state and audit.** Persist only adapter type, pseudonymous router-client mapping, lease identifier, requested/verified timestamps, expiry, and result. Do not store packet data, DNS history, URL/domain history, or unrelated client inventory. Audit create, verify, expire, cancel, recovery, and ambiguous outcomes without secrets.
9. **Visible adult action.** Require a selected child, duration, confirmation, and display of the affected interfaces. Show the verified router result and absolute recovery time. A capability appears only after a live compatibility check.
10. **No arbitrary administration.** The adapter exposes typed create, inspect, and cancel lease operations. It cannot accept arbitrary firewall fields, paths, scripts, shell commands, or raw router requests.

## Compatibility decision

| Path | Automation decision | Reason | What would be required next |
| --- | --- | --- | --- |
| Existing ARRIS NVG448BQ | **No-go; manual-only** | No documented least-privilege API or hard-expiring lease; official warning says time profiles are unreliable | Optional manual operator test only, with recovery access and controller excluded |
| HTML/CGI automation on ARRIS | **Rejected** | Broad credential, undocumented contract, brittle parsing, uncertain rollback, and no trustworthy expiry | None; do not implement |
| MikroTik RouterOS downstream router | **Conditional candidate** | Documented REST, forwarding filters, and router scheduler provide necessary primitives | Separate hardware/configuration approval and full physical safety matrix |
| Supported OpenWrt downstream router | **Conditional candidate** | Documented ACL-scoped local RPC and programmable firewall/service model | Separate hardware/configuration approval and router-local lease implementation |
| Endpoint Network Extension | Outside Stage 06C | Depends on Apple entitlement and endpoint integrity rather than router ownership | Keep separate from the router track |
| MDM or managed identity | Outside Stage 06C | Different trust, recovery, and distribution boundaries | Separately authorized stages only |

## Safe manual evaluation on the current gateway

This checklist does not create an automated capability and must not be represented as one.

1. Maintain a wired or otherwise independent adult recovery path to the gateway. Confirm the Parent Controller and recovery device are not selected.
2. Record only a synthetic label for the test client; do not place gateway credentials or household identifiers in project logs or screenshots.
3. In the gateway's documented **Firewall → Access Control** UI, create a short test profile using the ISP's documented UTC-offset caveat. Assign it only to the disposable test client.
4. Verify external IPv4 and IPv6 separately, local controller connectivity, DHCP renewal, local name resolution, and manual removal.
5. Remove the restriction in the same session. Reboot the test client and gateway only if the adult recovery route remains proven.
6. Treat any failure to remove, any parent-LAN interruption, or any mismatch between the displayed schedule and actual enforcement as a failed evaluation.

Because the vendor warns that timing is unreliable, the built-in profile is not accepted as an unattended hard-expiry mechanism even if one manual test happens to pass.

## Alternatives and deployment shape

If stronger router control remains desired, the least disruptive path is a separately administered downstream router that owns the child network while the ARRIS remains the upstream Internet gateway. The Parent Controller and its recovery workstation need a deliberate management/LAN path that is never included in child WAN-deny rules. This topology still requires validation against double NAT, IPv6 prefix delegation, roaming, private addresses, DNS behavior, time synchronization, router reboot, controller loss, lease expiry, and adult rollback.

A future adapter should start as a standalone, synthetic-lab compatibility harness. Product UI integration and an installer follow only after the physical matrix proves hard expiry and local-controller preservation. No household router credential or real client inventory may enter CI or the repository.

## Decision

Do not integrate the current ARRIS gateway and do not produce an executable or installer for Stage 06C. The sole release-candidate artifact is this source dossier. Preserve the existing approved Stage 06A installer as the latest installable application package.

A future router adapter is separately gated and may target a documented API only after the developer names the test hardware, authorizes configuration changes, confirms an independent adult recovery path, and accepts the privacy fields and maximum pause duration.

## Consequences

- The Parent Controller will not show a router WAN-pause capability for the evaluated gateway.
- Users may manually use the gateway's supported Access Control UI, with the ISP's reliability warning and without a product guarantee.
- The project does not take custody of the gateway's broad Device Access Code.
- A documented-API router can be evaluated later without changing the local-first authority or inspecting network content.
- Stage 07 remains unstarted until this feasibility result is reviewed and approved.

## Rollback

No router, application, account, or installed state changed. Repository rollback is a normal Git revert of this documentation stage. Read-only probe files are temporary project-work evidence and are deleted after the review is recorded.
