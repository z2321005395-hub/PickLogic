import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_file_index/picklogic_file_index.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late FileLocator locator;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('picklogic-scan-test-');
    locator = FileLocator(
      value: root.path,
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
    );
    await File(
      '${root.path}${Platform.pathSeparator}one.txt',
    ).writeAsString('1');
    await Directory('${root.path}${Platform.pathSeparator}nested').create();
    await File(
      '${root.path}${Platform.pathSeparator}nested${Platform.pathSeparator}two.pdf',
    ).writeAsBytes(const [1, 2]);
    await File(
      '${root.path}${Platform.pathSeparator}.hidden',
    ).writeAsString('3');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'streams bounded metadata batches without reading file bodies',
    () async {
      final batches = await StreamingDirectoryScanner()
          .scan(ScanRequest(root: locator, batchSize: 2))
          .toList();
      final records = batches.expand((batch) => batch.records).toList();

      expect(records, hasLength(3));
      expect(batches.first.records, hasLength(2));
      expect(batches.last.isComplete, isTrue);
      expect(
        records.singleWhere((record) => record.extension == 'pdf').sizeBytes,
        2,
      );
      expect(
        records
            .singleWhere((record) => record.displayName == '.hidden')
            .isHidden,
        isTrue,
      );
    },
  );

  test('cancellation stops after the current bounded batch', () async {
    final scanner = StreamingDirectoryScanner();
    final batches = <ScanBatch>[];
    await for (final batch in scanner.scan(
      ScanRequest(root: locator, batchSize: 1),
    )) {
      batches.add(batch);
      await scanner.cancel();
    }

    expect(batches, hasLength(1));
    expect(batches.single.isComplete, isFalse);
  });

  test('uses stable path order and resumes after a removed cursor', () async {
    final scanner = StreamingDirectoryScanner();
    final firstPass = await scanner
        .scan(ScanRequest(root: locator, batchSize: 1))
        .toList();
    final firstPaths = firstPass
        .expand((batch) => batch.records)
        .map((record) => record.locator.value)
        .toList();

    final secondPass = await scanner
        .scan(ScanRequest(root: locator, batchSize: 10))
        .toList();
    expect(
      secondPass
          .expand((batch) => batch.records)
          .map((record) => record.locator.value),
      firstPaths,
    );

    final removedCursor = firstPass.first.cursor!;
    await File(removedCursor).delete();
    final resumed = await scanner
        .scan(
          ScanRequest(
            root: locator,
            resumeCursor: removedCursor,
            batchSize: 10,
          ),
        )
        .toList();

    expect(resumed.single.isComplete, isTrue);
    expect(
      resumed.single.records.map((record) => record.locator.value),
      firstPaths.skip(1),
    );
  });

  test('resume order keeps nested files before a prefix sibling', () async {
    final prefixDirectory = await Directory(
      '${root.path}${Platform.pathSeparator}prefix',
    ).create();
    final nested = await File(
      '${prefixDirectory.path}${Platform.pathSeparator}z.txt',
    ).writeAsString('nested');
    final sibling = await File(
      '${root.path}${Platform.pathSeparator}prefix.txt',
    ).writeAsString('sibling');

    final resumed = await StreamingDirectoryScanner()
        .scan(
          ScanRequest(root: locator, resumeCursor: nested.path, batchSize: 20),
        )
        .toList();

    expect(
      resumed.single.records.map((record) => record.locator.value),
      contains(sibling.path),
    );
  });
}
