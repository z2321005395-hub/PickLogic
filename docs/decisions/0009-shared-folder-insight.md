# ADR 0009: Shared cross-platform Folder Insight

Status: Accepted

## Context

Mobile Storage Insight previously hid directory authorization below storage totals and repeatedly paged the same SAF directory while deriving folder summaries. Desktop had storage totals and generic selected-folder text but no equivalent evidence-based traversal. PickLogic needs one product-level explanation model without assuming that Windows paths and Android content URIs are interchangeable.

## Decision

- `insight_engine` owns shared folder observations, roles, evidence, explanation rules, and cancellable breadth-first traversal.
- Platform adapters own enumeration. Android returns one direct-child aggregate per user-authorized SAF directory; Windows streams one user-selected directory and returns the same aggregate shape.
- Each folder explanation separates observed facts, deterministic rule inference, confidence, recommendation, and platform limitations.
- Unknown remains `UNKNOWN` and never implies junk, safe deletion, or permission to mutate.
- Mobile shows authorization before aggregate storage cards and streams results as folders finish. Desktop Standard and Pro use the same Storage-page workflow and contextual selected-folder explanation.
- Traversal reads names and metadata only. It does not read file bodies, hash, OCR, move, rename, delete, bypass scoped storage, or inspect Android private app data.

## Compatibility

The shared types and Android summary method are additive. Existing `FileRecord`, `InsightRecord`, MediaStore pagination, SAF browsing, and serialization contracts are unchanged. Platform locators remain opaque strings interpreted only by their adapter.

## Consequences

Both clients present consistent folder explanations while retaining platform-specific access rules. A complete authorized tree may still take time, but each directory is enumerated once, progress is visible, cancellation is supported, and completed results remain usable during the scan.
