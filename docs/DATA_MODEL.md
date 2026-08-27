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

Developer Safe Mode now distinguishes an untrusted browse location from one exact root explicitly selected by the user. Mutations remain denied unless a `FileOperator` first canonicalizes both paths, proves they stay inside that root, previews the plan, receives confirmation, and records rollback metadata. This is an additive authorization input; existing callers default to denied.

## InsightRecord

`summary`, `fileType`, `probableOwner`, `probableOrigin`, `whyItExists`, `relatedApplication`, `spaceUsage`, `runningOrActiveState`, `riskLevel`, `confidence`, `evidence`, `recommendedActions`, and `limitations`.

Evidence entries distinguish `fact`, `ruleInference`, `lowConfidenceGuess`, and `platformRestriction`.

## LiteratureRecord

`id`, `localFileId`, optional `doi`, `title`, `authors`, `journal`, optional `year`, `volume`, `issue`, `pages`, `abstract`, `keywords`, `tags`, `readingProgress`, `lastOpenedAt`, `metadataSource`, and `metadataConfidence`.

## LiteratureLibraryEntry

The app-owned catalog entry wraps one `LiteratureRecord` with optional `localPath`, `fileName`, `addedAt`, `collectionIds`, `rating`, `isStarred`, optional `trashedAt`, and `supplementalPaths`. A reference imported from BibTeX/RIS may exist without a local PDF and can attach one later. Trash removes the entry from normal catalog views only; it never deletes the source PDF.

## LiteratureCollection

Regular and smart collections contain `id`, `name`, optional `parentId`, `createdAt`, `kind`, `query`, `requiredTags`, `minimumRating`, `unreadOnly`, and `starredOnly`. Membership and filters are virtual app-owned state and never move source files.

## LiteratureAnnotation

App-owned annotation state contains `id`, `literatureId`, `pageNumber`, `kind`, `selectedText`, `note`, `colorName`, `createdAt`, `updatedAt`, and zero or more page-coordinate `boxes`. Kinds are highlight, underline, strikethrough, and note. It is stored beside the local catalog, redraws over the matching PDF page, and never implies writing into the source PDF.

## LiteratureTranslationState

Explicit page translation stores `literatureId`, `pageNumber`, `targetLanguage`, `sourceText`, `translatedText`, `providerLabel`, `updatedAt`, and a source fingerprint. Terminology entries store source term, target term, and update time. Both remain local; a configured provider receives bounded extracted text and bounded terminology only after the user requests translation.

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
- `TranslationProvider`: translates only text from an explicitly requested selection, current page, or document scope; PDF bytes are never passed to it.
- `OcrProvider`: performs on-demand or bounded queued OCR.
- `IntelligenceProvider`: optional; absence is a supported state.

## Compatibility

Additive optional fields are backward compatible. Renames, removals, required-field additions, enum semantic changes, or locator changes are breaking and require migration notes plus Lead approval.

The Android bridge's additive private-index-path method is not a `FileLocator` and does not alter shared model serialization. It returns only a fixed app-private database location; the shared Dart SQLite implementation retains schema and search ownership.

`AndroidBrowseRoot`, `AndroidBrowseEntry`, and `AndroidBrowsePage` are additive SAF bridge DTOs for user-authorized read-only hierarchy traversal. Files are converted to normal `FileRecord` values with opaque `content://` locators; existing MediaStore contracts are unchanged.

Literature catalog organization, reference-only entries, annotation geometry, local translation memory, citation import, and citation formatting are additive Pro contracts. Existing `LiteratureRecord` serialization is unchanged. Missing optional fields receive safe defaults, SQLite tables migrate additively, and callers that omit the new stores retain the prior read-only reader behavior.
