# Task State

Updated: 2026-08-27

## Goal

Build PickLogic / 拾理 as one shared Flutter/Dart monorepo with launchable Windows Standard, Windows Pro, and Android targets, then deliver a verified v0.1.0-alpha without touching real user data.

## Completed

- Inspected the initially empty Git repository; renamed the unborn branch from `master` to `main`.
- Created the canonical GitHub repository `z2321005395-hub/PickLogic`; it began Private and Public conversion was explicitly authorized by the maintainer on 2026-08-27 after the release gates.
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
- PR #24 resolved Issue #23 and merged the durable Mobile index into `develop` as `f7474c4`. Authorized MediaStore metadata and per-collection resume checkpoints use the existing shared SQLite index at one fixed app-private `noBackupFilesDir` path.
- Mobile indexing continues one bounded page at a time with fair collection rotation, supports pause after the current page, resumes from validated checkpoints, and searches persisted records without delaying first paint. Malformed checkpoints restart safely; no WorkManager or other dependency was added.
- Mobile deletion reconciliation and OS-scheduled wakeups remain explicit follow-ups. No real media, physical-device permission, file mutation, or system setting was used while implementing this slice.
- Added a permanent repository-wide open-source reuse policy plus canonical dependency and third-party notice ledgers; infrastructure reuse is preferred while PickLogic retains its product logic.
- Installed the narrowly scoped Visual Studio Build Tools 2022 17.14.37 workload after maintainer authorization: MSVC v143 x64/x86, CMake, and Windows SDK 10.0.26100 are present; ATL/MFC, ASAN, vcpkg, LLVM, ARM64, v142, and unrelated workloads are absent.

## Files changed

