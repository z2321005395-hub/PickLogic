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
| `pdfrx` 2.4.7 / PDFium (evaluated, not accepted) | Pro local PDF render, thumbnails, search, and text selection | `pdfrx` MIT; PDFium BSD-3 plus required third-party notices | Dry-run adds 33 resolved dependencies and native assets; exact Standard/Pro delta pending CI experiment | System open is lighter but cannot satisfy embedded reader requirements |
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

Gate: no candidate becomes a dependency until its current upstream license, transitive runtime contents, and release-size delta are recorded.

Baseline hosted build evidence before PDFium: Windows Standard and Pro installed directories were each 31,492,217 bytes. The universal debug Android APK was 152,956,858 bytes and is not a release-size proxy; CI now measures an arm64 release artifact against the 40 MB budget while retaining a separately labeled installable debug APK.
