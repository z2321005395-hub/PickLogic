# Task State

Updated: 2026-08-13

## Goal

Build PickLogic / 拾理 as one shared Flutter/Dart monorepo with launchable Windows Standard, Windows Pro, and Android targets, then deliver a verified v0.1.0-alpha without touching real user data.

## Completed

- Inspected the initially empty Git repository; renamed the unborn branch from `master` to `main`.
- Created the Private GitHub repository `z2321005395-hub/PickLogic`; Public conversion remains blocked on maintainer approval.
- Audited Flutter/Windows/Android tool availability and started the official Flutter stable SDK download.
- Reused the existing TTDT Android toolchain instead of installing Android Studio: JDK 17, Gradle 9.4.1, SDK/API 36, ADB, Emulator, and two AVDs.
- Verified the reference phone via ADB without recording its serial: nubia NX736J, Android 15, API 35.
- Performed a brief brand screen; exact-name software/npm/domain conflicts require review before Public.
- Created global/local agent rules, product principles, architecture, contracts, privacy policy, dependency budget, roadmap, quick snapshot, repository map, device baseline, and ADRs.
- Installed and hash-verified Flutter 3.44.9 / Dart 3.12.2 in a user-level tool directory and disabled Flutter analytics.
- Generated real Flutter projects for Desktop, Mobile, Windows bridge, and Android bridge; removed duplicate template examples and per-package lockfiles through a guarded cleanup script.
- Added one Dart workspace, Standard/Pro desktop entrypoints, a four-destination Mobile shell, shared design/localization/safe-mode UI, and synthetic fixture generation.
- Implemented initial shared packages for models/interfaces, classification, search, streaming SHA-256 duplicates, SQLite indexing, operation planning, Insight, preview cache, literature, research, and system insight, with focused tests.
- Added a streaming directory scanner and an authorized synthetic-root Move/Rename/Undo operator; real paths remain read-only.
- Added Android MediaStore paging, permission-state, user-triggered permission/SAF, storage restrictions, search/open adapters, and a four-page mobile vertical slice without scanning real media.
- Added Windows system folder picker/open/reveal/attributes/storage bridge code and wired the Desktop shell to bounded scan batches, classification, SQLite upserts, search, preview, and Insight.
- Added pinned CI jobs, TTDT-first local tooling, dependency-license checks, privacy/secret checks, artifact build scripts, and size reporting.
- Created truthful Bootstrap commit `3303b03`, switched Lead to `develop`, and established the requested three feature branches plus clean sibling worktrees.
- Completed Track A, B, and C in isolated Codex worktrees; Lead reviewed and merged PRs #9, #10, and #11 into `develop`.
- Track A added resumable SQLite scan reconciliation, ranked search, streaming exact duplicates, and synthetic-root-only batch operation previews.
- Track B added bounded PDF metadata/DOI probing, preview-only literature naming, reading progress, virtual research buckets, and read-only System Insight views.
- Track C added bounded MediaStore thumbnails, screenshot timeline groups, a one-page-at-a-time metadata queue, and explicit scoped-storage limits.
- Established six truthful GitHub milestones and eight roadmap/validation issues; M0 and the Track A issue are closed with evidence.
- Baseline and track CI runs compiled Android, Windows Standard, and Windows Pro successfully on hosted runners.
- Final release-candidate CI run `31618429285` passed all three jobs and produced checksummed packages.
- Downloaded artifacts were independently hash-checked; both Windows ZIPs had required runtime entries and both executables completed a synthetic first-window smoke launch.
- Verified the arm64 debug APK signature and ABI. The separate 18,906,037-byte arm64 release artifact is intentionally unsigned for size evidence only.
- Created a Private Draft/Prerelease `v0.1.0-alpha` with four packages plus checksum, size, privacy, and verification reports; nothing was published.
- Opened Draft integration PR #14 from `develop` to `main`; it must remain unmerged until maintainer trial, license, signing, and device gates pass.
- Started isolated branch `codex/pdfium-size-audit`; added a generated two-page Pro PDF reader with search, selection/copy, thumbnails, bounded cache, and injectable tests without reading real PDFs.
- Verified `pdfrx` 2.4.7's 33 added packages: 97 external and 5 Flutter SDK packages now pass the license gate with zero missing/restricted/unknown findings.
- Verified the fixed PDFium Windows archive through GitHub attestation, pinned archive/DLL hashes, and added a packaging gate for all 16 upstream notice files.
- Added a packaged Pro engine self-check that only parses generated PDF bytes, extracts both pages' text, renders one bounded image, and returns a process exit code; no locator or real file can enter this path.
- Hosted experiment run `31622068263`: quality and Windows jobs passed; Standard measured 39,313,910 bytes installed / 17,392,260-byte ZIP and Pro 40,165,878 / 17,739,463. Both packages independently matched their manifests and carried the expected DLL plus all 16 license files.
- The same run's Android job failed only because GitHub returned HTTP 503 for the Gradle 9.1.0 distribution twice in immediate succession; CI now uses three attempts with 15/30-second bounded backoff.