- Root governance and product documents.
- `docs/` contracts, snapshot, map, baseline, and ADRs.
- Local `AGENTS.md` files under owned scopes.
- Flutter apps, shared packages, platform plugin scaffolds, synthetic fixtures, tools, and ignored output.
- Root `pubspec.yaml`; dependency resolution selected SQLite 3.5.1 and generated one workspace lockfile.
- Native Android/Windows bridges, desktop/mobile repositories, and CI/tooling gates.
- Pinned PDFium/SQLite native-asset preparation, shared verified-download tooling, and ADR 0004.
- Mobile SQLite persistence adapter, bounded queue/repository/UI lifecycle changes, additive Android private-path bridge contract, tests, ADR 0005, and concise privacy/dependency/known-limit documentation.

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
- Current candidate package sizes: Android arm64 Debug/unsigned Release 79,119,128/18,973,293 bytes; Standard distributable/ZIP 39,315,452/17,392,257 bytes; Pro 40,167,420/17,747,556 bytes. All release-size targets pass.
- ADB confirmed the reference phone is arm64-only; no media metadata or content was read.
- PDF engine audit: `pdfrx 2.4.7`/PDFium is accepted after native smoke, complete notices, size, privacy, and Mobile-regression gates.
- Isolated full gate passed after verified native-asset prefetch: 89 files formatted, root analysis clean, 11 quick + 6 remaining modules passed, desktop tests 7/7, dependency audit clean, and privacy findings 0. A direct native widget test was rejected as invalid because `flutter test` does not package `pdfium.dll`; packaged-executable interaction remains the correct runtime gate.
- Current isolated full gate: 92 files formatted with zero changes; root analysis clean; 11 quick + 6 remaining modules passed; 97 external + 5 Flutter SDK licenses passed; privacy findings 0; Windows SQLite and PDFium caches matched pinned hashes.
- Follow-up permission-error wording review passed 11 targeted Mobile tests, root analysis, `git diff --check`, and a zero-finding privacy scan; no dependency changed.
- PR #19 CI `31632859044` passed quality, Android, and both Windows builds. Its Android artifacts matched the published checksums, were arm64-only, and independently showed a v2-signed Debug APK plus intentionally unsigned Release-size APK.
- Static DEX review of the PR #19 Debug APK found both `PicklogicAndroidBridgePlugin` and the generated `registerWith` call, proving hosted plugin registration is present without reading device media.
- PR #19 merged into `develop` as `696cf19`; Issue #18 is closed. Final PR CI `31633685745` and post-merge push/PR runs `31634310839` / `31634314228` passed every job.
- The `696cf19` release candidate independently passed four manifest hashes, Android signature/ABI/registration checks, both pinned Windows DLL hashes, complete PDFium notices, Standard launch smoke, and Pro PDF smoke exit 0.
- Refreshed all eight assets and notes in the Private Draft/Prerelease; every GitHub asset digest matches locally. Draft PR #14 remains open and unmerged into `main`.
- Issue #21 and Draft PR #22 add an opt-in `device-validation` path for a CI-built x86_64 emulator APK. The path reuses pinned actions and dependencies and adds no arm64 release bytes.
- SQLite 3.5.1 Android x64 is now pre-seeded from its official fixed asset with SHA-256 `949965f0...8772`, preventing opportunistic hook downloads during validation builds.
- CI run `31639131268` built and uploaded the x86_64 APK; the original quality/Windows attempts recorded unrelated upstream connection closures, and rerunning only failed jobs completed all three checks successfully.
- The 64,724,478-byte APK matched its manifest, was x86_64-only and v2-signed, and contained the bridge plus generated registration. On the TTDT API 36 emulator it cold-launched in 3.709 seconds, rendered Storage Insight through the real bridge, retained zero media grants, and produced zero fatal-log matches.
- Repeated hosted HTTP 503 and premature-connection failures later succeeded with unchanged hashes. Native-asset prefetch now permits six bounded attempts with at most 150 seconds of backoff; hash mismatches still fail closed.
- Current durable-index gate: 94 files formatted unchanged; root analysis clean; Mobile 19/19 and Android bridge 10/10 tests passed; 11 quick + 6 remaining modules passed; 97 external + 5 Flutter SDK licenses passed; privacy findings 0; Windows SQLite and PDFium caches matched pinned hashes.
- PR #24 CI `31646213015` and post-merge push/PR runs `31647445953` / `31647449631` passed quality, Android, and Windows jobs. The PR's x86_64 APK matched its manifest, was v2-signed, and passed isolated TTDT API 36 cold-start, app-private SQLite create/reopen, UI wording, zero-media-grant, and zero-fatal-log checks.
- Current `flutter doctor -v` recognizes Build Tools 17.14.37 and Windows SDK 10.0.26100. The exact install is 3,099,022,241 bytes with a 42,732,999-byte package cache; total system-disk change including shared SDK files was about 5.41 GiB and no reboot was requested.
- Local synthetic Desktop tests passed 7/7 and Windows bridge tests passed 6/6. The first Standard build failed closed before compilation because Flutter could not create plugin symlinks before the requested reboot.
- After reboot, `AllowDevelopmentWithoutDevLicense=1` was present and Flutter generated all plugin symlinks. The Chinese repository path then exposed an MSBuild custom-step encoding failure, so validation continued from a new read-only-equivalent detached ASCII-path worktree without moving or renaming the repository.
- Local Windows Standard and Pro Release builds passed with pinned SQLite/PDFium hashes and all 16 PDFium notices. Preserved runtime sizes are 39,315,958 B / 40,167,926 B; portable ZIPs are 17,020,581 B / 17,370,327 B, both within budget.
- Standard and Pro each completed a real first-window inspection against synthetic fixtures: both displayed `Developer Safe Mode: ON`; Standard exposed only base navigation, while Pro additionally exposed Literature, Research, and System Insight. Pro's packaged synthetic PDF smoke exited 0. No scan or file-operation control was used.
- CI push/PR runs `31654697055` / `31654699150` passed quality, dependency/license and privacy audits, Android packages, Windows Standard/Pro packages, and the Pro packaged PDF smoke for commit `1aaec97`.

## Blockers

- The canonical repository's Chinese path currently corrupts one Flutter/MSBuild custom-step path. Local Windows validation therefore uses an ASCII-only detached worktree; the repository itself was not moved or renamed.
- Final license/copyright owner, Public conversion, real-directory scan, device media permission, first maintainer trial, release signing, and release publication remain gated.

## Next action

