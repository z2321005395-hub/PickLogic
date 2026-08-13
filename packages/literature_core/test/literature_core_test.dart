import 'dart:convert';
import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
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
      year: 2026,
    );
    final preview = const LiteratureNaming().previewRename(
      record: record,
      originalFileName: 'download.pdf',
    );
    expect(
      preview.proposedFileName,
      'Researcher (2026) - Synthetic_ paper.pdf',
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
