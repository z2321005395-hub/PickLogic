import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:picklogic_core_models/picklogic_core_models.dart';

final class SyntheticFixtureSet {
  const SyntheticFixtureSet();

  Future<List<File>> writeTo(Directory root) async {
    if (await root.exists() && !await root.list().isEmpty) {
      throw StateError('Fixture output directory must be empty.');
    }
    await root.create(recursive: true);
    final files = <File>[];

    Future<File> writeText(String relative, String content) async {
      final file = File('${root.path}${Platform.pathSeparator}$relative');
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      files.add(file);
      return file;
    }

    Future<File> writeBytes(String relative, List<int> bytes) async {
      final file = File('${root.path}${Platform.pathSeparator}$relative');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      files.add(file);
      return file;
    }

    await writeText(
      'documents/synthetic_notes.txt',
      'PickLogic synthetic document. No user data.\n',
    );
    await writeText(
      'documents/synthetic_table.csv',
      'sample,value\nalpha,1\nbeta,2\n',
    );
    await writeText(
      'documents/synthetic_slides.pptx.placeholder',
      'Synthetic presentation placeholder.\n',
    );
    await writeBytes(
      'documents/synthetic_paper.pdf',
      _minimalPdf('Synthetic PickLogic paper', 'Local-first fixture document.'),
    );

    final pixel = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await writeBytes('images/exact_duplicate_a.png', pixel);
    await writeBytes('images/exact_duplicate_b.png', pixel);
    await writeText(
      'images/near_duplicate.svg',
      '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'
          '<rect width="8" height="8" fill="#315c70"/></svg>',
    );
    for (var index = 1; index <= 3; index++) {
      await writeText(
        'screenshots/Screenshot_2026-01-01_12000$index.svg',
        '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="160">'
            '<text x="4" y="20">Synthetic screenshot $index</text></svg>',
      );
    }
    await writeBytes('synthetic_archive.zip', <int>[
      0x50,
      0x4b,
      0x05,
      0x06,
      ...List<int>.filled(18, 0),
    ]);
    await writeText(
      '.synthetic_hidden/info.txt',
      'Synthetic hidden-directory fixture.\n',
    );
    await writeText(
      'simulated_app_residual/cache.tmp',
      'Synthetic cache-like data. Review only.\n',
    );
    await writeText(
      'simulated_system_protected/system_component.dat',
      'Synthetic protected-system fixture. Never delete.\n',
    );
    return List<File>.unmodifiable(files);
  }

  List<FileRecord> records() {
    FileRecord record({
      required String id,
      required String name,
      required String extension,
      required int size,
      required VirtualCategory category,
      bool hidden = false,
      bool system = false,
      bool protected = false,
      List<String> tags = const [],
      String? sha256,
    }) => FileRecord(
      id: id,
      locator: FileLocator(
        value: 'synthetic://fixtures/$id',
        sourceKind: SourceKind.synthetic,
        platform: PickLogicPlatform.synthetic,
      ),
      displayName: name,
      extension: extension,
      mimeType: extension == 'pdf' ? 'application/pdf' : '',
      sizeBytes: size,
      createdAt: DateTime.utc(2026, 1, 1),
      modifiedAt: DateTime.utc(2026, 1, 2),
      parentLocator: null,
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
      isHidden: hidden,
      isSystem: system,
      isAccessible: true,
      isProtected: protected,
      category: category,
      tags: tags,
      hashState: sha256 == null ? HashState.notRequested : HashState.complete,
      sha256: sha256,
      ocrState: OcrState.notRequested,
    );

    return [
      record(
        id: 'notes',
        name: 'synthetic_notes.txt',
        extension: 'txt',
        size: 42,
        category: VirtualCategory.documents,
      ),
      record(
        id: 'paper',
        name: 'synthetic_paper.pdf',
        extension: 'pdf',
        size: 512,
        category: VirtualCategory.academicPapers,
        tags: const ['academic-paper'],
      ),
      record(
        id: 'dup-a',
        name: 'exact_duplicate_a.png',
        extension: 'png',
        size: 68,
        category: VirtualCategory.images,
        sha256: 'synthetic-identical-digest',
      ),
      record(
        id: 'dup-b',
        name: 'exact_duplicate_b.png',
        extension: 'png',
        size: 68,
        category: VirtualCategory.images,
        sha256: 'synthetic-identical-digest',
      ),
      record(
        id: 'protected',
        name: 'system_component.dat',
        extension: 'dat',
        size: 48,
        category: VirtualCategory.unknown,
        system: true,
        protected: true,
      ),
    ];
  }

  Uint8List _minimalPdf(String title, String body) {
    final escapedBody = body
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    final content = 'BT /F1 14 Tf 72 720 Td ($escapedBody) Tj ET';
    final objects = <String>[
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n',
      '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
      '5 0 obj\n<< /Length ${utf8.encode(content).length} >>\nstream\n'
          '$content\nendstream\nendobj\n',
      '6 0 obj\n<< /Title (${title.replaceAll('(', '').replaceAll(')', '')}) '
          '/Producer (PickLogic synthetic fixture) >>\nendobj\n',
    ];
    final output = BytesBuilder();
    output.add(utf8.encode('%PDF-1.4\n'));
    final offsets = <int>[];
    for (final object in objects) {
      offsets.add(output.length);
      output.add(utf8.encode(object));
    }
    final xrefOffset = output.length;
    output.add(utf8.encode('xref\n0 ${objects.length + 1}\n'));
    output.add(utf8.encode('0000000000 65535 f \n'));
    for (final offset in offsets) {
      output.add(
        utf8.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'),
      );
    }
    output.add(
      utf8.encode(
        'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R /Info 6 0 R >>\n'
        'startxref\n$xrefOffset\n%%EOF\n',
      ),
    );
    return output.takeBytes();
  }
}