Obtain explicit approval for a Windows reference-directory read-only scan and nubia Debug APK/media permission before Phase 2 reference-data validation. Separately obtain maintainer decisions for the final license/copyright, first trial, signing, Public conversion, and publication.

## Fast delivery user-test stage

- Standard now has a clear folder picker, selected-root search isolation, virtual category filters, exact SHA-256 duplicate review, preview/open/reveal, Insight, and explicit read-only Safe Mode controls.
- Pro now supports local PDF selection, an app-private persistent literature catalog and reading position, metadata/DOI display, continuous PDF reading, zoom, page jump, search, text selection, and rename preview only.
- Desktop Standard/Pro and Android Mobile now expose visible Chinese/English switching; focused integration tests pass 12/12 Desktop and 22/22 Mobile.
- Final bilingual Standard/Pro user-test ZIPs were built and launched from the ASCII worktree; Pro packaged PDF smoke exited 0.
- A bilingual arm64 Android user-test APK was built, installed, and launched on nubia NX736J as the parallel package `io.picklogic.mobile.usertest`, preserving the previous differently signed PickLogic package and its data.
- No real file or media mutation was enabled. Android media permission remains user-controlled and was still ungranted at the last check.

## Usability convergence stage

- Mobile Screenshots, Photos, Files, and recent media now page through all accessible MediaStore metadata in stable date order (120 items per page) instead of stopping at 60; thumbnails remain visible-only and bounded. Synthetic 145-item tests verify cross-page order, deduplication, and completion.
- Standard and Pro now share one localized dual-pane Windows shell with drive/common-folder entry points, independent navigation, indexed search into the active pane, exact duplicate review, read-only storage summary, and opt-in Preview/Insight drawers.
- Desktop auto-index is off by default. After an in-app disclosure and confirmation it scans only Desktop, Documents, and Downloads into the local index; drive roots remain browse-only. Safe Mode keeps create/move/rename/delete unavailable.
- Pro Literature uses a library-and-reader layout; metadata and rename preview open only on request. Research and System Insight now follow the selected language and shared theme.
- Integrated gates passed: Desktop 19/19, Mobile 28/28, Shared UI 2/2, Windows bridge 7/7; Dart analyses were clean. Windows Standard and Pro Release builds succeeded, and Pro packaged PDF smoke exited 0.
- Final local user-test sizes: Standard 39,505,916 B installed / 17,108,478 B ZIP; Pro 40,456,188 B installed / 17,487,652 B ZIP; Android arm64 Debug 79,255,936 B. Debug APK size remains above the 40 MB release target; release-size measurement is still the relevant budget gate.
- Updated `io.picklogic.mobile.usertest` installed and launched on nubia NX736J. Existing image/video/audio permissions were preserved; no fatal log matches were found and no media mutation was enabled.

## Next action

Collect the maintainer's hands-on feedback from the new Standard dual-pane shell, Pro Literature reader, and Z70 all-screenshots pagination. Do not add more features before that feedback.

## Single-pass UX consolidation delivery

- Goal: converge the working Desktop and Mobile implementations into one coherent, bilingual, read-only user experience without replacing shared indexing, PDFium, MediaStore, persistence, or Safe Mode backends.
- Desktop: unified Standard/Pro navigation and visual tokens; the dual-pane file workspace now uses one contextual Preview/Insight panel. Images, bounded text, folders, and PDF files preview in place; drives and common folders remain direct browse entry points.
- Pro: Literature remains a library-and-reader workspace with PDFium rendering; Preview/Insight now follows the same contextual interaction and language system as Standard.
- Mobile: the home page now separates file types, smart collections, and sources; Screenshots exposes every accessible indexed screenshot in date order with month/consecutive/review filters; Photos and Storage use compact type/source facets; Insight reports bounded platform evidence.
- Z70 reference: inspected only the local system file manager's visible layout. The user-test package is installed and focused on nubia NX736J; the screenshot page exposed 4,253 accessible MediaStore screenshots, all-month navigation, and the non-destructive deletion-review queue. Fatal and Flutter-overflow log matches were zero.
- Verification: scoped formatting and analysis passed; quick/remaining modules passed 11/11 and 6/6; Desktop 19/19, Mobile 30/30, and Windows bridge 7/7 tests passed; dependency audit found 0 missing/restricted/unknown licenses; privacy scan found 0 findings.
- Builds: final Standard and Pro Windows Release ZIPs launched successfully; Pro packaged synthetic PDF smoke exited 0. The final arm64 Debug user-test APK installed and launched under `io.picklogic.mobile.usertest` without replacing the differently signed prior package.
- Safety: no real Windows or Android file was moved, renamed, modified, or deleted. Screenshot actions remain app-local review marks. No private screenshot, filename, path, device serial, or media content was added to Git.
- Known limitation: embedded Office shell preview and archive-content listing are not connected; those files use metadata plus the single system Open action. The Android Debug APK exceeds the release-size target; the smaller signed-release-size gate remains separate.

