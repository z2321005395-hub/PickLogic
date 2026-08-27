import 'dart:convert';
import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart'
    hide TranslationProvider;
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'extracts normalized DOI candidates and removes sentence punctuation',
    () {
      final candidates = const DoiExtractor().candidates(
        'See https://doi.org/10.1000/ABC.123, and 10.1000/abc.123.',
      );
      expect(candidates, ['10.1000/abc.123']);
    },
  );

  test('creates a preview name without invalid Windows characters', () {
    const record = LiteratureRecord(
      id: 'lit-1',
      localFileId: 'file-1',
      title: 'A title: with / invalid * characters',
      authors: ['Researcher'],
      journal: 'Journal: of / Synthetic * Evidence',
      year: 2026,
    );
    final preview = const LiteratureNaming().previewFileName(record);
    expect(preview, endsWith('.pdf'));
    expect(preview, isNot(contains(':')));
    expect(preview, isNot(contains('/')));
  });

  test('rename proposal remains preview-only and reports safe adjustments', () {
    const record = LiteratureRecord(
      id: 'lit-rename',
      localFileId: 'file-rename',
      title: 'Synthetic: paper',
      authors: ['Researcher'],
      journal: 'Synthetic Journal',
      year: 2026,
    );
    final preview = const LiteratureNaming().previewRename(
      record: record,
      originalFileName: 'download.pdf',
    );
    expect(
      preview.proposedFileName,
      '2026 - Synthetic Journal - Synthetic_ paper.pdf',
    );
    expect(preview.changed, isTrue);
    expect(preview.isPreviewOnly, isTrue);
    expect(preview.warnings.last, contains('no file operation'));
  });

  test('reading progress updates preserve literature metadata', () {
    const record = LiteratureRecord(
      id: 'lit-progress',
      localFileId: 'file-progress',
      doi: '10.5555/synthetic',
      title: 'Synthetic progress paper',
      authors: ['Researcher'],
      journal: 'Synthetic Journal',
      year: 2026,
      metadataConfidence: 0.8,
    );
    final openedAt = DateTime.utc(2026, 8, 12, 8);
    final updated = const LiteratureReadingTracker().recordPage(
      record,
      currentPage: 3,
      totalPages: 12,
      openedAt: openedAt,
    );
    expect(updated.readingProgress, 0.25);
    expect(updated.lastOpenedAt, openedAt);
    expect(updated.doi, record.doi);
    expect(updated.title, record.title);
    expect(updated.metadataConfidence, record.metadataConfidence);
  });

  test('long Unicode naming preview truncates without a broken character', () {
    final title = List.filled(190, '🧪').join();
    final preview = const LiteratureNaming().previewRename(
      record: LiteratureRecord(
        id: 'lit-long-name',
        localFileId: 'file-long-name',
        title: title,
        authors: const ['研究者'],
        journal: '合成期刊',
        year: 2026,
      ),
      originalFileName: 'download.pdf',
    );
    expect(preview.proposedFileName.length, lessThanOrEqualTo(180));
    expect(preview.proposedFileName.runes, isNot(contains(0xFFFD)));
    expect(preview.proposedFileName, endsWith('.pdf'));
    expect(
      preview.warnings,
      contains('The preview was shortened to 180 characters.'),
    );
    expect(
      preview.warnings,
      isNot(contains('Windows-invalid characters were replaced.')),
    );
  });

  test('naming keeps year-journal-title order with explicit fallbacks', () {
    const record = LiteratureRecord(
      id: 'lit-missing-name-metadata',
      localFileId: 'file-missing-name-metadata',
      title: '',
    );
    final preview = const LiteratureNaming().previewRename(
      record: record,
      originalFileName: 'download.pdf',
    );
    expect(
      preview.proposedFileName,
      'n.d. - Unknown journal - Untitled paper.pdf',
    );
    expect(preview.warnings, contains('Publication year is missing.'));
    expect(preview.warnings, contains('Journal metadata is missing.'));
    expect(preview.warnings, contains('Title metadata is missing.'));
    expect(preview.warnings, isNot(contains('Author metadata is missing.')));
  });

  test(
    'PDF edit plan safely reorders, rotates, duplicates, and removes pages',
    () {
      var plan = PdfEditPlan.identity(3);
      expect(plan.changed, isFalse);

      plan = plan.move(2, 0).rotate(0, clockwise: true).duplicate(1).remove(2);

      expect(
        plan.pages.map(
          (page) => (page.sourcePageNumber, page.clockwiseQuarterTurns),
        ),
        [(3, 1), (1, 0), (2, 0)],
      );
      expect(plan.changed, isTrue);
      expect(plan.rotatedPageCount, 1);
      expect(plan.duplicatedPageCount, 0);
      expect(plan.removedPageCount, 0);
    },
  );

  test('PDF edit plan refuses to remove its final page', () {
    final plan = PdfEditPlan.identity(1);
    expect(() => plan.remove(0), throwsStateError);
  });

  test('bounded PDF probe reads only small head and tail ranges', () async {
    final bytes = List<int>.filled(4096, 0x20);
    final header = latin1.encode(
      r'%PDF-1.7 /Title (Bounded \(synthetic\) metadata) '
      r'/Author (Ada Lovelace; Alan Turing) /Keywords (local; private) '
      r'/CreationDate (D:20260812090000Z)',
    );
    bytes.setRange(0, header.length, header);
    final trailer = latin1.encode(
      r'/Subject (Synthetic study) DOI 10.5555/PICKLOGIC.SYNTHETIC %%EOF',
    );
    final trailerOffset = bytes.length - trailer.length;
    bytes.setRange(trailerOffset, bytes.length, trailer);
    final source = _RecordingPdfSource(bytes);

    final probe = await const BoundedPdfMetadataReader(
      headWindowBytes: 256,
      tailWindowBytes: 256,
      maxReadBytes: 32,
      maxTotalBytes: 512,
    ).read(source);

    expect(probe.hasPdfHeader, isTrue);
    expect(probe.title, 'Bounded (synthetic) metadata');
    expect(probe.authors, ['Ada Lovelace', 'Alan Turing']);
    expect(probe.keywords, ['local', 'private']);
    expect(probe.subject, 'Synthetic study');
    expect(probe.doiCandidates, ['10.5555/picklogic.synthetic']);
    expect(probe.year, 2026);
    expect(probe.bytesRead, 512);
    expect(probe.wasTruncated, isTrue);
    expect(source.requests, isNotEmpty);
    expect(source.requests.every((request) => request.length <= 32), isTrue);
    expect(
      source.requests.any((request) => request.length == bytes.length),
      isFalse,
    );
    expect(
      source.requests.every(
        (request) => request.offset < 256 || request.offset >= 3840,
      ),
      isTrue,
    );
  });

  test(
    'small PDFs are split instead of requested in one whole-file read',
    () async {
      final bytes = latin1.encode(
        '%PDF-1.7 ${List.filled(96, 'x').join()} %%EOF',
      );
      final source = _RecordingPdfSource(bytes);
      final probe = await const BoundedPdfMetadataReader(
        headWindowBytes: 256,
        tailWindowBytes: 256,
        maxReadBytes: 256,
        maxTotalBytes: 512,
      ).read(source);

      expect(probe.hasPdfHeader, isTrue);
      expect(source.requests.length, greaterThan(1));
      expect(
        source.requests.any((request) => request.length == bytes.length),
        isFalse,
      );
    },
  );

  test('local PDF source finishes each bounded read before closing', () async {
    final directory = await Directory.systemTemp.createTemp(
      'picklogic-local-pdf-source-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}fixture.pdf');
    final bytes = List<int>.filled(12 * 1024, 0x20);
    final header = latin1.encode(
      r'%PDF-1.7 /Title (Local source fixture) '
      r'/Author (Synthetic Author) /CreationDate (D:20260828010000Z)',
    );
    bytes.setRange(0, header.length, header);
    final trailer = latin1.encode(r'DOI 10.5555/picklogic.local %%EOF');
    bytes.setRange(bytes.length - trailer.length, bytes.length, trailer);
    await file.writeAsBytes(bytes, flush: true);

    final probe = await const BoundedPdfMetadataReader().read(
      FilePdfByteSource(file.path),
    );

    expect(probe.hasPdfHeader, isTrue);
    expect(probe.title, 'Local source fixture');
    expect(probe.authors, ['Synthetic Author']);
    expect(probe.year, 2026);
    expect(probe.doiCandidates, ['10.5555/picklogic.local']);
    expect(probe.readWindows.length, greaterThan(1));
  });

  test(
    'PDF header may follow a short prefix and an unreadable tail is nonfatal',
    () async {
      final source = _TailFailingPdfSource();
      final probe = await const BoundedPdfMetadataReader().read(source);

      expect(probe.hasPdfHeader, isTrue);
      expect(probe.title, 'Prefix-safe PDF');
      expect(
        probe.limitations,
        contains(
          'The tail metadata window could not be read; filename fallback remains available.',
        ),
      );
    },
  );

  test('library entry preserves metadata and exact reading page in JSON', () {
    final entry =
        LiteratureLibraryEntry.fromProbe(
          localPath: r'X:\synthetic\fixture.pdf',
          fileName: 'fixture.pdf',
          probe: const PdfMetadataProbe(
            hasPdfHeader: true,
            totalBytes: 1024,
            bytesRead: 512,
            wasTruncated: true,
            readWindows: [],
            title: 'Synthetic fixture',
            authors: ['Example Author'],
            doiCandidates: ['10.5555/synthetic.fixture'],
            year: 2026,
          ),
          addedAt: DateTime.utc(2026, 8, 13, 9),
        ).recordPosition(
          currentPage: 7,
          totalPages: 20,
          openedAt: DateTime.utc(2026, 8, 13, 10),
        );

    final restored = LiteratureLibraryEntry.fromJson(entry.toJson());

    expect(restored.id, entry.id);
    expect(restored.record.title, 'Synthetic fixture');
    expect(restored.record.authors, ['Example Author']);
    expect(restored.record.doi, '10.5555/synthetic.fixture');
    expect(restored.record.year, 2026);
    expect(restored.currentPage, 7);
    expect(restored.totalPages, 20);
    expect(restored.record.readingProgress, 0.35);
    expect(restored.localPath, r'X:\synthetic\fixture.pdf');
  });

  test(
    'JSON library store round-trips only app-owned synthetic state',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'picklogic-literature-synthetic-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = JsonFileLiteratureLibraryStore(
        '${root.path}${Platform.pathSeparator}catalog.json',
      );
      final entry = LiteratureLibraryEntry(
        record: const LiteratureRecord(
          id: 'lit-synthetic',
          localFileId: 'local-lit-synthetic',
          title: 'Synthetic persisted paper',
          authors: ['Test Author'],
          readingProgress: 0.5,
          metadataConfidence: 0.75,
        ),
        localPath: r'X:\synthetic\persisted.pdf',
        fileName: 'persisted.pdf',
        addedAt: DateTime.utc(2026, 8, 13),
        currentPage: 5,
        totalPages: 10,
      );

      expect(await store.load(), isEmpty);
      await store.save([entry]);
      final restored = await store.load();

      expect(restored, hasLength(1));
      expect(restored.single.fileName, 'persisted.pdf');
      expect(restored.single.currentPage, 5);
      expect(restored.single.record.readingProgress, 0.5);
    },
  );

  test(
    'SQLite library store atomically preserves order and metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'picklogic-literature-sqlite-synthetic-',
      );
      addTearDown(() => root.delete(recursive: true));
      final store = SqliteLiteratureLibraryStore(
        '${root.path}${Platform.pathSeparator}catalog.db',
      );
      final first = LiteratureLibraryEntry(
        record: const LiteratureRecord(
          id: 'lit-first',
          localFileId: 'local-lit-first',
          title: 'First synthetic paper',
          metadataConfidence: 0.5,
        ),
        localPath: r'X:\synthetic\first.pdf',
        fileName: 'first.pdf',
        addedAt: DateTime.utc(2026, 8, 14),
      );
      final second = LiteratureLibraryEntry(
        record: const LiteratureRecord(
          id: 'lit-second',
          localFileId: 'local-lit-second',
          title: 'Second synthetic paper',
          metadataConfidence: 0.5,
        ),
        localPath: r'X:\synthetic\second.pdf',
        fileName: 'second.pdf',
        addedAt: DateTime.utc(2026, 8, 14),
      );

      expect(await store.load(), isEmpty);
      await store.save([second, first]);
      var restored = await store.load();
      expect(restored.map((entry) => entry.id), ['lit-second', 'lit-first']);

      final editedRecord = LiteratureRecord(
        id: first.record.id,
        localFileId: first.record.localFileId,
        title: 'Manually corrected title',
        authors: const ['Test Author'],
        journal: 'Synthetic Journal',
        year: 2026,
        metadataSource: 'manual local edit',
        metadataConfidence: 1,
      );
      await store.save([first.replaceRecord(editedRecord)]);
      restored = await store.load();

      expect(restored, hasLength(1));
      expect(restored.single.record.title, 'Manually corrected title');
      expect(restored.single.record.journal, 'Synthetic Journal');
      expect(restored.single.localPath, first.localPath);
    },
  );

  test('citation export produces portable BibTeX, RIS, and quick text', () {
    const record = LiteratureRecord(
      id: 'lit-citation',
      localFileId: 'file-citation',
      doi: '10.5555/picklogic.citation',
      title: 'A local-first citation workflow',
      authors: ['Ada Lovelace', 'Alan Turing'],
      journal: 'Synthetic Research',
      year: 2026,
      volume: '12',
      issue: '3',
      pages: '45-51',
      keywords: ['local-first', 'citation'],
    );
    const formatter = LiteratureCitationFormatter();

    final bibtex = formatter.toBibTeX(record);
    final ris = formatter.toRis(record);
    final plain = formatter.toPlainText(record);

    expect(bibtex, startsWith('@article{Lovelace2026A,'));
    expect(bibtex, contains('doi = {10.5555/picklogic.citation}'));
    expect(ris, contains('AU  - Ada Lovelace'));
    expect(ris, contains('SP  - 45\nEP  - 51'));
    expect(ris, endsWith('ER  -\n'));
    expect(plain, contains('Ada Lovelace & Alan Turing'));
    expect(formatter.inText(record), '(Lovelace & Turing, 2026)');
  });

  test('BibTeX and RIS imports create durable reference-only entries', () {
    const importer = LiteratureCitationImporter();
    final importedAt = DateTime.utc(2026, 8, 27, 12);
    final bibtex = importer.parse(
      r'''
@article{local2026,
  title = {A {Nested} Local-First Study},
  author = {Lovelace, Ada and Alan Turing},
  journal = {Synthetic Research},
  year = {2026},
  doi = {https://doi.org/10.5555/PICKLOGIC.IMPORT},
  keywords = {local-first; citation}
}
''',
      format: CitationImportFormat.bibtex,
      importedAt: importedAt,
      sourceFileName: 'library.bib',
    );

    expect(bibtex.warnings, isEmpty);
    expect(bibtex.entries, hasLength(1));
    expect(bibtex.entries.single.hasLocalPdf, isFalse);
    expect(bibtex.entries.single.record.title, 'A {Nested} Local-First Study');
    expect(bibtex.entries.single.record.authors, [
      'Lovelace, Ada',
      'Alan Turing',
    ]);
    expect(bibtex.entries.single.record.doi, '10.5555/picklogic.import');
    expect(bibtex.entries.single.record.keywords, ['local-first', 'citation']);

    final ris = importer.parse(
      '''TY  - JOUR
TI  - Portable reference import
AU  - Example, Alice
AU  - Example, Bob
JO  - Synthetic Journal
PY  - 2025/08/27
SP  - 10
EP  - 18
DO  - doi:10.5555/PICKLOGIC.RIS
ER  -
''',
      format: CitationImportFormat.ris,
      importedAt: importedAt,
      sourceFileName: 'library.ris',
    );

    expect(ris.warnings, isEmpty);
    expect(ris.entries.single.record.authors, [
      'Example, Alice',
      'Example, Bob',
    ]);
    expect(ris.entries.single.record.year, 2025);
    expect(ris.entries.single.record.pages, '10-18');
    expect(ris.entries.single.record.doi, '10.5555/picklogic.ris');
  });

  test('library organization supports smart filters, sorting, and trash', () {
    final first = LiteratureLibraryEntry(
      record: const LiteratureRecord(
        id: 'lit-organize-first',
        localFileId: 'file-organize-first',
        title: 'Local microscopy workflow',
        authors: ['Ada Example'],
        year: 2025,
        tags: ['microscopy', 'methods'],
      ),
      fileName: 'first.pdf',
      addedAt: DateTime.utc(2026, 8, 26),
      rating: 4,
      isStarred: true,
    );
    final second = LiteratureLibraryEntry(
      record: const LiteratureRecord(
        id: 'lit-organize-second',
        localFileId: 'file-organize-second',
        title: 'Different topic',
        authors: ['Bob Example'],
        year: 2026,
        readingProgress: 0.5,
      ),
      fileName: 'second.pdf',
      addedAt: DateTime.utc(2026, 8, 27),
      rating: 5,
    );
    final removed = second.moveToTrash(DateTime.utc(2026, 8, 27, 13));
    final smart = LiteratureCollection(
      id: 'smart-microscopy',
      name: 'Unread microscopy',
      createdAt: DateTime.utc(2026, 8, 27),
      kind: LiteratureCollectionKind.smart,
      query: 'local',
      requiredTags: const ['microscopy'],
      minimumRating: 4,
      unreadOnly: true,
      starredOnly: true,
    );
    const organizer = LiteratureLibraryOrganizer();

    expect(organizer.apply(entries: [first, removed], collection: smart), [
      same(first),
    ]);
    expect(organizer.apply(entries: [first, removed], trash: true), [
      same(removed),
    ]);
    expect(
      organizer
          .apply(
            entries: [first, second],
            sortMode: LiteratureSortMode.yearNewest,
          )
          .map((entry) => entry.id),
      ['lit-organize-second', 'lit-organize-first'],
    );
  });

  test('SQLite collection store preserves hierarchy and smart rules', () async {
    final root = await Directory.systemTemp.createTemp(
      'picklogic-literature-collections-',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = SqliteLiteratureCollectionStore(
      '${root.path}${Platform.pathSeparator}catalog.db',
    );
    final createdAt = DateTime.utc(2026, 8, 27);
    final parent = LiteratureCollection(
      id: 'collection-parent',
      name: 'Project A',
      createdAt: createdAt,
    );
    final child = LiteratureCollection(
      id: 'collection-child',
      name: 'Unread methods',
      parentId: parent.id,
      createdAt: createdAt,
      kind: LiteratureCollectionKind.smart,
      requiredTags: const ['methods'],
      unreadOnly: true,
    );

    await store.save([parent, child]);
    final restored = await store.load();

    expect(restored.map((item) => item.id), [parent.id, child.id]);
    expect(restored.last.parentId, parent.id);
    expect(restored.last.kind, LiteratureCollectionKind.smart);
    expect(restored.last.requiredTags, ['methods']);
    expect(restored.last.unreadOnly, isTrue);
  });

  test('high-confidence duplicates merge metadata without losing PDFs', () {
    final first = LiteratureLibraryEntry(
      record: const LiteratureRecord(
        id: 'lit-duplicate-a',
        localFileId: 'file-duplicate-a',
        doi: '10.5555/duplicate',
        title: 'A duplicate study',
        authors: ['Alice Example'],
        tags: ['reviewed'],
        readingProgress: 0.2,
      ),
      localPath: r'X:\synthetic\a.pdf',
      fileName: 'a.pdf',
      addedAt: DateTime.utc(2026, 8, 25),
      rating: 3,
    );
    final second = LiteratureLibraryEntry(
      record: const LiteratureRecord(
        id: 'lit-duplicate-b',
        localFileId: 'file-duplicate-b',
        doi: '10.5555/DUPLICATE',
        title: 'A duplicate study with a longer corrected title',
        authors: ['Alice Example', 'Bob Example'],
        abstractText: 'A richer abstract.',
        keywords: ['local'],
        readingProgress: 0.8,
      ),
      localPath: r'X:\synthetic\b.pdf',
      fileName: 'b.pdf',
      addedAt: DateTime.utc(2026, 8, 26),
      currentPage: 8,
      totalPages: 10,
      rating: 5,
      isStarred: true,
    );
    const detector = LiteratureReferenceDuplicateDetector();
    final groups = detector.find([first, second]);

    expect(groups, hasLength(1));
    expect(groups.single.reasons, contains('Same DOI'));
    final merged = detector.merge(groups.single, preferredId: first.id);
    expect(merged.id, first.id);
    expect(merged.record.title, second.record.title);
    expect(merged.record.authors, second.record.authors);
    expect(merged.record.tags, ['reviewed']);
    expect(merged.record.keywords, ['local']);
    expect(merged.record.readingProgress, 0.8);
    expect(merged.localPath, first.localPath);
    expect(merged.supplementalPaths, contains(second.localPath));
    expect(merged.rating, 5);
    expect(merged.isStarred, isTrue);
  });

  test('six bundled citation styles produce copyable text and RTF', () {
    const record = LiteratureRecord(
      id: 'lit-style',
      localFileId: 'file-style',
      doi: '10.5555/style',
      title: '拾理 citation styles',
      authors: ['Ada Lovelace', 'Alan Turing'],
      journal: 'Synthetic Research',
      year: 2026,
      volume: '12',
      issue: '3',
      pages: '45-51',
    );
    const formatter = LiteratureBibliographyFormatter();

    for (final style in LiteratureCitationStyle.values) {
      final result = formatter.bibliography([record], style: style);
      expect(result.entries, hasLength(1), reason: style.name);
      expect(result.plainText, contains('citation styles'), reason: style.name);
      expect(result.rtf, startsWith(r'{\rtf1'), reason: style.name);
      expect(result.rtf, contains(r'\u'), reason: style.name);
      expect(
        formatter.formatCitation([record], style: style),
        isNotEmpty,
        reason: style.name,
      );
    }
    expect(
      formatter.formatCitation([
        record,
        record,
      ], style: LiteratureCitationStyle.vancouver),
      '[1,2]',
    );
    expect(
      formatter.formatCitation([
        record,
        record,
      ], style: LiteratureCitationStyle.ieee),
      '[1], [2]',
    );
  });

  test(
    'annotation store preserves page-linked notes without editing PDF',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'picklogic-literature-annotation-',
      );
      addTearDown(() => root.delete(recursive: true));
      final path = '${root.path}${Platform.pathSeparator}catalog.db';
      final store = SqliteLiteratureAnnotationStore(path);
      final createdAt = DateTime.utc(2026, 8, 27, 9);
      final annotation = LiteratureAnnotation(
        id: 'annotation-1',
        literatureId: 'lit-synthetic',
        pageNumber: 4,
        kind: LiteratureAnnotationKind.highlight,
        selectedText: 'Local-first evidence',
        note: 'Use in introduction.',
        colorName: 'yellow',
        createdAt: createdAt,
        updatedAt: createdAt,
        boxes: [
          LiteratureAnnotationBox(
            pageNumber: 4,
            left: 72,
            top: 710,
            right: 240,
            bottom: 696,
          ),
        ],
      );

      await store.upsert(annotation);
      var restored = await store.loadFor('lit-synthetic');
      expect(restored, hasLength(1));
      expect(restored.single.pageNumber, 4);
      expect(restored.single.selectedText, 'Local-first evidence');
      expect(restored.single.boxes, hasLength(1));
      expect(restored.single.boxes.single.left, 72);

      await store.upsert(
        annotation.replaceNote(
          'Use in discussion.',
          createdAt.add(const Duration(minutes: 5)),
        ),
      );
      restored = await store.loadFor('lit-synthetic');
      expect(restored.single.note, 'Use in discussion.');
      expect(restored.single.boxes.single.pageNumber, 4);

      await store.delete(annotation.id);
      expect(await store.loadFor('lit-synthetic'), isEmpty);
    },
  );

  test(
    'explicit page translation is split into bounded provider calls',
    () async {
      final provider = _RecordingTranslationProvider();
      final source = List<String>.generate(
        18,
        (index) => 'Paragraph $index contains synthetic local PDF text.',
      ).join('\n\n');

      final result = await provider.translateExplicitTextInChunks(
        source,
        targetLanguage: 'Simplified Chinese',
        maxChunkCharacters: 500,
        terminology: const {'grain boundary': '晶界'},
      );

      expect(provider.requests.length, greaterThan(1));
      expect(provider.requests.every((value) => value.length <= 500), isTrue);
      expect(result.sourceText, source);
      expect(result.translatedText, contains('translated:'));
      expect(
        provider.terminologyRequests.every(
          (terms) => terms['grain boundary'] == '晶界',
        ),
        isTrue,
      );
    },
  );

  test('SQLite translation memory restores pages and terminology', () async {
    final root = await Directory.systemTemp.createTemp(
      'picklogic-literature-translation-',
    );
    addTearDown(() => root.delete(recursive: true));
    final path = '${root.path}${Platform.pathSeparator}catalog.db';
    final store = SqliteLiteratureTranslationStore(path);
    final updatedAt = DateTime.utc(2026, 8, 27, 14);
    final page = LiteraturePageTranslation(
      literatureId: 'lit-translation',
      pageNumber: 3,
      targetLanguage: 'Simplified Chinese',
      sourceText: 'Grain boundary evidence.',
      translatedText: '晶界证据。',
      providerLabel: 'Synthetic translator',
      updatedAt: updatedAt,
    );
    final term = LiteratureTerminologyEntry(
      id: 'term-grain-boundary',
      sourceTerm: 'grain boundary',
      translatedTerm: '晶界',
      targetLanguage: 'Simplified Chinese',
      updatedAt: updatedAt,
    );

    await store.upsertPage(page);
    await store.upsertTerm(term);
    final restoredPages = await SqliteLiteratureTranslationStore(path)
        .loadPages(
          literatureId: 'lit-translation',
          targetLanguage: 'Simplified Chinese',
        );
    final restoredTerms = await SqliteLiteratureTranslationStore(
      path,
    ).loadTerminology('Simplified Chinese');

    expect(restoredPages, hasLength(1));
    expect(restoredPages.single.sourceText, page.sourceText);
    expect(restoredPages.single.translatedText, page.translatedText);
    expect(restoredPages.single.sourceFingerprint, page.sourceFingerprint);
    expect(restoredTerms, hasLength(1));
    expect(restoredTerms.single.sourceTerm, 'grain boundary');
    expect(restoredTerms.single.translatedTerm, '晶界');

    await store.deletePage(
      literatureId: page.literatureId,
      pageNumber: page.pageNumber,
      targetLanguage: page.targetLanguage,
    );
    await store.deleteTerm(term.id);
    expect(
      await store.loadPages(
        literatureId: page.literatureId,
        targetLanguage: page.targetLanguage,
      ),
      isEmpty,
    );
    expect(await store.loadTerminology(page.targetLanguage), isEmpty);
  });
}

