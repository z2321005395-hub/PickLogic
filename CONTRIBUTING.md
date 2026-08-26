# Contributing

PickLogic is pre-alpha. Contributions must preserve local-first behavior, shared-core architecture, and safety boundaries.

## Before coding

1. Read `AGENTS.md`, `docs/PROJECT_SNAPSHOT.md`, the nearest local `AGENTS.md`, and `TASK_STATE.md`.
2. Confirm the issue is real and scoped to the current milestone.
3. For shared contracts, propose an ADR and compatibility note before implementation.
4. For any dependency, update `DEPENDENCY_BUDGET.md` first.

## Changes

- Keep Standard and Pro in one desktop implementation.
- Use synthetic data in tests and examples.
- Never add credentials, personal paths, private file metadata, telemetry, cloud uploads, or destructive shortcuts.
- Format code, inspect the diff, and run the smallest relevant test set.
- Commit messages should explain a real change; do not split work to manufacture activity.

## Pull requests

Describe changed files, tests, install-size impact, privacy/safety impact, compatibility, blockers, and next action. A passing build alone does not prove a change is safe or complete.

By contributing, you agree that your contribution may be distributed under the repository's BSD 3-Clause License. Do not submit code, assets, or binaries without clear provenance and compatible redistribution rights.