## Next action

Merge the green Private integration PR into `develop`, then stop feature work and collect maintainer hands-on feedback from Standard, Pro, and the Z70 user-test package.

## Usability recovery and UI rebuild

- Goal: restore coherent, immediately usable Desktop Standard, Desktop Pro, and Android workflows while preserving the working shared core, PDFium, SQLite, platform bridges, MediaStore paging, and Safe Mode.
- Desktop: added a localized home, drive/common-folder entry points, list/grid/dual-pane browsing, real image thumbnails, bounded image/PDF/text/ZIP/folder preview, and one vertically unified Preview + Insight context pane. Office files use an explicit unavailable fallback plus system Open; no renderer was bundled.
- Pro: added native multi-PDF selection and drag/drop through one bounded import path, app-private SQLite persistence with one-time JSON migration, manual catalog-metadata correction, and explicit partial/failure feedback. Reading, zoom, page jump, search, selection, and persisted position continue to use the existing PDFium reader.
- Mobile: rebuilt the category, recent, and organize navigation around real MediaStore counts and bounded thumbnails. On nubia NX736J, the read-only user-test app displayed aggregate counts, then showed all 4,254 accessible screenshots as date-browsable and advanced from 120/4,254 to 240/4,254 without a fatal, missing-plugin, or overflow log match.
- Safety: Windows and Android source files remained read-only. Screenshot review marks remain app-local; no delete, move, rename, or system mutation was enabled. No private file/media name, content, screenshot, path, or device serial entered Git.
- Verification commands: targeted Dart/Flutter analyses and module tests; then one `tools\\picklogic.cmd full` gate from an ASCII detached worktree. Result: 103 files formatted unchanged, analysis clean, 11 quick + 6 remaining modules passed, 105 external + 5 Flutter SDK license entries accepted, and privacy findings 0.
- Build verification: Standard and Pro Release windows stayed running with a visible `PickLogic` window; packaged Pro synthetic PDF smoke exited successfully. The arm64-only Debug APK installed and launched as `io.picklogic.mobile.usertest`, with media grants present and the app focused.
- Artifacts: Standard 41,345,241 B installed / 17,870,471 B ZIP; Pro 41,378,009 B installed / 17,885,390 B ZIP; Android arm64 Debug 80,741,851 B. SHA-256 values are retained with the ignored local artifacts, not published as a Release.
- Build tooling: `tools/build_windows.ps1` now reports exported artifacts on Windows PowerShell 5.1 without requiring unavailable `System.IO.Path.GetRelativePath`.

## Next action

Push the scoped Private PR, wait for its single CI gate, merge to `develop`, and stop feature work for maintainer hands-on testing. Do not make the repository or artifacts Public.

## Open / Preview / Operate recovery

