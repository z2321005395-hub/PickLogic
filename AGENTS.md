# PickLogic Agent Rules

Scope: the whole repository. A nearer `AGENTS.md` may add narrower rules but cannot weaken these rules.

## Read order

1. Read this file, `TASK_STATE.md`, and `docs/PROJECT_SNAPSHOT.md`.
2. Read the nearest local `AGENTS.md` and only the files relevant to the task.
3. Use `docs/REPO_MAP.md`, symbol search, targeted reads, module tests, and `git diff`; avoid rescanning the repository.

## Product and architecture

- Product: PickLogic / 拾理. Context explanation: 知件 / Insight.
- Motto: Small. Local. Useful.
- One monorepo, one shared core, one desktop implementation with Standard and Pro entrypoints.
- Flutter stable + Dart are primary. Native code is limited to Windows and Android bridges.
- Do not add cloud backends, accounts, telemetry, ads, training frameworks, embedded web UIs, Python/Node runtimes, or large models.
- Interfaces and models are governed by `docs/DATA_MODEL.md`. Contract changes require an ADR, compatibility note, documentation update, and Lead review before code changes.

## Safety and privacy

- Debug builds must show and enforce `Developer Safe Mode: ON`.
- Real user data is read-only unless the user explicitly authorizes an operation on a dedicated test directory.
- File mutations must follow `Plan -> Preview -> Confirm -> Execute -> Undo/Trash` through `FileOperator`; UI code never calls raw move, rename, or delete APIs.
- `PROTECTED` and `UNKNOWN` have no direct-delete path.
- Never commit private paths, filenames, document titles, device serials, credentials, tokens, logs, or screenshots containing personal data.
- Tests and CI use only `test_fixtures/` or temporary synthetic data.
- Never bypass Windows security, Android scoped storage, UAC, RSA prompts, MFA, CAPTCHA, or store/platform controls.

## Dependencies and size

- Before adding a dependency, update `DEPENDENCY_BUDGET.md` with purpose, license, estimated install-size impact, and lighter alternatives.
- Prefer SDK libraries and small audited packages. Optional OCR, translation, PDF extras, or AI engines must remain replaceable and disabled by default.
- Base targets: Android <= 40 MB, Windows Standard <= 80 MB, Windows Pro <= 130 MB. Report real artifact sizes.

## Quality and delivery

- Format and inspect the diff after changes. Run the smallest relevant tests first; run all tests only for integration/release gates.
- A task is complete only when requested artifacts build or run and verification evidence is recorded.
- Update `TASK_STATE.md` after each completed stage with goal, files, commands, results, blockers, and next action.
- Keep Git history truthful and scoped. Do not fabricate issues, users, dates, downloads, stars, or activity.
- Do not create or publish a remote, select a final license/copyright owner, make the repository public, scan real directories, mutate real files, or publish media without the user's required confirmation.

## Token-efficient reporting

- Success logs contain summaries; inspect detailed logs only on failure.
- Final track reports contain only: changed files, tests, commit, blockers, next action.
- Keep `docs/PROJECT_SNAPSHOT.md` under 150 lines and normal documentation under 200 lines.
