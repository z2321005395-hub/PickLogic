# PickLogic Project Snapshot

- Product: PickLogic / 拾理; contextual explanation: 知件 / Insight.
- Motto: Small. Local. Useful.
- Status: the usability-recovery candidate is locally verified for all three targets; Private PR/CI integration is in progress; no public release.
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
- Current state and next action: `TASK_STATE.md`; installation limits: `docs/KNOWN_ISSUES.md`.
- Repository map: `docs/REPO_MAP.md`.
- Dependency gate: `DEPENDENCY_BUDGET.md`.
- Public gate: final license/copyright, brand review, maintainer approval, clean privacy scan, green CI, installable artifacts, user trial.
- Known brand risk: exact-name npm/open-source projects and active PickLogic domains; display name unchanged pending maintainer decision.
- Local Android baseline: TTDT toolchain with JDK 17, Gradle 9.4.1, SDK/API 36, ADB, and existing AVDs.
- Reference phone verified by ADB: nubia NX736J, Android 15, API 35, arm64-only. Do not record its serial.
- Verification: merged local suite and hosted Android/Windows builds pass; dependency-license and privacy scans report no findings.
- Local Windows gate: Build Tools 2022 17.14.37 and Developer Mode are verified; Standard/Pro build and launch from an ASCII-path worktree because Flutter/MSBuild corrupts the canonical Chinese path.
- Mobile bootstrap failures are bounded, explicit, safe, and retryable; platform errors are not presented as permission denial.
- Mobile MediaStore metadata and per-collection checkpoints use the shared app-private SQLite index; bounded work resumes on next launch without scheduling OCR.
- Mobile category/source navigation uses real bounded thumbnails; every accessible screenshot remains browsable by date through 120-item pagination.
- A CI-built x86_64 APK passed the TTDT API 36 emulator bridge success path with zero media grants and zero fatal-log matches.
- PDF engine: `pdfrx 2.4.7`/PDFium is accepted after notice, native-engine, size, and Mobile-regression gates.
- Pro Literature supports multi-PDF selection/drop, SQLite persistence, reading-position recovery, and app-local manual metadata correction; source PDFs remain read-only.
- Native build assets: PDFium and SQLite, including opt-in Android x64 validation, are version-pinned, SHA-256 verified, retried, and pre-seeded before CI invokes package hooks.
- GitHub: Private repository, real milestones/issues, and reviewed integration PRs; Public remains maintainer-gated.
- Release evidence: private Draft artifacts are refreshed only from green `develop` merges and must match remote digests and budgets; the Android installable remains debug-signed.
- Current limitation: Office files disclose that no embedded system preview handler is connected and retain a single system Open action; no Office renderer is bundled.

## Ownership

- Track A: merged — core indexing/search/duplicates/safe operations and Desktop Standard.
- Track B: merged — bounded literature metadata, research skeleton, System Insight, and Pro composition.
- Track C: merged — Mobile, bounded thumbnails/grouping/index queue, and Android bridge.
- Lead: contracts, dependency audit, review, CI, integration, release gates, user interaction; no duplicate feature implementation.

## First commands

```bat
tools\picklogic.cmd env
tools\picklogic.cmd pub-get
tools\picklogic.cmd quick
tools\picklogic.cmd full
```

Use target/module tests during development; full commands are integration/release gates.