- Desktop now opens images, system-supported video/audio, PDF, bounded text/code, ZIP lists, Office Open XML summaries, folders, and Shell thumbnails internally. File views support Details/List/icon/grid/dual-pane modes, 48–256 px Ctrl-wheel zoom, and independent preview zoom.
- Windows creates `%USERPROFILE%\PickLogic-TestWorkspace`, imports only copies, and executes previewed/confirmed create, move, rename, Test-Trash, and Undo operations inside authorized roots. Managed-folder delete uses the Windows Recycle Bin with in-session restore when Shell supplies an undo item; unselected locations remain read-only.
- Pro retains one SQLite-backed literature library and PDFium reader, adding multi-PDF import, selection/copy, opt-in selected-text translation with DPAPI secret storage, first-party module registry, and authorized rename execution after preview.
- Mobile adds internal image/video/audio/PDF/text/APK/archive/Office viewers, persisted PDF position and 2–6-column media grids, system-confirmed APK install and MediaStore Trash entry points, plus an SAF-authorized Test Workspace with copy/move/rename/Test-Trash/Undo.
- New direct dependencies are `video_player` 2.13.0 and `video_player_win` 3.2.2, both BSD-3-Clause and recorded in all dependency ledgers. Full dependency/license and privacy gates report zero restricted, unknown, missing, or private-data findings.
- Local verification: full Dart gate passed 11 quick + 6 remaining modules; Desktop 20/20, Mobile 30/30, Windows bridge 9/9, and Android bridge 12/12 tests passed. Windows Standard/Pro Release and Android ARM64 Debug/Release/Profile builds compiled; packaged Pro PDF smoke exited 0.
- Emulator validation: the final arm64-only, v2-signed Profile APK installed and launched on `TTDT_Modern_64`; UI semantics showed the localized PickLogic home and app-scoped log review found zero fatal matches. Only old PickLogic emulator test data was removed to make installation space; no other emulator or user data was changed.
- User-test artifacts: Standard 18,259,594 B ZIP / 42,315,395 B installed; Pro 18,276,491 B ZIP / 42,348,163 B installed; Mobile ARM64 Profile 31,668,994 B. Checksums are stored beside ignored local artifacts.

## Current blocker / next action

The nubia Z70 is not currently listed by ADB. After USB connection and the user's RSA/media/SAF confirmations, install the final APK, open real MediaStore read-only, validate viewers and grid paging, then stop feature work. Push the scoped Private PR, wait for CI, and merge to `develop`; do not publish a Release or make the repository Public.

## Open / Preview / Operate CI recovery

- Private PR #29 built Windows Standard, Windows Pro, and Android Debug successfully, but its Linux quality job exposed one host assumption: `WindowsWorkspaceController` required `USERPROFILE` during cross-platform Flutter widget tests.
- The controller now keeps the Windows `%USERPROFILE%\\PickLogic-TestWorkspace` contract unchanged and uses the system temporary directory only on non-Windows test hosts.
- Local verification after the fix: the complete Desktop Flutter suite passed 20/20.

## Next action

Run the quick repository gate, push the focused CI fix, require a green PR, merge it into `develop`, and retain the Z70 USB/RSA/media/SAF validation as the only physical-device gate.

## Actions storage optimization

- Audited 144 Actions artifacts with run, branch, commit, size, creation, and expiry metadata: 6,458,827,405 bytes total. The local user-test-3 Standard, Pro, and ARM64 packages were re-hashed successfully before cleanup.
- Deleted only those 144 Actions artifacts through the artifact REST endpoint; the follow-up list reports 0 artifacts and 0 bytes. Commits, branches, tags, PRs, Issues, workflow definitions, workflow runs, and Private Draft Release assets were preserved.
- Repository artifact/log retention is now 3 days instead of 90 days. Routine push/PR CI keeps quality and platform verification but uploads no packages; manual candidate runs and `v*` tags may upload packages for 3 days.
- CI skips the duplicate heavy `develop -> main` PR run when the same SHA is verified by the `develop` push, cancels superseded routine runs per event/ref, and limits `labeled` reruns to the `device-validation` path.
- Changed files: `.github/workflows/ci.yml`, `.github/AGENTS.md`, `docs/development-log.md`, and `TASK_STATE.md`. Validation: workflow policy assertions passed, `git diff --check` passed, and privacy findings were 0.

## Next action

Commit the scoped CI-only change, push its Private feature branch, open one PR to `develop`, require green CI with no routine artifacts, merge, and verify local/remote synchronization.

## Mature file and literature workflows

