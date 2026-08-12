# Dependency and Install-Size Budget

Every runtime dependency requires a measured release-size delta before v0.1. Unverified estimates are labeled as such.

| Dependency / tool | Purpose | License | Base artifact impact | Lighter alternative / decision |
|---|---|---|---|---|
| Flutter 3.44.9 / Dart 3.12.2 | Shared native UI and runtime | BSD-3-Clause | Runtime engine included; measure per target | Mandated stack; no Electron/WebView fallback |
| SQLite | Local index | Public domain | Small native library; measure | Platform SQLite varies; one consistent audited binding preferred |
| `sqlite3` 3.5.1 | Direct Dart SQLite access | MIT; SQLite public domain | Accepted; current Windows bundle is about 31.5 MB total before optional PDFium | Manual platform databases increase duplicate code |
| `crypto` | Streaming SHA-256 | BSD-3-Clause | Accepted; pure Dart and small | `dart:convert` lacks SHA-256 |
| `path_provider` (candidate) | App database/cache paths | BSD-3-Clause | Small platform plugin | Custom bridge duplicates platform code |
| `plugin_platform_interface` 2.1.8 | Testable Android/Windows plugin dispatch | BSD-3-Clause | Pure Dart; negligible | Static method channels are smaller in structure but harder to substitute safely in tests |
| `pdfrx` 2.4.7 / PDFium (isolated experiment) | Pro local PDF render, thumbnails, search, and text selection | `pdfrx`/bindings MIT; PDFium and bundled components require 16 notice files | Adds 33 resolved dependencies. Pinned Windows archive is 3,718,879 B; DLL is 7,176,704 B; exact Standard/Pro artifact delta pending CI | System open is lighter but cannot satisfy embedded reader requirements |
| AndroidX WorkManager (candidate) | Resumable mobile indexing | Apache-2.0 | Expected low MB | Foreground-only work misses background requirement |
| TTDT Android toolchain | Local build/ADB/emulator | Mixed official SDK/JDK terms; Temurin GPL-2.0+CPE | Development-only, not packaged | Reused; no duplicate Android Studio install |
| Visual Studio Build Tools | Windows native compilation | Microsoft proprietary tool license | Development-only | Standalone Build Tools is smaller than full IDE |
| `actions/checkout` v4 | CI source checkout | MIT | CI-only; none in artifacts | Git CLI scripting is less maintainable in Actions |
| `actions/setup-java` v4 | CI JDK 17 setup | MIT | CI-only; none in artifacts | Hosted JDK assumptions are less reproducible |
| `actions/upload-artifact` v4 | Retain synthetic build outputs for seven days | MIT | CI-only; none in artifacts | Build-only checks would not expose installable CI evidence |
| `subosito/flutter-action` v2 | Pin and cache Flutter 3.44.9 in CI | MIT | CI-only; none in artifacts | Manual SDK download is lighter in dependencies but duplicates setup logic |

All four CI actions are pinned to immutable commits in `.github/workflows/ci.yml`; moving tags are comments only.

Budgets:

- Android base APK: <= 40 MB.
- Windows Standard: <= 80 MB.
- Windows Pro: <= 130 MB.
- Optional OCR languages, models, and advanced PDF extras are disclosed separately.

Gate: no candidate becomes a dependency until its current upstream license, transitive runtime contents, and release-size delta are recorded. PDFium packaging verifies the pinned archive and DLL SHA-256 values and copies the archive's full license directory next to the executable.

Final hosted baseline before PDFium: Windows Standard 31,606,393 bytes installed, Windows Pro 31,835,769 bytes installed, and Android arm64 release 18,906,037 bytes. The Android release artifact is unsigned size evidence; the separately labeled debug APK is installable.
