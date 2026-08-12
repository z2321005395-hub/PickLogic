import 'dart:convert';
import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_duplicate_engine/picklogic_duplicate_engine.dart';
import 'package:test/test.dart';

void main() {
  final detector = Sha256DuplicateDetector();

  test('hashes a stream without requiring a whole file buffer', () async {
    final digest = await detector.hashBytes(
      Stream<List<int>>.fromIterable([
        utf8.encode('Pick'),
        utf8.encode('Logic'),
      ]),
    );
    expect(digest, hasLength(64));
    expect(
      digest,
      await detector.hashBytes(Stream.value(utf8.encode('PickLogic'))),
    );
  });

  test('groups only complete same-size SHA-256 records', () {
    FileRecord record(String id, String hash) => FileRecord(
      id: id,
      locator: FileLocator(
        value: 'synthetic://$id',
        sourceKind: SourceKind.synthetic,
        platform: PickLogicPlatform.synthetic,
      ),
      displayName: '$id.bin',
      extension: 'bin',
      mimeType: 'application/octet-stream',
      sizeBytes: 4,
      createdAt: null,
      modifiedAt: DateTime.utc(2026),
      parentLocator: null,
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
      isHidden: false,
      isSystem: false,
      isAccessible: true,
      isProtected: false,
      category: VirtualCategory.unknown,
      hashState: HashState.complete,
      sha256: hash,
      ocrState: OcrState.notRequested,
    );
    const uppercaseDigest =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    const lowercaseDigest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    expect(
      detector.groupExact([
        record('a', uppercaseDigest),
        record('b', lowercaseDigest),
      ]),
      hasLength(1),
    );
    expect(detector.groupExact([record('a', 'x'), record('b', 'x')]), isEmpty);
  });

  test('hashes only same-size candidates and finds exact files', () async {
    final root = await Directory.systemTemp.createTemp(
      'picklogic-duplicate-test-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<File> write(String name, String content) => File(
      '${root.path}${Platform.pathSeparator}$name',
    ).writeAsString(content);
    final first = await write('first.bin', 'same');
    final second = await write('second.bin', 'same');
    final different = await write('different.bin', 'else');
    final uniqueSize = await write('unique.bin', 'unique-size');

    FileRecord fileRecord(String id, File file) => FileRecord(
      id: id,
      locator: FileLocator(
        value: file.path,
        sourceKind: SourceKind.synthetic,
        platform: PickLogicPlatform.synthetic,
      ),
      displayName: file.uri.pathSegments.last,
      extension: 'bin',
      mimeType: 'application/octet-stream',
      sizeBytes: file.lengthSync(),
      createdAt: null,
      modifiedAt: DateTime.utc(2026),
      parentLocator: null,
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
      isHidden: false,
      isSystem: false,
      isAccessible: true,
      isProtected: false,
      category: VirtualCategory.unknown,
      hashState: HashState.notRequested,
      ocrState: OcrState.notRequested,
    );

    final result = await detector.findExactFiles([
      fileRecord('a', first),
      fileRecord('b', second),
      fileRecord('c', different),
      fileRecord('d', uniqueSize),
    ]);

    expect(result.hashedCount, 3);
    expect(result.failedCount, 0);
    expect(result.groups, hasLength(1));
    expect(result.groups.single.map((record) => record.id), ['a', 'b']);
    expect(
      result.records.singleWhere((record) => record.id == 'd').hashState,
      HashState.notRequested,
    );
  });
}
