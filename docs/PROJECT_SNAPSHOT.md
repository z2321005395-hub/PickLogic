# PickLogic Project Snapshot

- Product: PickLogic / 拾理; contextual explanation: 知件 / Insight.
- Motto: Small. Local. Useful.
- Status: the Public v0.1.0-alpha user-testing prerelease is published from the verified `main` tag.
- Targets: Windows Standard, Windows Pro, Android Mobile.
- Architecture: one Flutter/Dart workspace, shared pure-Dart core, narrow Windows/Android bridges.
- Desktop: one implementation with `main_standard.dart` and `main_pro.dart`; no duplicate app.
- Core safety: virtual classification does not move files; mutations require Plan -> Preview -> Confirm -> Execute -> Undo/Trash.
- Debug safety is enforced through per-location states: read-only, managed folder, or Test Workspace; no global mutation grant exists.
- Real data is read-only by default. Test Workspace imports copies; managed roots require an explicit system picker authorization.
- Privacy: no account, ads, default telemetry, backend, or full-file upload.
- AI: optional provider; deterministic rules and metadata come first; app works with AI disabled.
- Current recovery targets: Android user-test <= 60 MiB, Standard <= 80 MiB, Pro soft target <= 180 MiB.
- Canonical contracts: `docs/DATA_MODEL.md`.
- Current state and next action: `TASK_STATE.md`; installation limits: `docs/KNOWN_ISSUES.md`.
- Repository map: `docs/REPO_MAP.md`.
- Dependency gate: `DEPENDENCY_BUDGET.md`.
- License: BSD-3-Clause, Copyright (c) 2026 Dawei Zhou; public release assets include the project license and applicable third-party notices.
- Known brand risk: exact-name npm/open-source projects and active PickLogic domains; display name unchanged pending maintainer decision.
- Local Android baseline: TTDT toolchain with JDK 17, Gradle 9.4.1, SDK/API 36, ADB, and existing AVDs.
- Reference phone verified by ADB: nubia NX736J, Android 15, API 35, arm64-only. Do not record its serial.
- Verification: merged local suite and hosted Android/Windows builds pass; dependency-license and privacy scans report no findings.
- Local Windows gate: Build Tools 2022 17.14.37 and Developer Mode are verified; Standard/Pro build and launch from an ASCII-path worktree because Flutter/MSBuild corrupts the canonical Chinese path.
- Mobile bootstrap failures are bounded, explicit, safe, and retryable; platform errors are not presented as permission denial.
- Mobile MediaStore metadata and per-collection checkpoints use the shared app-private SQLite index; bounded work resumes on next launch without scheduling OCR.
- Mobile category/source navigation uses real bounded thumbnails; every accessible screenshot remains browsable by date through 120-item pagination.
- Mobile Files now has a user-authorized hierarchical SAF browser, visible-only thumbnails, direct full-screen photo/video/audio/document opening, and app-local favorite/review marks.
- A CI-built x86_64 APK passed the TTDT API 36 emulator bridge success path with zero media grants and zero fatal-log matches.
- PDF engine: `pdfrx 2.4.7`/PDFium is accepted after notice, native-engine, size, and Mobile-regression gates.
- Pro Literature supports multi-PDF selection/drop, SQLite persistence, library search/tag filters, metadata correction, reading-position recovery, local page-linked annotations, BibTeX/RIS/text citation copy, and explicit selection/page/document translation with a bilingual pane; source PDFs remain read-only.
- Desktop file selection no longer forces Preview/Insight open; double-click/Enter opens content and Ctrl+Shift+I opens the contextual panel on demand.
- Native build assets: PDFium and SQLite, including opt-in Android x64 validation, are version-pinned, SHA-256 verified, retried, and pre-seeded before CI invokes package hooks.
- GitHub: the same repository and complete development history are Public at `z2321005395-hub/PickLogic`; commits, branches, PRs, Issues, workflow runs, and tags were preserved.
- Release evidence: v0.1.0-alpha Standard/Pro ZIPs include BSD-3-Clause and third-party notices; the arm64 Profile APK is v2 test-signed. GitHub asset digests match the published checksum file.
- Current limitation: Office Open XML files have bounded structural summaries and Shell thumbnails, but an installed Office/WPS Shell Preview Handler is not embedded; no Office runtime is bundled.

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