final class _RecordingPdfSource implements PdfByteSource {
  _RecordingPdfSource(this.bytes);

  final List<int> bytes;
  final List<({int offset, int length})> requests = [];

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<List<int>> readRange({
    required int offset,
    required int length,
  }) async {
    requests.add((offset: offset, length: length));
    final end = (offset + length).clamp(0, bytes.length);
    if (offset >= end) return const <int>[];
    return bytes.sublist(offset, end);
  }
}

final class _TailFailingPdfSource implements PdfByteSource {
  final List<int> _head = latin1.encode(
    'synthetic-prefix%PDF-1.7 /Title (Prefix-safe PDF)',
  );

  @override
  Future<int> length() async => 128 * 1024;

  @override
  Future<List<int>> readRange({
    required int offset,
    required int length,
  }) async {
    if (offset >= 64 * 1024) {
      throw const FileSystemException('Synthetic tail read failure');
    }
    if (offset >= _head.length) return List<int>.filled(length, 0x20);
    final end = (offset + length).clamp(0, _head.length);
    final result = List<int>.of(_head.sublist(offset, end));
    if (result.length < length) {
      result.addAll(List<int>.filled(length - result.length, 0x20));
    }
    return result;
  }
}

final class _RecordingTranslationProvider implements TranslationProvider {
  final List<String> requests = [];
  final List<Map<String, String>> terminologyRequests = [];

  @override
  TranslationProviderKind get kind => TranslationProviderKind.openAiCompatible;

  @override
  String get label => 'Synthetic translator';

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async {
    requests.add(selectedText);
    terminologyRequests.add(Map<String, String>.of(terminology));
    return SelectedTextTranslation(
      sourceText: selectedText,
      translatedText: 'translated:$selectedText',
      targetLanguage: targetLanguage,
      providerLabel: label,
    );
  }
}
