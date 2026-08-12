# Third-party Notices

This file is the redistribution notice index for PickLogic. It is not a replacement for upstream license text. Release packaging must include the complete applicable license and notice files, and CI must fail when required notices are missing.

## Current notice index

| Component | License and notice | Distribution handling |
|---|---|---|
| Flutter / Dart runtime | BSD-3-Clause; copyright retained for the Flutter and Dart authors | Flutter's generated runtime notice bundle remains in each application package |
| `crypto` 3.0.7 | BSD-3-Clause; Copyright 2015, the Dart project authors | Resolved package license is covered by the dependency audit and generated notices |
| `sqlite3` 3.5.1 | MIT; Copyright 2020 Simon Binder | Package license is retained; SQLite itself is dedicated to the public domain |
| `plugin_platform_interface` 2.1.8 | BSD-3-Clause; Copyright 2013 The Flutter Authors | Resolved package license is covered by the dependency audit and generated notices |
| `pdfrx` 2.4.7 | MIT; Copyright 2018 Takashi Kawasaki | Package license is retained with the resolved dependency notices |
| PDFium Chromium/7811 | PDFium BSD-style license and bundled third-party terms | Windows packaging verifies the pinned archive/DLL hashes and copies the top-level license plus all 15 bundled notice files beside the application |

## Binary provenance

- SQLite native files come only from the pinned `simolus3/sqlite3.dart` 3.5.1 release and are SHA-256 verified before build hooks run.
- PDFium comes only from the pinned `bblanchon/pdfium-binaries` Chromium/7811 release and is SHA-256 verified before packaging.
- No third-party source is currently copied into the PickLogic source tree; packages are imported and native libraries are linked or bundled with provenance.

Exact URLs and hashes are maintained in `tools/sqlite_native_asset.dart` and `tools/pdfium_artifact.dart`. Size decisions are in `DEPENDENCY_BUDGET.md`; the resolved graph is locked in `pubspec.lock` and audited in CI.
