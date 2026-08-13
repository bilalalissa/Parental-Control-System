# STAGE-01 — Apple-silicon Parent Controller shell

- Version: `0.1.0-rc.1`
- Branch: `stage/01-controller-shell`
- Status: `IMPLEMENTING`
- Platform: Apple-silicon macOS 14 or newer

## Objective and included scope

Deliver a native SwiftUI controller shell with local SQLite migrations, synthetic device data, dashboard, device details, schedule editor, chat and audit shells, settings, storage/retention controls, accessibility identifiers, a supported startup-at-login option, and an original controller icon.

## Exclusions

No LAN hub, pairing, endpoint connection, real chat transport, application or browser monitoring, command execution, policy signing/enforcement, privileged helper, relay/cloud service, MDM, or Stage 02+ behavior is included. All displayed family/device content is synthetic.

## Acceptance and resource plan

- Validate migrations and deterministic schedule rules with unit tests.
- Exercise synthetic macOS, Windows, and standard-iPad capability combinations without overstating iPadOS behavior.
- Build and launch one arm64 Release app with one project-owned Derived Data path and no simulator.
- Verify the startup-at-login control reports Service Management errors honestly.
- Produce one ad-hoc-signed DMG, checksum it, smoke-test its contents, and retain only that developer-test candidate plus its checksum.
- Measure bundle size, idle memory, and best-available idle CPU evidence against the controller targets.
- Remove project-owned build, staging, loose-bundle, test, screenshot, and temporary icon output before reporting.

Exact commands, results, artifact checksum, resource evidence, and developer checklist will replace this implementation note when the stage reaches its test gate.
