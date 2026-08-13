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

## Open-source reuse policy

- Principle: **Reuse infrastructure; own the product logic.** Do not rebuild a non-product-specific subsystem before checking for a mature, actively maintained, license-compatible, size-appropriate implementation.
- Fixed priority: (1) Windows / Android / Dart / Flutter platform APIs, (2) mature package dependency, (3) permissively licensed reusable component, (4) a small independent implementation.
- Prefer MIT, BSD-2-Clause, BSD-3-Clause, and Apache-2.0 when practical.
- Pause for a compatibility and redistribution audit before introducing GPL, AGPL, LGPL, MPL, another copyleft license, or any dependency with special redistribution obligations. Agents may not approve these unilaterally.
- Never import or copy code without an explicit license, unknown-provenance snippets, unverified Stack Overflow or blog code, binary blobs without provenance, or a clearly oversized dependency for a simple feature.
- Every proposed third-party dependency must be recorded in `DEPENDENCIES.md` with its name, upstream URL, exact version or commit, license and copyright notice, dependency versus copied-source status, purpose, supported platforms, approximate binary-size impact, reason not to implement locally, and any lighter alternative.
- Keep `THIRD_PARTY_NOTICES.md`, `DEPENDENCIES.md`, `DEPENDENCY_BUDGET.md`, and the dependency/license CI audit aligned. Release bundles must carry all required notices.
- Reuse is normally preferred for PDF rendering, archives, SQLite, cryptographic hashing, EXIF/image metadata, perceptual hashing, file pickers and platform filesystem bridges, MediaStore/SAF, Windows shell integration, DOI clients, BibTeX/RIS parsing, OCR provider boundaries, Markdown/code preview, and Trash/Recycle Bin integration.
- PickLogic owns its virtual classification and organization workflow, Insight, Screenshot Manager, Storage Insight, Research Workspace, OperationPlan/Preview/Undo safety model, Data Lineage, and other product-level behavior.
- Development speed alone never justifies a dependency; license, provenance, maintenance, necessity, and measured size must all be reasonable.

## Quality and delivery

- Format and inspect the diff after changes. Run the smallest relevant tests first; run all tests only for integration/release gates.
- A task is complete only when requested artifacts build or run and verification evidence is recorded.
- Update `TASK_STATE.md` after each completed stage with goal, files, commands, results, blockers, and next action.
- Keep Git history truthful and scoped. Do not fabricate issues, users, dates, downloads, stars, or activity.
- Do not create or publish a remote, select a final license/copyright owner, make the repository public, scan real directories, mutate real files, or publish media without the user's required confirmation.

## GitHub development history

- The Private repository `z2321005395-hub/PickLogic` is the canonical, continuous, auditable engineering history. Preserve this same history if the repository is later made Public; do not replace it with a clean one-commit import.
- The maintainer grants ongoing authorization to commit, push feature branches or `develop`, create/update genuine PRs, run Actions, and merge completed green internal PRs into `develop`, provided privacy and secret checks are clean. Private-to-Public conversion, formal GitHub Releases, public artifact publication, final license/copyright changes, important remote-branch deletion, force pushes, and published-history rewrites still require explicit confirmation.
- One coherent engineering change equals one meaningful commit. Use the real current date and configured author. Never manufacture activity, contributors, feedback, bugs, issues, PRs, dates, downloads, or stars.
- Use real feature branches and PRs for meaningful multi-track work. Prefer normal merge/no-ff history that preserves useful commits; do not squash an entire feature branch by default. Never force push `main` or `develop`.
- A medium task normally needs 1–4 checkpoint commits: a usable page, completed interaction, platform integration, real fix, measured optimization, dependency change, or user-visible capability. Do not create trivial commits for activity.
- Git history records engineering work. `CHANGELOG.md` records only user-visible changes. Keep `docs/development-log.md` concise: only a few milestone bullets per important development day.
- Create Issues and PRs only for genuine requirements, bugs, regressions, architecture problems, device findings, or user feedback. Redact private names, paths, screenshots, media, research data, and device identifiers; use aggregate evidence.
- At the end of a substantial task: inspect status/diff, run privacy and secret checks, commit coherent changes, push feature branches, create/update real PRs, run the necessary CI once, merge completed green PRs into `develop`, push `develop`, and verify local/remote synchronization. Routine Private pushes do not need repeated approval.
- Keep history maintenance lightweight: targeted tests before commits, one full CI after integration, and no repeated repository-wide, license, or long-report work unless the change requires it.

## Token-efficient reporting

- Success logs contain summaries; inspect detailed logs only on failure.
- Final track reports contain only: changed files, tests, commit, blockers, next action.
- Keep `docs/PROJECT_SNAPSHOT.md` under 150 lines and normal documentation under 200 lines.
