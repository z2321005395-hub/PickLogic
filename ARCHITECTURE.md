# Architecture

## Shape

PickLogic uses a Flutter/Dart workspace. Pure Dart packages hold stable models and core algorithms. Flutter apps compose those packages. Narrow platform bridges expose Windows and Android capabilities without leaking path assumptions into the core.

```text
apps/desktop (Standard + Pro entrypoints) ----+
                                               +--> packages/* --> core_models
apps/mobile ----------------------------------+
      |                                            |
      +--> platform/android_bridge                 +--> provider interfaces
apps/desktop --> platform/windows_bridge
```

## Target composition

- Standard: core models, index, search, duplicate detection, classification, preview, operation planning, Insight, shared UI, Windows bridge.
- Pro: Standard plus literature, research, and system-insight packages. It is a feature composition, not a copied application.
- Mobile: shared core plus Android bridge and mobile UI for files, screenshots, photos, and storage.

## Data flow

1. Platform scanner yields bounded batches of locators and metadata.
2. Index writer commits batches to local SQLite and records a resumable scan cursor.
3. Classifiers and exact duplicate detection enrich indexed records in background tasks.
4. Search queries the local index; thumbnails and previews load on demand through bounded caches.
5. Insight combines facts, explicit rules, confidence, evidence, limitations, and recommended actions.
6. Any mutation becomes an `OperationPlan`; execution is unavailable in Developer Safe Mode except for an explicitly approved synthetic/test root.

## Constraints

- No full-file loading during scans; hashes stream bytes.
- UI renders usable state before a complete scan.
- Work is cancellable and progress reports measured counts, not simulated percentages.
- Providers for OCR, translation, metadata, and intelligence may be absent.
- Online providers never receive complete files.

Canonical contracts: `docs/DATA_MODEL.md`.
Decisions: `docs/decisions/`.
