# Contributing

Thank you for helping build a safer, transparent parental-control system.

## Before starting

1. Read [AGENTS.md](AGENTS.md), [CODEX_MASTER_PROMPT.md](CODEX_MASTER_PROMPT.md), and [the stage tracker](docs/stages/stage-status.json).
2. Work only on the approved stage. Do not introduce later-stage scaffolding or empty directory trees.
3. Create or continue `stage/<stage-id>-<short-name>`.
4. Use synthetic data and keep credentials, identifiers, family information, logs, and signing material out of Git.

## Development rules

- Preserve the local-first architecture and platform capability boundaries.
- Keep changes small, native where practical, and dependency-light.
- Default to one or two build workers; run light checks before native builds or UI tests.
- Keep at least 5 GiB free on the development volume.
- Use one checkout, one stage build directory, and one current test artifact.
- Run cleanup in list mode first. Delete only confirmed repository-owned output.
- Do not use broad cleanup such as `git clean -fdx`.
- Do not add hidden behavior, surveillance functionality, arbitrary command execution, private APIs, or security bypasses.

## Stage 00 checks

```sh
npm test
npm run cleanup:list
```

Windows contributors can run `powershell -File tools/cleanup.ps1` to list cleanup targets. Pass `-Apply` only after reviewing the list.

## Pull requests

Use the pull-request template. Include the approved stage, exact commands/results, resource evidence, privacy/security effects, limitations, and rollback instructions. One draft pull request remains open for the stage until developer approval. Do not merge, release, or begin the next stage without the commands defined in the master prompt.
