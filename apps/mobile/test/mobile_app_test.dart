import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_mobile/main.dart';
import 'package:picklogic_mobile/src/incremental_index_queue.dart';
import 'package:picklogic_mobile/src/mobile_repository.dart';
import 'package:picklogic_mobile/src/screenshot_grouping.dart';

void main() {
  testWidgets('mobile has four primary destinations and safe mode', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.pumpAndSettle();
    expect(find.text('Developer Safe Mode: ON'), findsOneWidget);
    for (final label in ['文件', '截图', '照片', '存储']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(const Key('language-switch')), findsOneWidget);
  });

  testWidgets('visible language switch updates navigation and permission CTA', (
    tester,
  ) async {
    final repository = _RetryMobileRepository(
      failBootstrapOnce: false,
      bootstrapState: _deniedBootstrap,
    );
    await tester.pumpWidget(PickLogicMobileApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('language-switch')));
    await tester.pumpAndSettle();
    for (final label in ['Files', 'Screenshots', 'Photos', 'Storage']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('PickLogic'), findsOneWidget);
    expect(find.text('拾理'), findsNothing);

    await tester.tap(find.text('Screenshots'));
    await tester.pumpAndSettle();
    expect(find.text('Choose media permissions'), findsOneWidget);
    expect(find.text('Choose shared folder'), findsOneWidget);
  });

  testWidgets('English covers media, Insight, review, and Storage actions', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-switch')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Screenshots'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('All 4 screenshots are browsable by date'),
      findsOneWidget,
    );
    expect(find.textContaining('Local review'), findsOneWidget);
    await tester.tap(find.byKey(const Key('screenshot-item-Screenshot_1.png')));
    await tester.pumpAndSettle();
    expect(find.text('Insight'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Delete review'), findsOneWidget);
    await tester.tap(find.byKey(const Key('screenshot-mark-later')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.text('Search photo name or type'), findsOneWidget);

    await tester.tap(find.text('Storage'));
    await tester.pumpAndSettle();
    expect(find.text('Storage Insight'), findsOneWidget);
    await tester.drag(find.text('Storage Insight'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Explicit limits'), findsOneWidget);
  });

  testWidgets('screenshot route uses review-safe language', (tester) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screenshot-real-count')), findsOneWidget);
    expect(find.textContaining('全部 4 张截图均可按日期浏览'), findsOneWidget);
    expect(find.byKey(const Key('screenshot-thumbnail-grid')), findsOneWidget);
    expect(find.textContaining('删除审查不会删除、移动或重命名'), findsOneWidget);
    expect(find.textContaining('来源线索不是应用归属结论'), findsOneWidget);
    expect(find.textContaining('OCR'), findsNothing);
    expect(find.textContaining('一键放心删除'), findsNothing);
  });

  testWidgets('screenshot month filter and local review queue are usable', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('screenshot-month-2026-07')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('screenshot-item-Screenshot_4.png')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('screenshot-item-Screenshot_1.png')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('screenshot-month-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screenshot-item-Screenshot_1.png')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screenshot-item-details')), findsOneWidget);
    expect(find.textContaining('OCR：未请求'), findsOneWidget);

    await tester.tap(find.byKey(const Key('screenshot-mark-delete-review')));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除审查 1'), findsOneWidget);
    expect(find.textContaining('未修改原文件'), findsOneWidget);
  });

  testWidgets('files collections remain usable without photo permission', (
    tester,
  ) async {
    final repository = _RetryMobileRepository(
      failBootstrapOnce: false,
      bootstrapState: _deniedBootstrap,
    );
    await tester.pumpWidget(PickLogicMobileApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('files-documents')), findsOneWidget);
    expect(find.text('Document_1.txt'), findsOneWidget);
    await tester.tap(find.byKey(const Key('files-downloads')));
    await tester.pumpAndSettle();
    expect(find.text('Download_1.pdf'), findsOneWidget);
  });

  testWidgets('photos support loaded metadata search', (tester) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.tap(find.text('照片'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('photos-search-field')),
      'Photo_12',
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Photo_12.jpg'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo_1.jpg'), findsNothing);
  });

  testWidgets('photos continue past 120 items near the grid bottom', (
    tester,
  ) async {
    final base = DateTime.utc(2026, 8, 13, 12);
    final photos = List<FileRecord>.generate(
      145,
      (index) => syntheticMobileRecord(
        'Photo_${index + 1}.jpg',
        createdAt: base.subtract(Duration(minutes: index)),
      ),
      growable: false,
    );
    final repository = _RetryMobileRepository(
      failBootstrapOnce: false,
      photos: photos,
    );
    await tester.pumpWidget(PickLogicMobileApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('照片'));
    await tester.pumpAndSettle();
    expect(repository.photoOffsets, <int>[0]);
    expect(find.text('已加载 120 / 145'), findsOneWidget);

    for (
      var attempt = 0;
      attempt < 20 && repository.photoOffsets.length < 2;
      attempt++
    ) {
      await tester.drag(
        find.byKey(const Key('photos-thumbnail-grid')),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
    }

    expect(repository.photoOffsets, <int>[0, 120]);
    expect(find.text('已加载 145 / 145', skipOffstage: false), findsOneWidget);
  });

  testWidgets('storage insight exposes platform and attribution limits', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.tap(find.text('存储'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('存储知件'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('明确限制'), findsOneWidget);
    expect(find.textContaining('无法枚举或归因'), findsOneWidget);
    expect(find.textContaining('不提供清理按钮'), findsOneWidget);
    expect(find.textContaining('不调度 OCR'), findsOneWidget);
  });

  testWidgets('bootstrap failure is explicit, safe, and retryable', (
    tester,
  ) async {
    final repository = _RetryMobileRepository();
    await tester.pumpWidget(PickLogicMobileApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-bootstrap-failure')), findsOneWidget);
    expect(find.text('本地平台能力暂时不可用'), findsOneWidget);
    expect(find.textContaining('未读取任何媒体或文件'), findsOneWidget);
    expect(find.text('尚未获得媒体只读权限。'), findsNothing);

    await tester.tap(find.byKey(const Key('mobile-bootstrap-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-bootstrap-failure')), findsNothing);
    expect(find.text('文件集合'), findsOneWidget);
    expect(repository.bootstrapCalls, 2);
  });

  testWidgets('permission platform failure is not reported as user denial', (
    tester,
  ) async {
    final repository = _RetryMobileRepository(
      failBootstrapOnce: false,
      failPermissionRequest: true,
      bootstrapState: _deniedBootstrap,
    );
    await tester.pumpWidget(PickLogicMobileApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择媒体权限'));
    await tester.pumpAndSettle();

    expect(find.textContaining('媒体权限检查未完成'), findsOneWidget);
    expect(find.textContaining('未授予媒体权限'), findsNothing);
    expect(find.text('尚未获得媒体只读权限。'), findsOneWidget);
  });
}

final class _RetryMobileRepository implements MobileRepository {
  _RetryMobileRepository({
    this.failBootstrapOnce = true,
    this.failPermissionRequest = false,
    this.bootstrapState,
    this.photos,
  });

  final MobileRepository _delegate = const SyntheticMobileRepository();
  final bool failBootstrapOnce;
  final bool failPermissionRequest;
  final MobileBootstrapState? bootstrapState;
  final List<FileRecord>? photos;
  final List<int> photoOffsets = <int>[];
  int bootstrapCalls = 0;

  @override
  Future<MobileBootstrapState> loadBootstrap() {
    bootstrapCalls += 1;
    if (failBootstrapOnce && bootstrapCalls == 1) {
      return Future<MobileBootstrapState>.error(
        StateError('synthetic bootstrap failure'),
      );
    }
    if (bootstrapState case final state?) {
      return Future<MobileBootstrapState>.value(state);
    }
    return _delegate.loadBootstrap();
  }

  @override
  Future<MobileBootstrapState> requestMediaAccess() {
    if (failPermissionRequest) {
      return Future<MobileBootstrapState>.error(
        StateError('synthetic permission platform failure'),
      );
    }
    return _delegate.requestMediaAccess();
  }

  @override
  Future<List<FileRecord>> loadMedia(
    AndroidMediaKind kind, {
    int limit = 120,
    int offset = 0,
  }) {
    if (kind == AndroidMediaKind.photos && photos != null) {
      final records = photos!;
      photoOffsets.add(offset);
      return Future<List<FileRecord>>.value(
        records.skip(offset).take(limit).toList(growable: false),
      );
    }
    return _delegate.loadMedia(kind, limit: limit, offset: offset);
  }

  @override
  Future<List<MobileScreenshotGroup>> loadScreenshotGroups({
    int limit = 120,
    int offset = 0,
  }) => _delegate.loadScreenshotGroups(limit: limit, offset: offset);

  @override
  Future<List<MobileScreenshotCandidate>> loadScreenshotCandidates({
    int limit = 120,
    int offset = 0,
  }) => _delegate.loadScreenshotCandidates(limit: limit, offset: offset);

  @override
  Future<int> countMedia(AndroidMediaKind kind) {
    if (kind == AndroidMediaKind.photos && photos != null) {
      final records = photos!;
      return Future<int>.value(records.length);
    }
    return _delegate.countMedia(kind);
  }

  @override
  Future<Uint8List?> loadThumbnail(
    FileRecord record, {
    required int maxWidth,
    required int maxHeight,
  }) =>
      _delegate.loadThumbnail(record, maxWidth: maxWidth, maxHeight: maxHeight);

  @override
  MobileIndexQueueSnapshot get indexQueueSnapshot =>
      _delegate.indexQueueSnapshot;

  @override
  void scheduleIncrementalIndexing() => _delegate.scheduleIncrementalIndexing();

  @override
  void cancelIncrementalIndexing() => _delegate.cancelIncrementalIndexing();

  @override
  Future<String?> chooseDocumentTree() => _delegate.chooseDocumentTree();

  @override
  Future<bool> open(FileRecord record) => _delegate.open(record);

  @override
  Future<List<FileRecord>> search(String query) => _delegate.search(query);

  @override
  Future<void> close() async {}
}

const _deniedBootstrap = MobileBootstrapState(
  permissions: AndroidMediaPermissionState(
    images: false,
    videos: false,
    audio: false,
    partialVisualAccess: false,
  ),
  storage: AndroidStorageSnapshot(
    totalBytes: 1000,
    availableBytes: 400,
    canInspectSharedMedia: false,
    canInspectOtherAppPrivateData: false,
    systemRestriction: 'restricted',
  ),
  synthetic: true,
  indexQueue: MobileIndexQueueSnapshot(
    pendingBatches: 0,
    isRunning: false,
    completedBatches: 0,
    failedBatches: 0,
    pageSize: 40,
    maxPendingBatches: 4,
  ),
);
