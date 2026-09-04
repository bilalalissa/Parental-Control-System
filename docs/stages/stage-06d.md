# STAGE-06D — macOS application, website, and network enforcement

- Version: `0.6.4-rc.1`
- Branch: `stage/06d-macos-app-web-network-enforcement`
- Status: `BLOCKED`
- Authorized: `2026-09-04` via `AUTHORIZE ROADMAP AMENDMENT: INSERT STAGE-06D MACOS APP-WEB-NETWORK ENFORCEMENT BEFORE STAGE-07` and `PROCEED: STAGE-06D`
- Evidence type: official Apple capability review, local signing inspection, entitlement templates, and offline readiness tests
- Canonical decision: [ADR-0004](../adr/0004-macos-enforcement-extension-readiness.md)

## Objective

Implement supported macOS enforcement for adult-selected application identities and website domains plus a bounded external-Internet pause, while preserving authenticated local parent control, essential recovery traffic, hard expiry, user visibility, and privacy.

## Included scope

- Network Extension content-filter and Endpoint Security system-extension architecture.
- Explicit bundle identifiers and reviewable entitlement templates.
- A local readiness checker for Developer ID identities, explicit App IDs, managed entitlements, and Team ID alignment.
- Signed/versioned typed rule contracts, domain normalization, code-identity matching, bounded WAN-pause leases, fail-safe recovery, audit, upgrade, uninstall, and resource criteria.
- Official-source distribution requirements and a complete physical acceptance matrix.
- Canonical roadmap, architecture, capability, security, privacy, threat-model, and repository-test updates.

## Excluded scope

- Private Apple APIs, entitlement bypasses, ad-hoc claims, hidden installation, anti-administrator persistence, loginwindow replacement, or defeating an authorized administrator.
- Packet or page-content inspection, TLS interception, DNS/browsing history, arbitrary process/network control, screenshots, microphone/camera capture, or unrelated device inventory.
- ARRIS HTML/CGI automation, router credentials, MDM, Windows/iPad enforcement, relay/cloud service, or Stage 07 work.
- Submitting Apple capability requests or creating/storing developer certificates, profiles, private keys, or notarization credentials on the developer's behalf.

## Assumptions and resource limits

- The child uses a standard non-administrator account; an adult retains independent administrator recovery.
- System-extension and Network Extension approval is visible and follows Apple's supported workflow.
- All components use one Apple Team ID and matching Developer ID provisioning profiles.
- Until the gate passes, work is source-only: no Xcode build, simulator, VM, container, daemon, browser driver, or installer.
- Tests use at most two workers. The 5 GiB free-space floor remains mandatory.
- Cleanup covers only repository-owned temporary output; existing installed Parent Controller/hub processes remain developer-owned and untouched.

## Acceptance criteria

1. The readiness checker validates a Developer ID Application identity, all three explicit identifiers, required capabilities, and one Team ID without disclosing profile contents.
2. Source documents define exact app/domain/WAN semantics, safety allowlists, hard expiry, fail-open recovery, privacy, auditing, upgrade/uninstall, and physical tests.
3. The product does not expose an operational control or installer before Apple-managed entitlement and signed activation evidence exists.
4. After the gate passes, a signed/notarized installer must prove the complete physical matrix in ADR-0004 before developer approval.
5. Repository tests, entitlement lint, shell syntax, secret/profile scans, resource checks, cleanup, push, and one draft pull request complete.

## Finding and blocker

The development Mac has `0 valid identities found` for code signing, no matching provisioning profiles are present, and the installed Parent Controller is ad-hoc signed with no Team Identifier. Apple requires the restricted Endpoint Security capability and an approved Network Extension content-filter capability, matching Developer ID profiles, same-Team signing, user/system approval, and notarization for supported distribution.

Therefore this candidate is intentionally source-only and blocked. It does not produce a Stage 06D installer or claim enforcement. The approved Stage 06A package and Stage 05 browser-extension ZIP remain the latest installable artifacts and are not modified by this stage.

## Unblock procedure

The developer must obtain and install locally:

- one valid Developer ID Application identity and private key;
- a host profile for `com.bilalalissa.ParentalControlChild` with system-extension installation;
- a Network Extension profile for `com.bilalalissa.ParentalControlNetworkFilter` with content-filter provider system-extension authorization;
- an Apple-approved Endpoint Security profile for `com.bilalalissa.ParentalControlExecutionFilter`;
- all profiles under the same Team ID.

Do not commit or send credentials, certificates, private keys, provisioning profiles, or notarization secrets. Run the local command documented in ADR-0004 and report only its READY/BLOCKED summary. Work then resumes on this branch and pull request.

## Validation plan

```sh
plutil -lint agents/endpoint-macos/Enforcement/Entitlements/*.entitlements
bash -n script/check_stage06d_readiness.sh
script/check_stage06d_readiness.sh
node --test test/macos-enforcement-readiness.test.mjs test/repository.test.mjs
npm test
git diff --check
npm run cleanup:list
```

The no-argument readiness invocation must exit with blocked status and list missing prerequisites. Signed build, extension activation, and physical enforcement tests remain unavailable until the external Apple gate is satisfied.

## Candidate artifact and rollback

- Artifact: `docs/adr/0004-macos-enforcement-extension-readiness.md`
- Installer: none; no executable changed and an unentitled package would be unusable.
- Signing/entitlements: templates only; no local Developer ID identity or matching profile was available.
- Rollback: normal Git revert only. No Mac, router, browser, policy, or installed application state changed.

## Candidate evidence

- Entitlement templates: all three passed `plutil -lint`.
- Readiness-checker shell syntax: passed `bash -n`.
- Local readiness result: expected exit `2`; missing Developer ID Application identity plus host, Network Extension, and Endpoint Security profiles; no profile data copied.
- Focused Stage 06D tests: 5 passed, 0 failed.
- Complete `npm test`: 59 passed, 0 failed, 1 Windows-only cleanup test skipped on macOS.
- `git diff --check`: passed.
- Repository profile/certificate and credential-pattern scans: no committed signing material or detected secret.
- Cleanup dry run: no repository-owned generated output found.
- Dossier SHA-256: `bf5a2849e6f64cc9468ed7df06e22042728e7f926a385dc2fe35bc09fc758a0c`.

## Resource evidence

- Free disk before work: 14 GiB on the repository volume.
- Repository size before work: 27 MiB; retained project-owned artifacts: 15 MiB.
- Native build and generated installer size: 0 bytes.
- Project processes started by this stage: none.
- Existing installed Parent Controller/hub processes: developer-owned and deliberately untouched.
- Simulator/emulator/VM/container state: not used.
- Free disk after validation and cleanup: 14 GiB; repository size: 28 MiB; retained artifacts: 15 MiB.
- Cleanup result: no repository-owned generated output found.
- Resource-budget exception: none; the 5 GiB floor remained satisfied.
