# STAGE-00 — Repository foundation and resource-safe architecture

- Version: `0.0.1-rc.1`
- Branch: `stage/00-repository-foundation`
- Status: `READY_FOR_DEVELOPER_TEST`

## Objective and scope

Create the smallest reviewable monorepo foundation: project/readme/license guidance, security and privacy posture, contribution and GitHub templates, architecture/threat/capability/resource documents, stage and ADR templates, canonical protocol/policy schemas, synthetic fixtures and contract tests, CI controls, safe ignore rules, dry-run-first cleanup tooling, and an original icon brief.

## Exclusions

No application runtime, privileged component, installer, enforcement, live networking, real pairing/signing key, user data, cloud/relay service, MDM implementation, or Stage 01+ scaffolding is included. Stage 00 produces source/contracts only and therefore has no installable release artifact.

## Acceptance and evidence plan

- Parse and validate canonical schemas plus valid/invalid protocol fixtures.
- Execute policy precedence/cross-midnight golden vectors.
- Prove cleanup defaults to listing, deletes only allowlisted project output, preserves the active candidate, and does not follow an unrelated symlink.
- Review iPadOS limitations, `.gitignore`, least-privilege CI/concurrency/retention, and repository layout.
- Run source-level checks locally without a simulator or native build, then clean temporary project-owned test output.

## Architecture decisions

- The controller remains the only policy authority; endpoints initiate authenticated LAN connections and cache the last valid signed policy.
- JSON Schema 2020-12 files are canonical. Platform types will be generated from them rather than maintained as copies.
- Protocol commands are typed and allowlisted. There is no arbitrary execution or unrestricted file operation.
- Policy evaluation is deterministic and uses IANA time-zone data plus monotonic active-use accounting.
- Standard iPadOS capabilities are represented as approximate or unavailable where public APIs do not provide desktop semantics.
- Stage 00 uses no runtime dependency, native build, simulator, container, VM, service, or installer.

## Automated results

| Command | Result |
| --- | --- |
| `npm test` | Passed locally: 24 checks passed; one Windows-only PowerShell execution check skipped on macOS. |
| `bash -n tools/cleanup.sh` | Passed locally. |
| `npm run cleanup:list` | Passed locally; no project-owned generated output remained. |
| Ruby YAML parse for the workflow and issue templates | Passed locally. |
| `git diff --check` | Passed locally. |
| Official action-tag verification with `git ls-remote` | Pinned hashes matched checkout `v4.2.2`, setup-node `v4.4.0`, and upload-artifact `v4.6.2`. |

Local tests ran with the available Node.js `v20.14.0`; the supported repository baseline and CI are Node.js 22. The Windows cleanup execution path is not locally proven because PowerShell is unavailable on this Mac; the focused `windows-2025` CI job runs that test. No physical device, native platform build, or simulator is relevant to this stage.

## Artifact, installation, and rollback

Stage 00 is source/contracts only. It has no application, installer, signing identity, entitlement, or binary release artifact, so a SHA-256 artifact checksum and installation/uninstallation steps are not applicable.

To review, check out this branch and run `npm test`. To roll back before merge, delete the branch; after merge, revert the focused Stage 00 commit. Cleanup tooling itself lists targets by default and requires explicit apply mode.

## Manual developer checklist

1. Confirm the README clearly labels the repository as non-installable Stage 00 work.
2. Review the architecture, threat model, privacy rules, and capability matrix—especially the iPadOS limitations.
3. Run `npm test` with Node.js 22 or review the draft pull-request checks.
4. Run `tools/cleanup.sh` or `tools/cleanup.ps1` without apply mode and confirm it lists only repository-owned generated paths.
5. Review both JSON Schemas and the synthetic policy vectors for compatibility and safe defaults.

## Known limitations and security/privacy notes

- This stage provides contracts, not cryptographic, transport, storage, or enforcement implementations.
- Schema validation is exercised by dependency-free contract checks; production cryptographic verification and protocol-specific payload schemas arrive with their approved implementation stages.
- The PowerShell cleanup behavior requires Windows CI/developer evidence.
- Fixtures contain synthetic identifiers and signatures only. No real family, device, network, chat, credential, or signing data is present.
- No prohibited surveillance, hidden behavior, privileged operation, arbitrary command execution, public relay, or telemetry was added.

## Resource evidence

- Free disk before: 13 GiB reported available on the repository volume.
- Repository/project-owned output before: 200 KiB repository; no build output.
- Peak temporary output: best estimate below 1 MiB for synthetic cleanup-test trees; all were removed.
- Free disk after cleanup: 12 GiB reported available (system-wide volume usage changed during the work; repository size remained sub-megabyte).
- Repository retained: 376 KiB including Git metadata (216 KiB worktree), for source, contracts, tests, and documentation.
- Project-owned generated paths retained: none.
- Project-started processes still running: none.
- Simulator/emulator state: not used; existing system CoreSimulator services were not started or modified by this stage.
- Single artifact retained for developer testing: none; Stage 00 has no installable artifact.
- Resource-budget exceptions: none; the 5 GiB floor was maintained.
