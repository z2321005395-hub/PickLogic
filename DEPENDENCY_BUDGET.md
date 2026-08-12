# Dependency and Install-Size Budget

Every runtime dependency requires a measured release-size delta before v0.1. Unverified estimates are labeled as such.

| Dependency / tool | Purpose | License | Base artifact impact | Lighter alternative / decision |
|---|---|---|---|---|
| Flutter 3.44.9 / Dart 3.12.2 | Shared native UI and runtime | BSD-3-Clause | Runtime engine included; measure per target | Mandated stack; no Electron/WebView fallback |
| SQLite | Local index | Public domain | Small native library; measure | Platform SQLite varies; one consistent audited binding preferred |
| `sqlite3` 3.5.1 | Direct Dart SQLite access | MIT; SQLite public domain | Accepted; Windows/Linux x64 libraries are 1,710,592/1,801,592 B; deterministic prefetch adds no runtime payload | Manual platform databases increase duplicate code |
| `crypto` | Streaming SHA-256 | BSD-3-Clause | Accepted; pure Dart and small | `dart:convert` lacks SHA-256 |
| `path_provider` (candidate) | App database/cache paths | BSD-3-Clause | Small platform plugin | Custom bridge duplicates platform code |
| `plugin_platform_interface` 2.1.8 | Testable Android/Windows plugin dispatch | BSD-3-Clause | Pure Dart; negligible | Static method channels are smaller in structure but harder to substitute safely in tests |
| `pdfrx` 2.4.7 / PDFium (accepted) | Pro local PDF render, thumbnails, search, and text selection; reusable Standard PDF preview base | `pdfrx`/bindings MIT; PDFium and bundled components require 16 notice files | Adds 33 packages. Standard +7,707,517 B runtime / +3,850,919 B ZIP; Pro +8,330,109 B / +4,118,626 B | System open cannot satisfy embedded behavior; post-build DLL removal is brittle |
| AndroidX WorkManager 2.11.2 (evaluated, not added) | OS-scheduled persistent mobile work | Apache-2.0 | Unmeasured runtime/transitive increase | Existing SQLite checkpoints resume on next launch without a new dependency; schedule only if device testing proves OS wakeups are required |
| TTDT Android toolchain | Local build/ADB/emulator | Mixed official SDK/JDK terms; Temurin GPL-2.0+CPE | Development-only, not packaged | Reused; no duplicate Android Studio install |
| Visual Studio Build Tools | Windows native compilation | Microsoft proprietary tool license | Development-only | Standalone Build Tools is smaller than full IDE |
| `actions/checkout` 7.0.1 | CI source checkout on Node 24 | MIT | CI-only; none in artifacts | Git CLI scripting is less maintainable in Actions |
| `actions/setup-java` 5.7.0 | CI JDK 17 setup on Node 24 | MIT | CI-only; none in artifacts | Hosted JDK assumptions are less reproducible |
| `actions/upload-artifact` 7.0.1 | Retain synthetic build outputs for seven days on Node 24 | MIT | CI-only; none in artifacts | Build-only checks would not expose installable CI evidence |
| `subosito/flutter-action` v2 | Pin and cache Flutter 3.44.9 in CI | MIT | CI-only; none in artifacts | Manual SDK download is lighter in dependencies but duplicates setup logic |

All four CI actions are pinned to immutable commits in `.github/workflows/ci.yml`; moving tags are comments only.

Budgets:

- Android base APK: <= 40 MB.
- Windows Standard: <= 80 MB.
- Windows Pro: <= 130 MB.
- Optional OCR languages, models, and advanced PDF extras are disclosed separately.

Gate: no candidate becomes a dependency until its current upstream license, transitive runtime contents, and release-size delta are recorded. PDFium packaging verifies the pinned archive and DLL SHA-256 values and copies the archive's full license directory next to the executable.

The SQLite 3.5.1 package publishes hashes for its release assets. CI pre-seeds the exact Windows x64 (`e6ebc264...c278a`) or Linux x64 (`b1772918...e0d2`) file under the package hook's hash-derived cache path after its own verification. This removes opportunistic downloads from tests/builds without changing packaged bytes.

Opt-in emulator validation similarly pre-seeds the package's Android x64 file (`949965f0...8772`). It is not included in arm64 release artifacts and adds no production dependency or release bytes.

Final hosted baseline before PDFium: Windows Standard 31,606,393 bytes runtime, Windows Pro 31,835,769 bytes runtime, and Android arm64 release 18,906,037 bytes. The Android release artifact is unsigned size evidence; the separately labeled debug APK is installable.

Hosted accepted runtime: Standard 39,313,910 bytes; Pro 40,165,878 bytes. The distributable payload adds the 1,542-byte installation guide, yielding 39,315,452 and 40,167,420 bytes before compression; ZIPs are 17,392,256 and 17,747,557 bytes. These are 46.9% and 29.5% of the respective budgets. Android arm64 release is 18,907,513 bytes, only 1,476 bytes above baseline; PDFium is not packaged into Mobile. Packaged Pro parse/text/render smoke returned 0.
