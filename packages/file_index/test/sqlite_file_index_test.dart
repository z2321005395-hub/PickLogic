import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_file_index/picklogic_file_index.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  FileRecord fixture(
    String id,
    String name, {
    VirtualCategory category = VirtualCategory.pdf,
  }) => FileRecord(
    id: id,
    locator: FileLocator(
      value: 'synthetic://$id',
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
    ),
    displayName: name,
    extension: name.split('.').last,
    mimeType: name.endsWith('.pdf') ? 'application/pdf' : 'text/plain',
    sizeBytes: 42,
    createdAt: DateTime.utc(2026, 1, 1),
    modifiedAt: DateTime.utc(2026, 1, int.parse(id)),
    parentLocator: null,
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
    isHidden: false,
    isSystem: false,
    isAccessible: true,
    isProtected: false,
    category: category,
    tags: const ['synthetic'],
    hashState: HashState.notRequested,
    ocrState: OcrState.notRequested,
  );

  test('persists batches, search state, updates, and removals', () async {
    final index = SqliteFileIndex.inMemory();
    addTearDown(index.close);
    await index.upsertBatch([
      fixture('1', 'alpha.pdf'),
      fixture('2', 'beta.pdf'),
    ]);
    expect(index.count, 2);
    expect((await index.search('alpha')).single.id, '1');

    await index.saveScanState(rootKey: 'root', cursor: '2', scannedCount: 2);
    expect(index.loadScanState('root')?.cursor, '2');
    expect(index.loadScanState('root')?.scannedCount, 2);

    await index.removeByIds(['1']);
    expect(index.count, 1);
  });

  test('searches all terms literally and ranks matching metadata', () async {
    final index = SqliteFileIndex.inMemory();
    addTearDown(index.close);
    await index.upsertBatch([
      fixture('1', 'alpha-notes.pdf'),
      fixture('2', 'alpha.txt', category: VirtualCategory.documents),
      fixture('3', '100_percent.pdf'),
      fixture('4', '100Xpercent.pdf'),
    ]);

    expect((await index.search('PDF alpha')).map((record) => record.id), ['1']);
    expect((await index.search('100_percent')).map((record) => record.id), [
      '3',
    ]);
  });

  test(
    'incremental scans preserve unchanged data and remove stale rows',
    () async {
      final index = SqliteFileIndex.inMemory();
      addTearDown(index.close);

      final first = index.beginIncrementalScan(rootKey: 'synthetic-root');
      final firstDelta = await index.upsertIncrementalBatch(
        session: first,
        records: [fixture('1', 'alpha.pdf'), fixture('2', 'beta.pdf')],
        cursor: '2',
        scannedCount: 2,
      );
      expect(firstDelta.insertedCount, 2);
      expect(firstDelta.changedCount, 2);
      expect(index.completeIncrementalScan(first).removedIds, isEmpty);

      const digest =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await index.upsertBatch([
        fixture(
          '1',
          'alpha.pdf',
        ).copyWith(hashState: HashState.complete, sha256: digest),
      ]);

      final second = index.beginIncrementalScan(rootKey: 'synthetic-root');
      final secondDelta = await index.upsertIncrementalBatch(
        session: second,
        records: [fixture('1', 'alpha.pdf'), fixture('2', 'beta-renamed.pdf')],
        cursor: '2',
        scannedCount: 2,
      );
      expect(secondDelta.unchangedCount, 1);
      expect(secondDelta.updatedCount, 1);
      expect(index.completeIncrementalScan(second).removedIds, isEmpty);
      final preserved = (await index.search('alpha')).single;
      expect(preserved.hashState, HashState.complete);
      expect(preserved.sha256, digest);

      final third = index.beginIncrementalScan(rootKey: 'synthetic-root');
      final thirdDelta = await index.upsertIncrementalBatch(
        session: third,
        records: [fixture('2', 'beta-renamed.pdf')],
        cursor: '2',
        scannedCount: 1,
      );
      expect(thirdDelta.unchangedCount, 1);
      expect(index.completeIncrementalScan(third).removedIds, ['1']);
      expect(index.count, 1);
    },
  );

  test('reconciles two synthetic directory scans end to end', () async {
    final root = await Directory.systemTemp.createTemp(
      'picklogic-incremental-index-test-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final alpha = File('${root.path}${Platform.pathSeparator}alpha.txt');
    final removed = File('${root.path}${Platform.pathSeparator}removed.txt');
    await alpha.writeAsString('a');
    await removed.writeAsString('remove-me');

    final index = SqliteFileIndex.inMemory();
    addTearDown(index.close);
    final scanner = StreamingDirectoryScanner();
    final rootLocator = FileLocator(
      value: root.path,
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
    );

    Future<({int changed, List<String> removedIds})> scanOnce() async {
      final session = index.beginIncrementalScan(rootKey: 'synthetic-root');
      var changed = 0;
      var removedIds = const <String>[];
      await for (final batch in scanner.scan(
        ScanRequest(root: rootLocator, batchSize: 1),
      )) {
        final delta = await index.upsertIncrementalBatch(
          session: session,
          records: batch.records,
          cursor: batch.cursor,
          scannedCount: batch.scannedCount,
        );
        changed += delta.changedCount;
        if (batch.isComplete) {
          removedIds = index.completeIncrementalScan(session).removedIds;
        }
      }
      return (changed: changed, removedIds: removedIds);
    }

    final first = await scanOnce();
    expect(first.changed, 2);
    expect(first.removedIds, isEmpty);
    final removedId = (await index.search('removed')).single.id;

    await alpha.writeAsString('alpha-expanded');
    await removed.delete();
    await File(
      '${root.path}${Platform.pathSeparator}added.txt',
    ).writeAsString('new');

    final second = await scanOnce();
    expect(second.changed, 2);
    expect(second.removedIds, [removedId]);
    expect(index.count, 2);
    expect((await index.search('added')).single.displayName, 'added.txt');
  });

  test('migrates version-one scan state without losing progress', () async {
    final root = await Directory.systemTemp.createTemp(
      'picklogic-sqlite-migration-test-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final databasePath =
        '${root.path}${Platform.pathSeparator}index-v1.sqlite3';
    final legacy = sqlite3.open(databasePath);
    legacy.execute('''
      CREATE TABLE scan_state (
        root_key TEXT PRIMARY KEY,
        cursor TEXT,
        scanned_count INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    legacy.execute(
      '''
      INSERT INTO scan_state(
        root_key, cursor, scanned_count, updated_at_ms
      ) VALUES (?, ?, ?, ?)
      ''',
      ['legacy-root', 'legacy-cursor', 7, 1],
    );
    legacy.execute('PRAGMA user_version = 1');
    legacy.close();

    final migrated = SqliteFileIndex.open(databasePath);
    expect(migrated.loadScanState('legacy-root')?.cursor, 'legacy-cursor');
    expect(migrated.loadScanState('legacy-root')?.scannedCount, 7);
    final session = migrated.beginIncrementalScan(rootKey: 'legacy-root');
    expect(session.generation, 1);
    migrated.close();

    final verified = sqlite3.open(databasePath);
    addTearDown(verified.close);
    expect(verified.select('PRAGMA user_version').single['user_version'], 2);
    final columns = verified
        .select('PRAGMA table_info(scan_state)')
        .map((row) => row['name'])
        .toSet();
    expect(columns, containsAll(['generation', 'is_complete']));
  });
}