- Goal: make Desktop and Mobile content-first file browsers and converge Pro on the most valued local Zotero/ReadCube/EndNote/小绿鲸 workflows without copying proprietary UI or weakening Safe Mode.
- Mobile: added a persisted user-authorized SAF hierarchy browser, direct full-screen internal viewers, visible-only folder thumbnails, swipe-through media, Insight facts, and app-local favorite/deletion-review marks. Real media remains read-only.
- Desktop: single-click selection no longer opens Preview/Insight; double-click/Enter opens internally, and Backspace/F2/Escape/Ctrl+Shift+I provide predictable file-manager shortcuts under existing authorization gates.
- Pro: added library search/tag filters, fuller metadata editing, local page-linked annotations, BibTeX/RIS/quick citation copy, selection/current-page translation, and user-confirmed cancellable full-document translation in a bilingual pane. PDF bytes are never uploaded.
- Contracts: added bridge-only SAF browse DTOs plus additive citation/annotation/translation helpers; existing `FileRecord` and `LiteratureRecord` serialization remains compatible.
- Verification: repository full gate passed (11 quick + 6 remaining modules), dependency license findings 0, privacy findings 0, Android Bridge 12/12, Mobile UI 15/15, Pro UI 7/7, and ARM64 Debug APK compilation succeeded.
- Blocker: nubia Z70 is connected but ADB remains unauthorized pending the maintainer's RSA confirmation. Windows source build from the canonical Chinese path hit the known Flutter/MSBuild path-decoding defect; package from an isolated ASCII worktree after the checkpoint commit.

## Next action

Commit this coherent checkpoint, build and smoke-test Standard/Pro from an ASCII-path worktree, install the rebuilt APK after Z70 RSA authorization, then push one Private PR and require green CI before the authorized Public conversion/release gate.

## Alpha release packaging

- Added the maintainer-authorized BSD-3-Clause license with `Copyright (c) 2026 Dawei Zhou`; README, contribution guidance, Windows version resources, installation text, and known issues now agree.
- Final local packages were rebuilt from commit `9833667` in the ASCII-path worktree. Standard is 18,710,258 B, Pro is 18,724,631 B, and the arm64 Profile APK is 31,734,970 B.
- Both Windows ZIPs contain `LICENSE`, `THIRD_PARTY_NOTICES.md`, installation guidance, PDFium's 16 verified notice files, and the expected runtime. The Pro packaged PDF smoke exited 0.
- The APK is arm64-v8a only and verifies with APK Signature Scheme v2. The repository dependency/license audit reports 113 external + 5 Flutter SDK packages with zero missing/restricted/unknown findings; privacy findings remain 0.
- The Standard and Pro user-test applications were launched successfully from independent extracted directories. Windows Computer Use screenshot automation was blocked by desktop access error `0x80070005`, so no system permission was weakened or bypassed.
- The nubia Z70 remains visible to ADB as `unauthorized`; installation is waiting only for the user's on-device RSA confirmation. No device serial, media metadata, or content was recorded.

## Next action

Push this branch, require one green integration CI, merge through the canonical history, convert the same repository to Public, and publish the checksum-pinned v0.1.0-alpha prerelease. Install/launch the APK immediately after the Z70 RSA prompt is accepted.

## Public v0.1.0-alpha release

- PR #31 merged the mature file/literature workflows into `develop` as `a52d261`; the existing integration PR #14 then merged the complete history into `main` as `bf19c8e`.
- PR, `develop`, `main`, and tag CI passed quality/tests/audits, Android, Windows Standard/Pro, and packaged Pro PDF smoke gates. One `main` Android setup attempt failed before compilation because the upstream Flutter download connection reset; rerunning only that failed job passed.
- The canonical repository is Public at `https://github.com/z2321005395-hub/PickLogic` with BSD-3-Clause detected by GitHub. Existing commits, branches, tags, PRs, Issues, workflow definitions, and run history were retained.
- Public prerelease `v0.1.0-alpha` contains the checksum-matched Standard ZIP, Pro ZIP, arm64 Profile APK, installation guide, project license, third-party notices, and checksum file. Remote asset digests equal the locally verified hashes.
- The release tag CI left two candidate artifacts totaling 97,158,757 bytes; both use the configured three-day retention and expire on 2026-08-29. No workflow run or development history was deleted.
- The nubia Z70 remains connected as ADB `unauthorized`. No APK replacement, media permission, or real MediaStore access was attempted without the required on-device RSA confirmation.

