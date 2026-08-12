import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_mobile/src/incremental_index_queue.dart';
import 'package:picklogic_mobile/src/mobile_index_persistence.dart';
import 'package:picklogic_mobile/src/mobile_repository.dart';
import 'package:picklogic_mobile/src/screenshot_grouping.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('screenshot timeline', () {
    test('groups only close screenshots with the same source clue', () {
      final candidates = <MobileScreenshotCandidate>[
        _candidate('1', DateTime.utc(2026, 8, 12, 10), 'app.notes'),
        _candidate('2', DateTime.utc(2026, 8, 12, 9, 58), 'app.notes'),
        _candidate('3', DateTime.utc(2026, 8, 12, 9, 57), 'app.browser'),
        _candidate('4', DateTime.utc(2026, 8, 12, 9, 40), 'app.notes'),
      ];

      final groups = buildScreenshotGroups(candidates);

      expect(groups, hasLength(3));
      expect(groups.first.summary.memberIds, <String>['1', '2']);
      expect(groups.first.summary.sourceHint, 'app.notes');
      expect(groups.first.summary.ocrState, OcrState.notRequested);
      expect(groups.first.summary.contentHint, contains('未运行 OCR'));
    });

    test('falls back to an honest folder clue', () {
      final entry = _entry(
        '1',
        DateTime.utc(2026, 8, 12),
        null,
        relativePath: 'Pictures/Screenshots/',
      );
      expect(screenshotSourceHint(entry), '文件夹：Screenshots');
    });
  });

  test('manual queue continuation is bounded and deduplicated', () async {
    final queries = <AndroidMediaQuery>[];
    final queue = MobileIncrementalIndexQueue(
      autoContinue: false,
      pageSize: 2,
      maxPendingBatches: 2,
      loader: (query) async {
        queries.add(query);
        return AndroidMediaPage(
          items: <AndroidMediaEntry>[
            _entry(
              '${query.kind.name}:${queries.length}',
              DateTime.utc(2026, 8, 12, 10, queries.length),
              query.kind.name,
            ),
          ],
          offset: query.offset,
          hasMore:
              query.kind == AndroidMediaKind.screenshots && query.offset == 0,
        );
      },
    );

    expect(queue.enqueue(AndroidMediaKind.screenshots), isTrue);
    expect(queue.enqueue(AndroidMediaKind.screenshots), isFalse);
    expect(queue.enqueue(AndroidMediaKind.photos), isTrue);
    expect(queue.enqueue(AndroidMediaKind.images), isFalse);
    expect(queue.snapshot.schedulesOcr, isFalse);
    expect(queue.snapshot.persistsAcrossRestarts, isFalse);

    await queue.idle;
    expect(queries, hasLength(2));
    expect(queries.every((query) => query.limit == 2), isTrue);
    expect(
      queries.every((query) => query.modifiedAfterEpochSeconds == null),
      isTrue,
    );

    expect(queue.enqueue(AndroidMediaKind.screenshots), isTrue);
    await queue.idle;
    expect(queries, hasLength(3));
    expect(queries.last.offset, 1);
    expect(queries.last.modifiedAfterEpochSeconds, isNull);

    expect(queue.enqueue(AndroidMediaKind.screenshots), isTrue);
    await queue.idle;
    expect(queries, hasLength(4));
    expect(queries.last.offset, 0);
    expect(queries.last.modifiedAfterEpochSeconds, isNotNull);
  });

  test(
    'automatic continuation is bounded and fair across collections',
    () async {
      final queries = <AndroidMediaQuery>[];
      final calls = <AndroidMediaKind, int>{};
      final queue = MobileIncrementalIndexQueue(
        pageSize: 1,
        loader: (query) async {
          queries.add(query);
          final call = (calls[query.kind] ?? 0) + 1;
          calls[query.kind] = call;
          return AndroidMediaPage(
            items: <AndroidMediaEntry>[
              _entry(
                '${query.kind.name}:$call',
                DateTime.utc(2026, 8, 13, 10, call),
                query.kind.name,
              ),
            ],
            offset: query.offset,
            hasMore: call == 1,
          );
        },
      );

      expect(queue.enqueue(AndroidMediaKind.screenshots), isTrue);
      expect(queue.enqueue(AndroidMediaKind.photos), isTrue);
      await queue.idle;

      expect(queries.map((query) => query.kind), <AndroidMediaKind>[
        AndroidMediaKind.screenshots,
        AndroidMediaKind.photos,
        AndroidMediaKind.screenshots,
        AndroidMediaKind.photos,
      ]);
      expect(queries.map((query) => query.offset), <int>[0, 0, 1, 1]);
      expect(queue.snapshot.completedBatches, 4);
      expect(queue.snapshot.pendingBatches, 0);
      expect(queue.snapshot.isPaused, isFalse);
    },
  );

  test('cancellation stops after the current bounded page', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var queryCount = 0;
    final queue = MobileIncrementalIndexQueue(
      pageSize: 1,
      loader: (query) async {
        queryCount += 1;
        if (!started.isCompleted) started.complete();
        await release.future;
        return AndroidMediaPage(
          items: <AndroidMediaEntry>[
            _entry(
              'cancelled:$queryCount',
              DateTime.utc(2026, 8, 13, 11),
              query.kind.name,
            ),
          ],
          offset: query.offset,
          hasMore: true,
        );
      },
    );

    expect(queue.enqueue(AndroidMediaKind.screenshots), isTrue);
    await started.future;
    queue.cancel();
    release.complete();
    await queue.idle;

    expect(queryCount, 1);
    expect(queue.snapshot.pendingBatches, 0);
    expect(queue.snapshot.isRunning, isFalse);
    expect(queue.snapshot.isPaused, isTrue);
  });

  group('Android repository', () {
    const channel = MethodChannel('picklogic_android_bridge');
    var thumbnailCalls = 0;
    late Completer<Object?> blockedQueries;
    late List<String> queriedKinds;

    setUp(() {
      thumbnailCalls = 0;
      blockedQueries = Completer<Object?>();
      queriedKinds = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'getMediaPermissionState' => <String, Object>{
                'images': true,
                'videos': false,
                'audio': false,
                'partialVisualAccess': false,
              },
              'getStorageSnapshot' => <String, Object>{
                'totalBytes': 1000,
                'availableBytes': 400,
                'canInspectSharedMedia': true,
                'canInspectOtherAppPrivateData': false,
                'systemRestriction': 'restricted',
              },
              'getPrivateIndexDatabasePath' =>
                'synthetic-private/picklogic-index.sqlite3',
              'queryMediaPage' => () {
                final arguments = call.arguments! as Map<Object?, Object?>;
                queriedKinds.add(arguments['kind']! as String);
                return blockedQueries.future;
              }(),
              'loadThumbnail' => () {
                thumbnailCalls += 1;
                return Uint8List.fromList(<int>[1, 2, 3, 4]);
              }(),
              _ => null,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('bootstrap does not await the background metadata queue', () async {
      final repository = AndroidMobileRepository(
        indexPersistence: SqliteMobileIndexPersistence.inMemory(),
      );

      final bootstrap = await repository.loadBootstrap().timeout(
        const Duration(seconds: 1),
      );

      expect(bootstrap.indexQueue.pendingBatches, lessThanOrEqualTo(2));
      expect(bootstrap.indexQueue.schedulesOcr, isFalse);
      await _waitUntil(() => queriedKinds.isNotEmpty);
      blockedQueries.complete(<String, Object>{
        'items': <Object>[],
        'offset': 0,
        'hasMore': false,
      });
      await _waitUntil(
        () =>
            queriedKinds.toSet().containsAll(<String>{'screenshots', 'photos'}),
      );
      await repository.close();
      expect(repository.indexQueueSnapshot.isRunning, isFalse);
      expect(queriedKinds.toSet(), <String>{'screenshots', 'photos'});
    });

    test('background metadata work follows granted media kinds', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'getMediaPermissionState' => <String, Object>{
                'images': true,
                'videos': true,
                'audio': true,
                'partialVisualAccess': false,
              },
              'getStorageSnapshot' => <String, Object>{
                'totalBytes': 1000,
                'availableBytes': 400,
                'canInspectSharedMedia': true,
                'canInspectOtherAppPrivateData': false,
                'systemRestriction': 'restricted',
              },
              'queryMediaPage' => () {
                final arguments = call.arguments! as Map<Object?, Object?>;
                queriedKinds.add(arguments['kind']! as String);
                return <String, Object>{
                  'items': <Object>[],
                  'offset': 0,
                  'hasMore': false,
                };
              }(),
              _ => null,
            };
          });
      final repository = AndroidMobileRepository(
        indexPersistence: SqliteMobileIndexPersistence.inMemory(),
      );

      await repository.loadBootstrap();
      await _waitUntil(
        () => queriedKinds.toSet().containsAll(<String>{
          'screenshots',
          'photos',
          'videos',
          'audio',
        }),
      );
      await repository.close();

      expect(queriedKinds.toSet(), <String>{
        'screenshots',
        'photos',
        'videos',
        'audio',
      });
    });

    test('bootstrap platform reads have a bounded timeout', () async {
      final blocked = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'getMediaPermissionState' => blocked.future,
              'getStorageSnapshot' => <String, Object>{
                'totalBytes': 1000,
                'availableBytes': 400,
                'canInspectSharedMedia': false,
                'canInspectOtherAppPrivateData': false,
                'systemRestriction': 'restricted',
              },
              _ => null,
            };
          });
      final repository = AndroidMobileRepository(
        bootstrapTimeout: const Duration(milliseconds: 20),
        indexPersistence: SqliteMobileIndexPersistence.inMemory(),
      );

      await expectLater(
        repository.loadBootstrap(),
        throwsA(isA<TimeoutException>()),
      );
      blocked.complete(null);
      await repository.close();
    });

    test('serves repeated thumbnail requests from the bounded cache', () async {
      final repository = AndroidMobileRepository(
        indexPersistence: SqliteMobileIndexPersistence.inMemory(),
      );
      final record = _androidRecord('thumbnail');

      final first = await repository.loadThumbnail(
        record,
        maxWidth: 160,
        maxHeight: 120,
      );
      final second = await repository.loadThumbnail(
        record,
        maxWidth: 160,
        maxHeight: 120,
      );

      expect(first, <int>[1, 2, 3, 4]);
      expect(second, same(first));
      expect(thumbnailCalls, 1);
      await repository.close();
    });

    test(
      'MediaStore metadata is searchable through the shared index',
      () async {
        final repository = AndroidMobileRepository(
          indexPersistence: SqliteMobileIndexPersistence.inMemory(),
        );
        blockedQueries.complete(<String, Object>{
          'items': <Object>[
            <String, Object>{
              'id': 'screenshots:persisted',
              'contentUri': 'content://media/persisted',
              'displayName': 'Screenshot_persisted.png',
              'mimeType': 'image/png',
              'sizeBytes': 120,
              'createdAtEpochSeconds': 10,
              'modifiedAtEpochSeconds': 12,
              'relativePath': 'Pictures/Screenshots/',
              'sourceHint': 'synthetic.notes',
            },
          ],
          'offset': 0,
          'hasMore': false,
        });

        await repository.loadMedia(AndroidMediaKind.screenshots, limit: 1);
        final matches = await repository.search('persisted');

        expect(matches.single.id, 'screenshots:persisted');
        await repository.close();
      },
    );

    test(
      'a local index write failure does not hide a requested page',
      () async {
        final repository = AndroidMobileRepository(
          indexPersistence: _FailingMobileIndexPersistence(),
        );
        blockedQueries.complete(<String, Object>{
          'items': <Object>[
            <String, Object>{
              'id': 'screenshots:visible',
              'contentUri': 'content://media/visible',
              'displayName': 'Screenshot_visible.png',
              'mimeType': 'image/png',
              'sizeBytes': 120,
              'createdAtEpochSeconds': 10,
              'modifiedAtEpochSeconds': 12,
              'relativePath': 'Pictures/Screenshots/',
              'sourceHint': 'synthetic.notes',
            },
          ],
          'offset': 0,
          'hasMore': false,
        });

        final page = await repository.loadMedia(
          AndroidMediaKind.screenshots,
          limit: 1,
        );
        final cachedSearch = await repository.search('visible');

        expect(page.single.id, 'screenshots:visible');
        expect(cachedSearch.single.id, 'screenshots:visible');
        await repository.close();
      },
    );
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for background test work.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _FailingMobileIndexPersistence implements MobileIndexPersistence {
  @override
  bool get persistsAcrossRestarts => true;

  @override
  Future<MobileIndexCheckpoint?> loadCheckpoint(AndroidMediaKind kind) async =>
      null;

  @override
  Future<void> saveCheckpoint(
    AndroidMediaKind kind,
    MobileIndexCheckpoint checkpoint,
  ) async => throw StateError('synthetic checkpoint failure');

  @override
  Future<void> upsertRecords(List<FileRecord> records) async =>
      throw StateError('synthetic index failure');

  @override
  Future<List<FileRecord>> search(String query, {int limit = 100}) async =>
      throw StateError('synthetic search failure');

  @override
  Future<void> close() async {}
}

MobileScreenshotCandidate _candidate(
  String id,
  DateTime capturedAt,
  String sourceHint,
) => MobileScreenshotCandidate(
  record: _androidRecord(id, timestamp: capturedAt),
  metadata: _entry(id, capturedAt, sourceHint),
);

AndroidMediaEntry _entry(
  String id,
  DateTime capturedAt,
  String? sourceHint, {
  String? relativePath,
}) => AndroidMediaEntry(
  id: id,
  contentUri: 'content://media/$id',
  displayName: 'Screenshot_$id.png',
  mimeType: 'image/png',
  sizeBytes: 1024,
  createdAt: capturedAt,
  modifiedAt: capturedAt,
  relativePath: relativePath,
  sourceHint: sourceHint,
);

FileRecord _androidRecord(String id, {DateTime? timestamp}) => FileRecord(
  id: id,
  locator: FileLocator(
    value: 'content://media/$id',
    sourceKind: SourceKind.mediaStore,
    platform: PickLogicPlatform.android,
  ),
  displayName: 'Screenshot_$id.png',
  extension: 'png',
  mimeType: 'image/png',
  sizeBytes: 1024,
  createdAt: timestamp,
  modifiedAt: timestamp ?? DateTime.utc(2026, 8, 12),
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
