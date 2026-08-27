# ADR 0008: Local literature catalog and reading state

Status: Accepted

## Decision

PickLogic Pro implements mature local literature workflows without copying proprietary code, artwork, branding, or pixel layouts from Zotero, EndNote, ReadCube Papers, or 小绿鲸.

- A library entry may be reference-only or may link to one local PDF plus supplemental local attachments.
- Regular/nested collections, smart filters, tags, ratings, stars, catalog trash, and high-confidence duplicate merging are app-owned SQLite state. They do not move or delete source files.
- PDF highlights, underlines, strikethroughs, and notes use page-coordinate overlays stored outside the source PDF.
- Explicit page/document translations and terminology persist locally. Configured online providers receive bounded extracted text, never PDF bytes.
- BibTeX and RIS exchange reuse `petit_bibtex` 6.2.0 (MIT) for BibTeX parsing. Six compact local bibliography styles provide predictable offline copy and RTF output.
- Windows exposes plain text plus RTF on the clipboard for low-friction paste into Word. This is not a live Cite While You Write field or a Word add-in.

Automatic online metadata retrieval is excluded from this change at the maintainer's request. A complete CSL processor, live Word fields, shared libraries, sync, related-paper discovery, and PDF source rewriting remain separate audited decisions.

## Compatibility

All catalog fields are optional on older JSON rows and receive safe defaults. SQLite changes create new tables or add one annotation-geometry column. Existing `LiteratureRecord` data and source PDF bytes are unchanged.

## Consequences

The useful reading and organization state remains local and portable while the product avoids a JavaScript runtime, AGPL citation engine, cloud account, or proprietary binary. Citation-style coverage is intentionally bounded and must not be advertised as complete CSL conformance.
