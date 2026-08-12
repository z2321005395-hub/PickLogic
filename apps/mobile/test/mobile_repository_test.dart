import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_mobile/src/incremental_index_queue.dart';
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

  test(
    'incremental queue is bounded, deduplicated, and never auto-pages',
    () async {
      final queries = <AndroidMediaQuery>[];
      final queue = MobileIncrementalIndexQueue(
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
    },
  );

  group('Android repository', () {
    const channel = MethodChannel('picklogic_android_bridge');
    var thumbnailCalls = 0;
    late Completer<Object?> blockedQueries;

    setUp(() {
      thumbnailCalls = 0;
      blockedQueries = Completer<Object?>();
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
              'queryMediaPage' => blockedQueries.future,
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
      final repository = AndroidMobileRepository();

      final bootstrap = await repository.loadBootstrap().timeout(
        const Duration(seconds: 1),
      );

      expect(bootstrap.indexQueue.pendingBatches, lessThanOrEqualTo(2));
      expect(bootstrap.indexQueue.schedulesOcr, isFalse);
      blockedQueries.complete(<String, Object>{
        'items': <Object>[],
        'offset': 0,
        'hasMore': false,
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(repository.indexQueueSnapshot.isRunning, isFalse);
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
      );

      await expectLater(
        repository.loadBootstrap(),
        throwsA(isA<TimeoutException>()),
      );
      blocked.complete(null);
    });

    test('serves repeated thumbnail requests from the bounded cache', () async {
      final repository = AndroidMobileRepository();
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
    });
  });
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
