# Shared Data and Interface Contract

Status: Bootstrap contract. Add fields only for an implemented use case.

## Locator

`FileLocator` is an opaque platform locator with `value`, `sourceKind`, and `platform`. Windows paths and Android content URIs are never treated as interchangeable.

## FileRecord

`id`, `locator`, `displayName`, `extension`, `mimeType`, `sizeBytes`, `createdAt`, `modifiedAt`, `parentLocator`, `sourceKind`, `platform`, `isHidden`, `isSystem`, `isAccessible`, `isProtected`, `category`, `tags`, `hashState`, `sha256`, optional `perceptualHash`, and `ocrState`.

## VirtualCategory

Documents, Spreadsheets, Presentations, PDF, Images, Videos, Audio, Archives, Installers, Code, Academic Papers, Screenshots, Downloads, Duplicates, Large Files, Unknown. Categories are virtual and never imply moving a file.

## OperationPlan

`operationId`, `operationType`, `source`, optional `destination`, `preview`, `warnings`, `rollbackMetadata`, and `status`.

Required transition:

`planned -> previewed -> confirmed -> executing -> completed -> undone`

Failure and cancellation are explicit terminal states. UI cannot skip confirmation.

## InsightRecord

`summary`, `fileType`, `probableOwner`, `probableOrigin`, `whyItExists`, `relatedApplication`, `spaceUsage`, `runningOrActiveState`, `riskLevel`, `confidence`, `evidence`, `recommendedActions`, and `limitations`.

Evidence entries distinguish `fact`, `ruleInference`, `lowConfidenceGuess`, and `platformRestriction`.

## LiteratureRecord

`id`, `localFileId`, optional `doi`, `title`, `authors`, `journal`, optional `year`, `volume`, `issue`, `pages`, `abstract`, `keywords`, `tags`, `readingProgress`, `lastOpenedAt`, `metadataSource`, and `metadataConfidence`.

## ScreenshotGroup

`groupId`, `sourceHint`, `timeRange`, `memberIds`, `duplicateConfidence`, `contentHint`, `ocrState`, `reviewState`, and `protectedCount`.

## StorageBreakdown

`category`, `bytes`, `accessibleBytes`, `estimatedBytes`, `confidence`, `evidence`, `canInspect`, `canClean`, and `systemRestriction`.

## Interfaces

- `FileScanner`: streams bounded scan batches and resumable cursors.
- `FileOperator`: previews and executes confirmed plans; never accepts raw UI requests.
- `PreviewProvider`: returns bounded, cancellable preview resources.
- `SearchIndexer`: upserts/removes records and queries local search state.
- `DuplicateDetector`: streams SHA-256 work and exact duplicate groups.
- `ClassificationEngine`: applies deterministic and user rules.
- `InsightEngine`: creates structured, evidence-bearing explanations.
- `StorageAnalyzer`: reports accessible, estimated, and restricted storage separately.
- `LiteratureMetadataProvider`: resolves identifiers without uploading a document.
- `TranslationProvider`: translates only explicit text selections.
- `OcrProvider`: performs on-demand or bounded queued OCR.
- `IntelligenceProvider`: optional; absence is a supported state.

## Compatibility

Additive optional fields are backward compatible. Renames, removals, required-field additions, enum semantic changes, or locator changes are breaking and require migration notes plus Lead approval.

The Android bridge's additive private-index-path method is not a `FileLocator` and does not alter shared model serialization. It returns only a fixed app-private database location; the shared Dart SQLite implementation retains schema and search ownership.
