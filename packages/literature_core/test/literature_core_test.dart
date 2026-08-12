import 'dart:convert';

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
      r'/Author (Ada Lovelace; Alan Turing) /Keywords (local; private)',
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
