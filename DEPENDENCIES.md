# Third-party Dependency Registry

This is PickLogic's human-reviewed dependency ledger. `pubspec.lock` is the exact resolved Dart graph; `DEPENDENCY_BUDGET.md` records measured size; `THIRD_PARTY_NOTICES.md` indexes redistribution notices; CI audits the complete resolved graph.

## Intake rule

Before adding a dependency, record its project name, upstream URL, exact version or commit, license, copyright notice, linked/imported/copied status, purpose, platform support, approximate artifact-size impact, reason not to implement locally, and lighter alternatives. Copyleft or special redistribution obligations require maintainer review before introduction.

## Current material runtime dependencies

| Project | Upstream and exact version | License / copyright | Use and platform | Reuse form | Size impact | Decision and lighter alternative |
|---|---|---|---|---|---|---|
| Flutter / Dart | [flutter/flutter](https://github.com/flutter/flutter) 3.44.9; [dart-lang/sdk](https://github.com/dart-lang/sdk) 3.12.2 | BSD-3-Clause; Flutter and Dart authors | Shared native UI/runtime; Windows and Android | SDK/runtime dependency; no source copied | Included in every measured baseline | Mandated project stack; Electron/WebView is heavier |
| `crypto` | [dart-lang/core/crypto](https://github.com/dart-lang/core/tree/main/pkgs/crypto) 3.0.7 | BSD-3-Clause; Copyright 2015 the Dart project authors | Streaming SHA-256; all Dart targets | Package import; no source copied | Small pure-Dart code, included in measured totals | `dart:convert` has no SHA-256 implementation |
| `sqlite3` + SQLite | [simolus3/sqlite3.dart](https://github.com/simolus3/sqlite3.dart/tree/main/sqlite3) 3.5.1; native assets from the same release | MIT, Copyright 2020 Simon Binder; SQLite public domain | Local index; Windows, Android, Linux CI | Package import plus provenance- and SHA-256-pinned native library; no source copied | Windows library 1,710,592 B; complete target totals are measured | One binding avoids duplicate platform databases; platform-specific wrappers are not lighter overall |
| `plugin_platform_interface` | [flutter/packages](https://github.com/flutter/packages/tree/main/packages/plugin_platform_interface) 2.1.8 | BSD-3-Clause; Copyright 2013 The Flutter Authors | Replaceable/testable Windows and Android bridge contracts | Package import; no source copied | Pure Dart; negligible within measured totals | Static channels use less structure but weaken safe substitution and tests |
| `pdfrx` / PDFium | [espresso3389/pdfrx](https://github.com/espresso3389/pdfrx/tree/master/packages/pdfrx) 2.4.7; `pdfrx_engine` 0.4.6; `pdfium_flutter` 0.2.3; [PDFium binaries](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium%2F7811) Chromium/7811 | MIT, Copyright 2018 Takashi Kawasaki; PDFium BSD-style license plus bundled third-party notices | Pro PDF render, thumbnails, search, selection/copy; Windows | Package import plus provenance- and SHA-256-pinned binary; no source copied | Standard +7,707,517 B and Pro +8,330,109 B runtime in the accepted audit | System-open is lighter but cannot provide embedded reading; a custom PDF engine is unjustified |

## Development-only tools

CI actions are pinned to immutable commits in `.github/workflows/ci.yml`; Flutter, the TTDT Android toolchain, and Visual Studio Build Tools versions and size effects are tracked in `DEPENDENCY_BUDGET.md`. They add no application runtime bytes.

## Change gate

A dependency change is accepted only after documentation, license/provenance audit, targeted tests, release-size comparison, and notice packaging pass. The complete resolved package inventory remains machine-checked so transitive changes cannot bypass this ledger.
