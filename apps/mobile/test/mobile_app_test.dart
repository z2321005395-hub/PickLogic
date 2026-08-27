import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_mobile/main.dart';
import 'package:picklogic_mobile/src/incremental_index_queue.dart';
import 'package:picklogic_mobile/src/mobile_repository.dart';
import 'package:picklogic_mobile/src/screenshot_grouping.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

void main() {
  testWidgets('mobile has three focused primary destinations', (tester) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('开发者安全模式'), findsNothing);
    for (final label in ['分类', '最近', '整理']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.byKey(const Key('mobile-settings')), findsOneWidget);
    expect(find.byKey(const Key('mobile-refresh')), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('mobile-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    for (final label in ['Categories', 'Recent', 'Organize']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('PickLogic'), findsOneWidget);
    expect(find.text('拾理'), findsNothing);

    await tester.tap(find.byKey(const Key('nav-organize')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organize-screenshots')));
    await tester.pumpAndSettle();
    expect(find.text('Choose media permissions'), findsOneWidget);
    expect(find.text('Choose shared folder'), findsOneWidget);
  });

  testWidgets('English covers media, Insight, review, and Storage actions', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobile-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nav-organize')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organize-screenshots')));
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
    expect(
      find.byKey(const Key('screenshot-mark-delete-review')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('screenshot-mark-later')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organize-photos')));
    await tester.pumpAndSettle();
    expect(find.text('Search photo name or type'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('organize-storage')));
    await tester.pumpAndSettle();
    expect(find.text('Storage Insight'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Explicit limits'),
      600,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Explicit limits'), findsOneWidget);
  });

  testWidgets('screenshot route uses review-safe language', (tester) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await _openOrganize(tester, const Key('organize-screenshots'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('screenshot-real-count')), findsOneWidget);
    expect(find.textContaining('全部 4 张截图均可按日期浏览'), findsOneWidget);
    expect(find.byKey(const Key('screenshot-thumbnail-grid')), findsOneWidget);
    expect(find.textContaining('删除审查不会删除、移动或重命名'), findsOneWidget);
    expect(find.textContaining('来源线索不是应用归属结论'), findsOneWidget);
    expect(find.textContaining('OCR'), findsNothing);
    expect(find.textContaining('一键放心删除'), findsNothing);
  });

  testWidgets('screenshot opens in the first-class internal viewer', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await _openOrganize(tester, const Key('organize-screenshots'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screenshot-item-Screenshot_1.png')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('screenshot-open-internal-viewer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-first-class-viewer')), findsOneWidget);
    expect(find.text('Screenshot_1.png'), findsOneWidget);
    expect(find.byKey(const Key('mobile-viewer-information')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobile-viewer-review')));
    await tester.pump();
    expect(find.textContaining('真实文件未修改'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobile-viewer-favorite')));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.rule_folder), findsOneWidget);
  });

  testWidgets('photo opens in the full-page zoomable viewer', (tester) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await _openOrganize(tester, const Key('organize-photos'));
    await tester.pumpAndSettle();

    await tester.tap(
      find
          .descendant(
            of: find.byKey(const Key('photos-thumbnail-grid')),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-first-class-viewer')), findsOneWidget);
    expect(find.byKey(const Key('mobile-image-viewer')), findsOneWidget);
    expect(find.byIcon(Icons.center_focus_strong), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right), findsOneWidget);
  });

  testWidgets('audio and video collections use the internal media player', (
    tester,
  ) async {
    for (final item in <({String label, String name, bool audioOnly})>[
      (label: '音频', name: 'Audio_1.mp3', audioOnly: true),
      (label: '视频', name: 'Video_1.mp4', audioOnly: false),
    ]) {
      await tester.pumpWidget(PickLogicMobileApp(key: UniqueKey()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.label));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-collection-view')), findsOneWidget);
      await tester.tap(find.text(item.name));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mobile-first-class-viewer')),
        findsOneWidget,
      );
      final player = tester.widget<PickLogicMediaPlayer>(
        find.byType(PickLogicMediaPlayer),
      );
      expect(player.audioOnly, item.audioOnly);
      expect(player.source.kind, PickLogicMediaSourceKind.contentUri);
      expect(player.source.value, contains(item.name));
    }
  });

  testWidgets('screenshot month filter and local review queue are usable', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await _openOrganize(tester, const Key('organize-screenshots'));
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
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files-documents')));
    await tester.pumpAndSettle();
    expect(find.text('Document_1.txt'), findsOneWidget);
    await tester.tap(find.text('Document_1.txt'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-first-class-viewer')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files-downloads')));
    await tester.pumpAndSettle();
    expect(find.text('Download_1.pdf'), findsOneWidget);
  });

  testWidgets(
    'mobile home consolidates type, smart, source, and storage entry',
    (tester) async {
      await tester.pumpWidget(const PickLogicMobileApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mobile-home-search')), findsOneWidget);
      expect(find.text('文件类型'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-folder-browser-entry')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('智能集合'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('智能集合'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('应用与来源'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('应用与来源'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('phone-storage-entry')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('phone-storage-entry')), findsOneWidget);
      for (final label in ['图片', '音频', '视频', '应用', '压缩包', '文档']) {
        expect(find.text(label), findsWidgets);
      }
    },
  );

  testWidgets('folder browser is a first-class read-only destination', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobile-folder-browser-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-saf-file-browser')), findsOneWidget);
    expect(find.text('尚未添加文件夹'), findsOneWidget);
    expect(find.textContaining('不会修改真实文件'), findsOneWidget);
  });

  testWidgets('screenshot filters expose implemented review dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await _openOrganize(tester, const Key('organize-screenshots'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('screenshot-filter-month')), findsOneWidget);
    expect(
      find.byKey(const Key('screenshot-filter-consecutive')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('screenshot-filter-review')), findsOneWidget);
  });

  testWidgets('photos support loaded metadata search', (tester) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await _openOrganize(tester, const Key('organize-photos'));
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

    await _openOrganize(tester, const Key('organize-photos'));
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
    await _openOrganize(tester, const Key('organize-storage'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('明确限制'),
      600,
      scrollable: find.byType(Scrollable).last,
    );
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
    expect(find.byKey(const Key('mobile-home-search')), findsOneWidget);
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

    await _openOrganize(tester, const Key('organize-screenshots'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择媒体权限'));
    await tester.pumpAndSettle();

    expect(find.textContaining('媒体权限检查未完成'), findsOneWidget);
    expect(find.textContaining('未授予媒体权限'), findsNothing);
    expect(find.text('尚未获得媒体只读权限。'), findsOneWidget);
  });
}

Future<void> _openOrganize(WidgetTester tester, Key destination) async {
  await tester.tap(find.byKey(const Key('nav-organize')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(destination));
  await tester.pumpAndSettle();
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
  Future<bool> requestSystemTrash(List<FileRecord> records) =>
      _delegate.requestSystemTrash(records);

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
