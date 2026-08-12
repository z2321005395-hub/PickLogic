import 'dart:convert';

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
    expect(
      detector.groupExact([record('a', 'x'), record('b', 'x')]),
      hasLength(1),
    );
    expect(detector.groupExact([record('a', 'x'), record('b', 'y')]), isEmpty);
  });
}
