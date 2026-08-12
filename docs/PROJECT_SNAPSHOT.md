# PickLogic Project Snapshot

- Product: PickLogic / 拾理; contextual explanation: 知件 / Insight.
- Motto: Small. Local. Useful.
- Status: Phase 0 code/test baseline complete; native builds remain locally gated; no public release.
- Targets: Windows Standard, Windows Pro, Android Mobile.
- Architecture: one Flutter/Dart workspace, shared pure-Dart core, narrow Windows/Android bridges.
- Desktop: one implementation with `main_standard.dart` and `main_pro.dart`; no duplicate app.
- Core safety: virtual classification does not move files; mutations require Plan -> Preview -> Confirm -> Execute -> Undo/Trash.
- Debug: visible and enforced `Developer Safe Mode: ON`.
- Real data: read-only by default; tests use synthetic fixtures only.
- Privacy: no account, ads, default telemetry, backend, or full-file upload.
- AI: optional provider; deterministic rules and metadata come first; app works with AI disabled.
- Size targets: Android 40 MB, Standard 80 MB, Pro 130 MB.
- Canonical contracts: `docs/DATA_MODEL.md`.
- Current state and next action: `TASK_STATE.md`.
- Repository map: `docs/REPO_MAP.md`.
- Dependency gate: `DEPENDENCY_BUDGET.md`.
- Public gate: final license/copyright, brand review, maintainer approval, clean privacy scan, green CI, installable artifacts, user trial.
- Known brand risk: exact-name npm/open-source projects and active PickLogic domains; display name unchanged pending maintainer decision.
- Local Android baseline: TTDT toolchain with JDK 17, Gradle 9.4.1, SDK/API 36, ADB, and existing AVDs.
- Reference phone verified by ADB: nubia NX736J, Android 15, API 35. Do not record its serial.
- Verification: full Dart/Flutter module suite, SQLite native asset test, dependency-license audit, and committed-source privacy scan pass locally.
- Local build gates: Windows Developer Mode is off; Visual Studio C++ Build Tools is absent.

## Ownership

- Track A: core models, file/search index, duplicate/classification/operations, Desktop Standard.
- Track B: literature, research, system insight, Desktop Pro composition.
- Track C: Mobile and Android bridge.
- Lead: contracts, dependency audit, review, CI, integration, release gates, user interaction; no duplicate feature implementation.

## First commands

```bat
tools\picklogic.cmd env
tools\picklogic.cmd pub-get
tools\picklogic.cmd quick
tools\picklogic.cmd full
```

Use target/module tests during development; full commands are integration/release gates.