## Next action

After the user accepts the Z70 USB-debugging RSA prompt, install the published arm64 Profile APK, launch PickLogic, grant only user-selected read-only media/SAF access, and collect hands-on usability feedback. Stop new feature work until that trial.

## Human-readable desktop storage units

- Goal: remove raw byte counts from Desktop Standard/Pro user-facing file, storage, preview, and Insight surfaces.
- Added one shared formatter that presents compact KB/MB/GB/TB values; zero and sub-KB files now show `0 KB` or `< 1 KB` instead of raw bytes.
- Updated the Desktop explorer, storage summaries, internal preview surfaces, and shared Insight panel to use the same formatter and neutral `占用空间` / `Size` labels.
- Verification: Shared UI tests passed 4/4 and the complete Desktop suite passed 22/22; targeted source search found no remaining raw-byte display formatter in Desktop/Shared UI.

## Next action

Build and smoke-test refreshed Standard/Pro packages from an ASCII-path worktree, then install a non-destructive parallel Android user-test package because the Z70 already contains differently signed `io.picklogic.mobile` and `io.picklogic.mobile.usertest` installations.

## Pro PDF import usability recovery

- The user-visible failure came from the still-running `pro-68c990b` package built on 2026-08-13, not the current release source.
- Reworded the Literature surface around the user task (`文献库`, add/drop/read) and removed implementation jargon from the first screen.
- PDF selection, unreadable local files, invalid PDFs, and catalog-save failures now have separate actionable messages; no private path or raw exception is displayed.
- A valid `%PDF-` signature may occur within the first 1024 bytes, and an unavailable tail metadata window no longer prevents adding and reading the PDF with filename fallback.
- Verification: Literature Core passed 14/14 and the complete Desktop suite passed 23/23, including a focused picker-recovery widget test.

## Next action

Commit the recovery, build Standard/Pro from an ASCII-path worktree, launch the refreshed packages, and validate a synthetic local PDF through the packaged Pro reader before asking the user to retry their own PDF.

## Final user-test usability validation

- Desktop Standard/Pro packages were rebuilt from the recovery branch. User-facing file, storage, Preview, and Insight sizes use KB/MB/GB/TB; Pro Literature import has distinct picker, unreadable-file, invalid-PDF, and catalog-save recovery messages.
- A parallel arm64 Profile APK was built as `io.picklogic.mobile.usertest`, v2-signature verified, installed with update semantics, and launched on the authorized nubia Z70 without replacing the differently signed PickLogic package or clearing either package's data.
- Z70 read-only media validation used no screenshots, filenames, paths, or content in repository evidence. One accessible audio item initialized and advanced from 0:00 to 0:13/0:14 while muted; one accessible video initialized and completed 0:16/0:16 while muted. App-scoped warnings contained no ExoPlayer, MediaCodec, permission, or fatal matches.
- A photo opened in the dedicated full-body viewer rather than a sheet: the content area occupied the complete post-AppBar viewport and exposed reset-zoom and rotate controls. App-scoped warnings contained no image decode, memory, or permission matches.
- Media lists remain date ordered and paged through every accessible record; 120 is the bounded in-memory page size, not a collection cap. Synthetic coverage verifies loading from 120/145 to 145/145.
- Added regression coverage requiring photos to use the full-page image viewer and audio/video collections to route through the shared internal media player.
- Verification: Mobile 37/37, Android Bridge 12/12, Shared UI 4/4, Desktop 23/23, and Literature Core 14/14 tests passed. Windows Computer Use remained blocked by desktop access error `0x80070005`; no security control was bypassed.
- Local ignored artifacts: Standard ZIP 18,712,146 B; Pro ZIP 18,726,422 B; arm64 Profile APK 32,322,278 B. The APK installed and launched successfully; both Windows package processes launched successfully.

## Next action

Commit the focused media-viewer regression tests and this state update, run the repository quick gate and privacy scan, then push one feature PR into `develop` and merge it only after green CI. Keep routine build artifacts local under `codex_output/`.
