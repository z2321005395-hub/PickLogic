import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_file_index/picklogic_file_index.dart';
import 'package:picklogic_mobile/src/incremental_index_queue.dart';
import 'package:picklogic_mobile/src/mobile_index_persistence.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'picklogic-mobile-index-test-',
    );
    databasePath =
        '${temporaryDirectory.path}${Platform.pathSeparator}index.db';
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'SQLite metadata and a partial-page checkpoint survive restart',
    () async {
      final firstPersistence = SqliteMobileIndexPersistence.open(databasePath);
      await firstPersistence.upsertRecords(<FileRecord>[_record('one')]);
      final firstQueue = MobileIncrementalIndexQueue(
        autoContinue: false,
        pageSize: 1,
        checkpointStore: firstPersistence,
        loader: (_) async => AndroidMediaPage(
          items: <AndroidMediaEntry>[_entry('one')],
          offset: 0,
          hasMore: true,
        ),
      );

      expect(firstQueue.enqueue(AndroidMediaKind.screenshots), isTrue);
      await firstQueue.idle;
      expect(firstQueue.snapshot.persistsAcrossRestarts, isTrue);
      expect(firstQueue.snapshot.indexedItems, 1);
      await firstPersistence.close();

      final resumedQueries = <AndroidMediaQuery>[];
      final secondPersistence = SqliteMobileIndexPersistence.open(databasePath);
      final secondQueue = MobileIncrementalIndexQueue(
        pageSize: 1,
        checkpointStore: secondPersistence,
        loader: (query) async {
          resumedQueries.add(query);
          return AndroidMediaPage(
            items: const <AndroidMediaEntry>[],
            offset: query.offset,
            hasMore: false,
          );
        },
      );

      expect(secondQueue.enqueue(AndroidMediaKind.screenshots), isTrue);
      await secondQueue.idle;
      expect(resumedQueries.single.offset, 1);
      expect(resumedQueries.single.modifiedAfterEpochSeconds, isNull);
      expect((await secondPersistence.search('Screenshot')).single.id, 'one');
      await secondPersistence.close();
    },
  );

  test('a malformed checkpoint restarts the bounded pass safely', () async {
    final rawIndex = SqliteFileIndex.open(databasePath);
    await rawIndex.saveScanState(
      rootKey: 'android-mediastore:screenshots',
      cursor: '{not-json',
      scannedCount: 12,
    );
    rawIndex.close();

    final queries = <AndroidMediaQuery>[];
    final persistence = SqliteMobileIndexPersistence.open(databasePath);
    final queue = MobileIncrementalIndexQueue(
      checkpointStore: persistence,
      loader: (query) async {
        queries.add(query);
        return const AndroidMediaPage(items: [], offset: 0, hasMore: false);
      },
    );

    expect(queue.enqueue(AndroidMediaKind.screenshots), isTrue);
    await queue.idle;
    expect(queries.single.offset, 0);
    expect(queries.single.modifiedAfterEpochSeconds, isNull);
    expect(queue.snapshot.failedBatches, 0);
    await persistence.close();
  });

  test(
    'lazy persistence retries a failed private-path initialization',
    () async {
      var attempts = 0;
      final persistence = LazyMobileIndexPersistence(() async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('synthetic path lookup failure');
        }
        return SqliteMobileIndexPersistence.inMemory();
      }, persistsAcrossRestarts: true);

      await expectLater(
        persistence.loadCheckpoint(AndroidMediaKind.photos),
        throwsStateError,
      );
      expect(await persistence.loadCheckpoint(AndroidMediaKind.photos), isNull);
      expect(attempts, 2);
      await persistence.close();
    },
  );
}

AndroidMediaEntry _entry(String id) => AndroidMediaEntry(
  id: id,
  contentUri: 'content://synthetic/$id',
  displayName: 'Screenshot_$id.png',
  mimeType: 'image/png',
  sizeBytes: 1024,
  createdAt: DateTime.utc(2026, 8, 13, 9),
  modifiedAt: DateTime.utc(2026, 8, 13, 9),
  relativePath: 'Pictures/Screenshots/',
  sourceHint: 'synthetic.notes',
);

FileRecord _record(String id) => FileRecord(
  id: id,
  locator: FileLocator(
    value: 'content://synthetic/$id',
    sourceKind: SourceKind.mediaStore,
    platform: PickLogicPlatform.android,
  ),
  displayName: 'Screenshot_$id.png',
  extension: 'png',
  mimeType: 'image/png',
  sizeBytes: 1024,
  createdAt: DateTime.utc(2026, 8, 13, 9),
  modifiedAt: DateTime.utc(2026, 8, 13, 9),
  parentLocator: null,
  sourceKind: SourceKind.mediaStore,
  platform: PickLogicPlatform.android,
  isHidden: false,
  isSystem: false,
  isAccessible: true,
  isProtected: false,
  category: VirtualCategory.screenshots,
  hashState: HashState.notRequested,
  ocrState: OcrState.notRequested,
);
