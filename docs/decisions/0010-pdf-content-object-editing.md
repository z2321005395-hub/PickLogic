# ADR 0010: PDF Content Object Editing

Status: Accepted — 2026-08-28

## Context

PickLogic Pro already uses the audited `pdfrx 2.4.7` / PDFium runtime for local reading, search, selection, page assembly, and annotation export. Users also need direct text and image editing comparable to the core object-editing workflow in mature PDF editors. Adding a second PDF SDK would increase size, licensing, packaging, and maintenance cost.

## Decision

- Reuse the existing PDFium page-object API; add no dependency or binary.
- Inspect only top-level text and image objects on the selected page.
- Represent edits as an immutable `PdfContentEditPlan` containing source object index, source/target bounds, replacement content, rotation, and deletion state.
- Support text replacement, new text, image replacement/addition, move, resize, rotate, delete, undo, and redo.
- Decode user-selected images through Flutter with a 32 MiB encoded limit, 4096 px dimension limit, and 16 Mi-pixel decoded limit.
- Apply edits to an in-memory document immediately before export, regenerate the changed page content, and save only to a new non-existing PDF.
- Keep page organization and annotation embedding in the same source-preserving export pipeline.
- Validate the packaged Windows binary with a synthetic-only smoke that replaces text, inserts an image, reopens the result, and confirms the source bytes were unchanged.

## Safety and compatibility

This is an additive Pro contract. Existing page-edit callers omit `contentEdits` and retain prior behavior. No existing serialized `LiteratureRecord` or annotation state changes. Real source PDFs remain read-only and existing destinations are never overwritten.

## Limits

The first implementation does not claim paragraph reflow, OCR reconstruction, outlined-text editing, nested form-object editing, complex table reconstruction, AcroForm authoring, signing, certified redaction, or high-fidelity conversion. New text uses a PDF standard font; complex CJK font embedding may fail explicitly instead of silently substituting glyphs.

## Consequences

Pro gains a usable object editor without another runtime dependency or measurable package-size jump. PDFium's top-level object model is narrower than a full commercial editing engine, so unsupported pages remain readable and their limits are shown in the editor rather than misrepresented as editable.
