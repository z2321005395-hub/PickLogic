# ADR 0004: Pinned native build assets

Status: Accepted

## Context

Flutter native-asset hooks for `pdfrx_engine` and `sqlite3` download fixed release binaries during tests and Windows builds. Hosted CI observed independent transient failures after source analysis had passed. A build retry alone repeats work and still leaves downloads implicit.

## Decision

Before affected tasks, PickLogic resolves the host asset with three bounded attempts, verifies a fixed SHA-256, and writes it to the exact shared cache path expected by the upstream hook. The hook re-verifies SQLite's content hash before reuse.

- PDFium remains pinned to `chromium/7811`; archive and library hashes are in ADR 0003.
- SQLite remains pinned through `sqlite3 3.5.1`.
- Windows x64 source: `sqlite3.x64.windows.dll`, SHA-256 `e6ebc2642223bb419a666e278ae4d2cef586cd528633e1a595270490b51c278a`.
- Linux x64 source: `libsqlite3.x64.linux.so`, SHA-256 `b17729184e5a2818055ecbddd5ed6642521bfe6e56aafa472330e483c0e2e0d2`.
- Source release: https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-3.5.1

No dependency or application code is added. Cached files stay under ignored build/temp directories. A mismatch fails closed and is never packaged as trusted output.

## Consequences

CI becomes less sensitive to native-hook network timing while retaining upstream behavior and license terms. Windows builds keep one outer retry for unrelated transient tool failures. Android continues to use Flutter's target-specific build path; the host-x64 prefetch is not incorrectly substituted for Android binaries.
