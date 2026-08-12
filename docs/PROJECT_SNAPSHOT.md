# PickLogic Project Snapshot

- Product: PickLogic / 拾理; contextual explanation: 知件 / Insight.
- Motto: Small. Local. Useful.
- Status: M1 vertical slices merged; checksummed private alpha candidates and a Draft/Prerelease exist; no public release.
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
- Local build gates: Windows Developer Mode is off; Visual Studio C++ Build Tools is absent.
- PDF engine: `pdfrx 2.4.7`/PDFium passed an initial license-capability screen but is not accepted until Standard/Pro size deltas are measured.
- GitHub: Private repository, real milestones/issues, and merged PRs #9–#11; Public remains maintainer-gated.
- Release evidence: final CI run `31618429285` is green; Standard/Pro ZIPs and arm64 release-size APK are within budget; installable Android artifact remains debug-signed.

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
