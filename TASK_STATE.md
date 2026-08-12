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
- A later quality attempt reached `file_index` after all preceding pure-Dart tests passed, then the fixed SQLite 3.5.1 Linux asset connection closed before headers.
- Hosted run `31623567329` passed Windows and Android: packaged Pro PDF engine exit 0; Standard 39,313,910 B, Pro 40,165,878 B; Android debug/release 78,753,268 / 18,907,513 B. The Android release delta from baseline is only 1,476 B.
- A subsequent Windows attempt verified PDFium prefetch but failed inside a silent native-assets stage after two prior successful hosted builds.
- Added deterministic SQLite 3.5.1 native-asset preparation using the package's official Windows/Linux x64 filenames, hash-derived cache paths, and SHA-256 values. CI now verifies and pre-seeds SQLite before affected tests/builds; no dependency or runtime payload was added.
- Shared native-asset download handling now has three bounded attempts and fails closed on any hash mismatch. Windows release builds retain one outer retry for unrelated transient tool failures.
- Final hosted run `31625641505` passed quality, Android, and Windows. It verified both host SQLite hashes, both PDFium hashes, all 16 PDFium notices, Pro native PDF smoke exit 0, Android release 18,907,513 B, Standard/Pro runtime 39,313,910/40,165,878 B, and ZIPs 17,392,256/17,747,557 B.
- Independent download verification matched all four artifact checksums and reran the packaged Pro self-check successfully. The ZIP payloads are 1,542 B above the runtime measurements because they include `INSTALLATION.md`; CI now labels and gates runtime versus final distributable bytes separately.
- PR #15 merged as `5b3c011`; Issue #12 is closed. PR CI `31626689047` and post-merge push/PR runs `31627436020` / `31627440015` all passed.
- Refreshed the Private Draft/Prerelease with four merge-build artifacts, combined checksums, corrected size report, privacy report, and verification summary; it remains unpublished.
- Final package verification used the TTDT JDK/Android build tools: debug APK signature passed, release-size APK is unsigned by design, both are arm64-only, both Windows payloads contain pinned SQLite/PDFium plus 16 PDFium notices, Standard launched, and Pro native PDF smoke returned 0.
- GitHub reported Node 20 deprecation annotations for checkout/setup-java, then the first migration run exposed the same warning for upload-artifact v4. Issue #16 records the real maintenance task; the isolated Integration branch now pins current official Node 24 releases for all three without adding application dependencies or artifact bytes.
- PR #17 merged as `501aafb`; Issue #16 is closed. CI `31629867869` passed all jobs with zero deprecated-action annotations.
- Booted the existing TTDT API 36 x86_64 emulator and installed a temporary emulator-only Debug APK. Safe Mode and the four primary destinations rendered; no media permission was requested.
- VM heap inspection proved the local Storage spinner was a hidden `MissingPluginException`: Windows Developer Mode prevented Flutter from generating local plugin links. Static DEX inspection proved the hosted arm64 candidate includes both the Android bridge and generated registration call.
- Added bounded bootstrap platform reads plus an explicit safe/retryable failure state. Mobile tests cover timeout, no false permission claim, retry, and the existing vertical slices.
- The Android Gradle build automatically installed CMake 3.22.1 under the user-designated TTDT SDK (37.5 MiB measured); no system-wide location was changed and nothing was removed.
- Issue #18 records the emulator finding and fix. The isolated full gate passed: 92 files formatted unchanged, root analysis clean, 11 quick + 6 remaining modules passed, 97 external + 5 Flutter SDK licenses clean, and privacy findings 0.
- The updated emulator-only x86_64 APK cold-launched in 5.12 seconds, showed the safe bootstrap error instead of a spinner or false permission claim, stayed alive after retry, and had zero Flutter fatal-log matches.
- Based on measured size, complete notices, pinned hashes, native parse/text/render success, and no material Mobile regression, ADR 0003 accepts `pdfrx` 2.4.7/PDFium for v0.1.

## Files changed

- Root governance and product documents.
- `docs/` contracts, snapshot, map, baseline, and ADRs.
- Local `AGENTS.md` files under owned scopes.
- Flutter apps, shared packages, platform plugin scaffolds, synthetic fixtures, tools, and ignored output.
- Root `pubspec.yaml`; dependency resolution selected SQLite 3.5.1 and generated one workspace lockfile.
- Native Android/Windows bridges, desktop/mobile repositories, and CI/tooling gates.
- Pinned PDFium/SQLite native-asset preparation, shared verified-download tooling, and ADR 0004.

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
- Final merge package sizes: Android arm64 release 18,907,513 bytes; Standard distributable/ZIP 39,315,452/17,392,256 bytes; Pro 40,167,420/17,747,556 bytes. All release-size targets pass.
- ADB confirmed the reference phone is arm64-only; no media metadata or content was read.
- PDF engine audit: `pdfrx 2.4.7`/PDFium is accepted after native smoke, complete notices, size, privacy, and Mobile-regression gates.
- Isolated full gate passed after verified native-asset prefetch: 89 files formatted, root analysis clean, 11 quick + 6 remaining modules passed, desktop tests 7/7, dependency audit clean, and privacy findings 0. A direct native widget test was rejected as invalid because `flutter test` does not package `pdfium.dll`; packaged-executable interaction remains the correct runtime gate.
- Current isolated full gate: 92 files formatted with zero changes; root analysis clean; 11 quick + 6 remaining modules passed; 97 external + 5 Flutter SDK licenses passed; privacy findings 0; Windows SQLite and PDFium caches matched pinned hashes.
- Follow-up permission-error wording review passed 11 targeted Mobile tests, root analysis, `git diff --check`, and a zero-finding privacy scan; no dependency changed.
- PR #19 CI `31632859044` passed quality, Android, and both Windows builds. Its Android artifacts matched the published checksums, were arm64-only, and independently showed a v2-signed Debug APK plus intentionally unsigned Release-size APK.
- Static DEX review of the PR #19 Debug APK found both `PicklogicAndroidBridgePlugin` and the generated `registerWith` call, proving hosted plugin registration is present without reading device media.

## Blockers

- Windows Developer Mode must be enabled by the user in Settings; it is required for Flutter plugin symlinks and the evaluated PDF plugin.
- Visual Studio Build Tools with Desktop C++ is not installed and will require a later user-visible UAC/installer step.
- Local Android can compile an emulator APK, but first-party Flutter plugin registration remains blocked until the user enables Windows Developer Mode; Windows additionally needs Visual Studio Build Tools C++. Hosted CI compilation and registration are green.
- Windows Computer Use could capture the running Pro process/window but input activation was blocked twice by `GetCursorPos` access denial; automation stopped without elevation. The packaged engine self-check replaces UI automation for native parse/text/render evidence, while maintainer interaction remains part of first-use validation.
- Final license/copyright owner, Public conversion, real-directory scan, device media permission, first maintainer trial, release signing, and release publication remain gated.

## Next action

Integrate the Mobile bootstrap resilience fix. After the user enables Windows Developer Mode, rebuild the x86_64 Debug APK and rerun the real bridge path without requesting media access. Keep Visual Studio, real-data validation, Android permissions, license/copyright, signing, Public conversion, and publication as explicit gates.
