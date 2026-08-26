# ADR 0007: Literature workflow benchmarks

Status: Accepted

## Decision

PickLogic Pro uses Zotero, ReadCube Papers, EndNote, and 小绿鲸 as workflow
benchmarks, not as visual or code sources. PickLogic keeps its own UI, local-first
architecture, and read-only source-file boundary.

Repeatedly valued workflows across official documentation and public user
feedback are:

1. fast PDF capture/import with editable metadata;
2. one searchable library with collections or tags;
3. reading, highlighting, notes, and a link back to the source page;
4. reliable full-library and in-document search;
5. portable citation output and low-friction insertion while writing;
6. optional selection, page, and bilingual full-text translation;
7. keyboard-efficient, compact, stable UI.

Repeated complaints are annotation or database lock-in, unreliable sync,
incorrect metadata, weak shortcuts, excessive spacing, poor markup tools, and
basic actions breaking after upgrades. PickLogic therefore prioritizes local
portability and predictable core interactions over cloud accounts or feature
count.

## Implemented direction

- Local SQLite library; source PDFs remain in place and read-only.
- Search across title, author, journal, DOI, filename, keyword, and user tags.
- Manual metadata correction, reading-position persistence, and rename preview.
- App-owned page-linked highlights/notes, stored locally and independently of
  the PDF.
- BibTeX, RIS, quick bibliography text, and in-text citation copy.
- PDF text search, thumbnails, page jump, zoom, selection/copy, and explicit
  selection/current-page/full-document translation with a bilingual pane.
- Translation remains off by default and sends extracted text only after an
  explicit user action; PDF bytes are never uploaded.

Word/LibreOffice dynamic citation fields, automatic online metadata retrieval,
related-paper discovery, shared libraries, and cloud sync are separate future
decisions. They must not block the dependable local reader and library.

## Evidence reviewed

- Zotero collections and tags:
  https://www.zotero.org/support/collections_and_tags/
- Zotero PDF reader, annotations, notes, and page links:
  https://www.zotero.org/support/pdf_reader
- Zotero annotation portability:
  https://www.zotero.org/support/kb/annotations_in_database
- Zotero word-processor citation workflow:
  https://www.zotero.org/support/word_processor_plugin_usage
- ReadCube Papers product and enhanced PDF workflows:
  https://about.readcube.com/
  https://www.papersapp.com/highlights/feature-spotlight-enhanced-pdf/
- EndNote overview and citation/library workflows:
  https://docs.endnote.com/docs/endnote/2025/v1/windows/en/content/01intro/overview.htm
- 小绿鲸 user manual for selection/full translation and bilingual reading:
  https://oss.xljsci.com/userdemo.pdf
- Public user feedback sampled from Zotero forums/Reddit, EndNote Community,
  ReadCube App Store/G2 reviews, and 小绿鲸 App Store reviews on 2026-08-27.

No proprietary code, artwork, text, layout, or branding was copied.
