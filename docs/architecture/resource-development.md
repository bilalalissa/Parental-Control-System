# Resource-safe development

## Guardrails

- Keep at least 5 GiB free on the repository volume.
- Use one checkout, one active stage branch, one platform build directory, and at most one simulator.
- Default to one or two workers and run static/contract tests before native or UI work.
- Do not create VMs, containers, simulator runtimes, duplicate clones, or worktrees without explicit approval.
- Retain only the current developer-test artifact. Do not commit build output, installers, caches, logs, diagnostics, or real data.

## Stage 00 commands

No dependency installation or native build is needed.

```sh
df -h .
du -sh .
npm test
npm run cleanup:list
```

`npm test` uses Node's built-in test runner with concurrency capped at two. The workflow runs the same platform-neutral contracts on Ubuntu and exercises the PowerShell cleanup path on Windows. If local capacity falls near the 5 GiB floor, skip any future native build and use the already configured platform CI job; report CI evidence separately from local and physical-device evidence.

## Safe cleanup

`tools/cleanup.sh` and `tools/cleanup.ps1` are dry-run/list operations unless passed `--apply` or `-Apply`. They recognize only repository-owned generated output:

- root `.build`, `build`, `dist`, `coverage`, and `TestResults`;
- repository `.artifacts/derived-data`, `test-results`, `tmp`, `package-staging`, and `diagnostics`;
- nested `node_modules`, `bin`, `obj`, and `publish` directories.

They intentionally preserve `.artifacts/release-candidate`, source files, Git data, global Xcode/SwiftPM/NuGet/npm caches, simulators, other repositories, and anything outside the resolved repository root. Both scripts require repository marker files; test-root overrides require a dedicated synthetic marker.

Review before deleting:

```sh
npm run cleanup:list
npm run cleanup:apply
```

```powershell
.\tools\cleanup.ps1
.\tools\cleanup.ps1 -Apply
```

Never substitute `git clean -fdx` or an unscoped recursive deletion.

## CI controls

The Stage 00 workflow uses read-only permissions, shallow checkout, cancellation of superseded branch runs, no dependency cache or build-product cache, one relevant OS per contract path, and seven-day retention for failure-only test evidence. Later platform workflows must remain path/stage scoped and produce one release candidate per affected platform.