## Files changed

- Root governance and product documents.
- `docs/` contracts, snapshot, map, baseline, and ADRs.
- Local `AGENTS.md` files under owned scopes.
- Flutter apps, shared packages, platform plugin scaffolds, synthetic fixtures, tools, and ignored output.
- Root `pubspec.yaml`; dependency resolution selected SQLite 3.5.1 and generated one workspace lockfile.
- Native Android/Windows bridges, desktop/mobile repositories, and CI/tooling gates.

## Commands and verification

- Read-only environment and Git checks.
- Official Flutter manifest query: stable 3.44.9 / Dart 3.12.2; expected SHA-256 recorded before extraction.
- TTDT `java`, `javac`, `adb`, `emulator -list-avds`, `sdkmanager --list_installed`, and basic ADB `getprop` checks passed.
- `flutter doctor -v`: Flutter, Windows OS, Android toolchain/licenses, network, and connected Android device passed; Visual Studio is the only toolchain failure.
- `dart pub get` resolved the workspace and SQLite native asset without changing Windows policy.
- Final merged `tools\picklogic.cmd full`: 85 files formatted with zero changes; analysis reported no issues; 11 quick modules plus 6 remaining SQLite/Flutter modules passed.
- Dependency audit: 65 external packages and 4 Flutter SDK packages had recognized licenses; no missing/unknown/strong-copyleft package finding.
- Committed-source privacy scan passed with zero findings.
- Latest Track B and Track C GitHub Actions each passed quality, Android debug, and Windows Standard/Pro build jobs.
- Final package sizes: Android arm64 release 18,906,037 bytes; Standard installed/ZIP 31,606,393/13,541,337 bytes; Pro installed/ZIP 31,835,769/13,628,931 bytes. All release-size targets pass.
- ADB confirmed the reference phone is arm64-only; no media metadata or content was read.
- PDF engine dry-run audit: `pdfrx 2.4.7` is MIT over PDFium BSD-3 and would add 33 resolved dependencies plus native assets; it remains unaccepted pending measured size impact.
- Isolated full gate passed after verified native-asset prefetch: 89 files formatted, root analysis clean, 11 quick + 6 remaining modules passed, desktop tests 7/7, dependency audit clean, and privacy findings 0. A direct native widget test was rejected as invalid because `flutter test` does not package `pdfium.dll`; packaged-executable interaction remains the correct runtime gate.

## Blockers

- Windows Developer Mode must be enabled by the user in Settings; it is required for Flutter plugin symlinks and the evaluated PDF plugin.
- Visual Studio Build Tools with Desktop C++ is not installed and will require a later user-visible UAC/installer step.
- Native Android and Windows code cannot yet be compiled locally because Flutter plugin symlinks require Developer Mode; Windows additionally needs Visual Studio Build Tools C++. Hosted CI compilation is green.
- Embedded PDF page rendering/search/selection remains isolated from `develop` until hosted size results and packaged-executable interaction pass.
- Windows Computer Use could capture the running Pro process/window but input activation was blocked twice by `GetCursorPos` access denial; automation stopped without elevation. The packaged engine self-check replaces UI automation for native parse/text/render evidence, while maintainer interaction remains part of first-use validation.
- Final license/copyright owner, Public conversion, real-directory scan, device media permission, first maintainer trial, release signing, and release publication remain gated.

## Next action

Run the revised hosted CI, require packaged Pro PDF engine exit 0 and a passing Android size build, then review/merge Draft PR #15 into `develop` if all evidence remains green. Keep maintainer-controlled Developer Mode/Visual Studio, Android media permission, real-data validation, license/copyright, signing, Public conversion, and publication as explicit gates.
