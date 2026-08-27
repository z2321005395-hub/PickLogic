import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_desktop/src/app.dart';
import 'package:picklogic_desktop/src/desktop_repository.dart';
import 'package:picklogic_desktop/src/pro_pdf_reader.dart';
import 'package:picklogic_desktop/src/pro_workspace.dart';
import 'package:picklogic_duplicate_engine/picklogic_duplicate_engine.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  testWidgets('Standard starts on a localized category home', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const PickLogicDesktopApp(pro: false));
    await tester.pumpAndSettle();

    expect(find.text('拾理'), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('重复项'), findsOneWidget);
    expect(find.text('存储'), findsOneWidget);
    expect(find.byKey(const Key('desktop-home')), findsOneWidget);
    expect(find.byKey(const Key('home-dual-pane')), findsOneWidget);
    expect(find.byKey(const Key('workspace-view-mode')), findsOneWidget);
    expect(find.byKey(const Key('detail-pane')), findsNothing);
    expect(
      tester.widget<Switch>(find.byKey(const Key('auto-index-switch'))).value,
      isFalse,
    );
    expect(find.textContaining('磁盘根仅用于浏览'), findsOneWidget);
    expect(find.text('磁盘与常用目录'), findsOneWidget);
    expect(find.byKey(const Key('move-to-target')), findsNothing);
    expect(find.textContaining('Left pane'), findsNothing);
    expect(find.textContaining('Developer Safe Mode'), findsNothing);
  });

  testWidgets(
    'Standard panels navigate independently and context follows browsing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _TrackARepository();
      await tester.pumpWidget(
        PickLogicDesktopApp(pro: false, repository: repository),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('home-dual-pane')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workspace-tools-menu')), findsOneWidget);

      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('pane-0-root-drive:synthetic')),
          )
          .onDoubleTap!();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pane-0-entry-directory:documents')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pane-1-root-drive:synthetic')),
        findsOneWidget,
      );

      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('pane-0-entry-directory:documents')),
          )
          .onDoubleTap!();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pane-0-entry-report')), findsOneWidget);
      expect(find.byKey(const Key('detail-pane')), findsOneWidget);
      expect(find.byKey(const Key('current-folder-context')), findsOneWidget);
      expect(find.text('已验证事实'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pane-0-crumb-synthetic:/drive/Documents')),
        findsOneWidget,
      );
      final upButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('pane-0-up')),
      );
      expect(upButton.onPressed, isNotNull);
      upButton.onPressed!();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pane-0-entry-directory:documents')),
        findsOneWidget,
      );
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('pane-0-entry-directory:documents')),
          )
          .onDoubleTap!();
      await tester.pumpAndSettle();

      tester
          .widget<InkWell>(find.byKey(const ValueKey('pane-0-entry-report')))
          .onTap!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-pane')), findsOneWidget);
      expect(find.text('预览与知件'), findsOneWidget);
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.text('实际路径'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('置信度'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('置信度'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-detail-pane')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-pane')), findsNothing);

      tester
          .widget<InkWell>(find.byKey(const ValueKey('pane-0-entry-report')))
          .onDoubleTap!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('desktop-internal-viewer')), findsOneWidget);
      expect(repository.opened, isEmpty);
      Navigator.of(
        tester.element(find.byKey(const Key('desktop-internal-viewer'))),
      ).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pane-1-home')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('choose-folder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pane-1-entry-report')), findsOneWidget);
      tester
          .widget<InkWell>(find.byKey(const ValueKey('pane-1-entry-figure')))
          .onTap!();
      await tester.pump();
      expect(find.text('只读位置'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('move-workspace-item')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('trash-workspace-item')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('trash-workspace-item')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('trash-requires-managed-folder')),
        findsOneWidget,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('active-pane-search')),
        'figure',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('pane-1-entry-figure')), findsOneWidget);
      expect(find.byKey(const ValueKey('pane-1-entry-report')), findsNothing);
      expect(find.byKey(const ValueKey('pane-0-entry-report')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pane-0-home')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('nav-search')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('active-pane-search')),
        'indexed archive',
      );
      await tester.tap(find.byKey(const Key('search-index')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pane-0-entry-indexed-away')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pane-1-entry-figure')), findsOneWidget);
      expect(find.byKey(const Key('move-workspace-item')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('move-workspace-item')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Standard keeps duplicate and read-only storage tools reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _TrackARepository();
      await tester.pumpWidget(
        PickLogicDesktopApp(pro: false, repository: repository),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-duplicates')));
      await tester.pump();
      expect(find.textContaining('请先在活动栏打开包含文件的目录'), findsOneWidget);
      expect(repository.duplicateRuns, 0);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-files')));
      await tester.pumpAndSettle();

      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('pane-0-root-drive:synthetic')),
          )
          .onDoubleTap!();
      await tester.pumpAndSettle();
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('pane-0-entry-directory:documents')),
          )
          .onDoubleTap!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-duplicates')));
      await tester.pumpAndSettle();

      expect(repository.duplicateRuns, 1);
      expect(
        find.byKey(const ValueKey('pane-0-entry-duplicate-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pane-0-entry-duplicate-b')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('pane-0-entry-report')), findsNothing);
      expect(
        find.byKey(const ValueKey('pane-1-root-drive:synthetic')),
        findsOneWidget,
      );
      expect(find.text('精确重复项：2 个文件'), findsOneWidget);

      tester
          .widget<IconButton>(find.byKey(const Key('toggle-language')))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Exact duplicates: 2 files'), findsOneWidget);
      expect(find.textContaining('精确重复项'), findsNothing);
      tester
          .widget<IconButton>(find.byKey(const Key('toggle-language')))
          .onPressed!();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav-storage')));
      await tester.pumpAndSettle();
      expect(repository.storageSummaryRuns, 2);
      expect(find.byKey(const Key('storage-summary-view')), findsOneWidget);
      expect(find.text('存储概览'), findsOneWidget);
      expect(find.text('S:\\'), findsOneWidget);
      expect(find.textContaining('不会扫描或修改文件'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-files')));
      await tester.pumpAndSettle();
      expect(find.text('左栏'), findsOneWidget);
      expect(find.text('右栏'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pane-1-root-drive:synthetic')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Standard discloses auto-index sources and switches locale cleanly',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _TrackARepository();
      await tester.pumpWidget(
        PickLogicDesktopApp(pro: false, repository: repository),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('auto-index-switch')));
      await tester.pumpAndSettle();
      expect(find.textContaining('来源包括桌面、文档和下载目录'), findsOneWidget);
      expect(find.textContaining('磁盘根仍不会自动递归扫描'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-auto-index')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(find.byKey(const Key('auto-index-switch'))).value,
        isTrue,
      );
      expect(repository.commonIndexRuns, 1);
      expect(find.textContaining('本次常用目录索引已完成'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-files')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toggle-language')));
      await tester.pumpAndSettle();
      expect(find.text('PickLogic'), findsOneWidget);
      expect(find.text('Left pane'), findsOneWidget);
      expect(find.text('Right pane'), findsOneWidget);
      expect(find.text('Read-only location'), findsOneWidget);
      expect(
        find.textContaining('Common-folder indexing completed'),
        findsOneWidget,
      );
      expect(find.text('Files'), findsWidgets);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Duplicates'), findsOneWidget);
      expect(find.text('Storage'), findsOneWidget);
      expect(find.textContaining('拾理'), findsNothing);
      expect(find.textContaining('左栏'), findsNothing);
      expect(find.textContaining('开发者安全模式'), findsNothing);
    },
  );

  testWidgets('Pro composes literature and system navigation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      PickLogicDesktopApp(
        pro: true,
        proPdfReaderBuilder: (_) => const SizedBox(
          key: Key('test-pdf-reader'),
          child: Text('Embedded PDF reader test double'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('文献'), findsOneWidget);
    expect(find.text('研究'), findsOneWidget);
    expect(find.text('系统洞察'), findsOneWidget);
    expect(find.textContaining('Literature'), findsNothing);

    await tester.tap(find.byKey(const Key('toggle-language')));
    await tester.pumpAndSettle();
    expect(find.text('Literature'), findsOneWidget);
    expect(find.text('Research'), findsOneWidget);
    expect(find.text('System Insight'), findsOneWidget);
    expect(find.textContaining('文献'), findsNothing);
  });

  testWidgets('Pro literature route shows persistent metadata and page state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryLiteratureStore([
      LiteratureLibraryEntry(
        record: const LiteratureRecord(
          id: 'lit-synthetic',
          localFileId: 'local-lit-synthetic',
          doi: '10.5555/picklogic.synthetic',
          title: 'Local-first synthetic literature workflow',
          authors: ['Lin Researcher', 'Morgan Example'],
          year: 2026,
          readingProgress: 0.35,
          metadataConfidence: 0.9,
        ),
        localPath: r'X:\synthetic\paper.pdf',
        fileName: 'paper.pdf',
        addedAt: DateTime.utc(2026, 8, 13),
        currentPage: 7,
        totalPages: 20,
      ),
    ]);
    await tester.pumpWidget(
      _localizedTestApp(
        locale: const Locale('zh'),
        home: ProWorkspaceRoute(
          section: 'literature',
          libraryStore: store,
          literaturePdfReaderBuilder: (context, entry, onPositionChanged) =>
              Column(
                key: const Key('test-pdf-reader'),
                children: [
                  Text('Reader at page ${entry.currentPage}'),
                  FilledButton(
                    key: const Key('test-record-page'),
                    onPressed: () => onPositionChanged(8, 10),
                    child: const Text('Record page'),
                  ),
                ],
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('literature-manager-lite-view')),
      findsOneWidget,
    );
    expect(find.text('文献库'), findsOneWidget);
    expect(find.text('paper.pdf'), findsWidgets);
    expect(
      find.text('Local-first synthetic literature workflow'),
      findsWidgets,
    );
    expect(find.textContaining('Lin Researcher'), findsWidgets);
    expect(find.text('10.5555/picklogic.synthetic'), findsNothing);
    await tester.tap(find.byKey(const Key('literature-metadata-action')));
    await tester.pumpAndSettle();
    expect(find.text('10.5555/picklogic.synthetic'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('test-pdf-reader')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('literature-progress-value')))
          .data,
      '35%',
    );
    expect(find.text('第 7 / 20 页'), findsOneWidget);
    await tester.tap(find.byKey(const Key('test-record-page')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('literature-progress-value')))
          .data,
      '80%',
    );
    expect(find.text('第 8 / 10 页'), findsOneWidget);
    expect(store.entries.single.currentPage, 8);
    await tester.tap(find.byKey(const Key('literature-rename-preview-action')));
    await tester.pumpAndSettle();
    expect(find.textContaining('仅预览'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('翻译 · 即将推出'), findsNothing);
  });

  testWidgets(
    'Add literature uses picker, bounded probe, and persistent list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = _MemoryLiteratureStore([]);
      final source = _MemoryPdfSource(
        latin1.encode(
          '%PDF-1.7 /Title (Synthetic added paper) '
          '/Author (Ada Example; Lin Test) /CreationDate (D:20260813) '
          'DOI 10.5555/PICKLOGIC.ADDED %%EOF',
        ),
      );
      await tester.pumpWidget(
        _localizedTestApp(
          locale: const Locale('zh'),
          home: ProWorkspaceRoute(
            key: const Key('add-literature-route'),
            section: 'literature',
            libraryStore: store,
            pdfPicker: () async => r'X:\synthetic\added-paper.pdf',
            pdfSourceBuilder: (_) => source,
            literaturePdfReaderBuilder: (context, entry, onPositionChanged) =>
                const SizedBox(
                  key: Key('added-pdf-reader'),
                  child: Text('Added PDF reader test double'),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('即可开始阅读'), findsOneWidget);
      await tester.tap(find.byKey(const Key('literature-add-action')));
      await tester.pumpAndSettle();

      expect(store.entries, hasLength(1));
      expect(store.entries.single.fileName, 'added-paper.pdf');
      expect(store.entries.single.record.title, 'Synthetic added paper');
      expect(store.entries.single.record.authors, ['Ada Example', 'Lin Test']);
      expect(store.entries.single.record.doi, '10.5555/picklogic.added');
      expect(store.entries.single.record.year, 2026);
      expect(find.byKey(const Key('literature-library-list')), findsOneWidget);
      expect(find.text('Synthetic added paper'), findsWidgets);
      final literatureScrollable = find
          .descendant(
            of: find.byKey(const Key('literature-manager-lite-view')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('added-pdf-reader')),
        300,
        scrollable: literatureScrollable,
      );
      expect(find.byKey(const Key('added-pdf-reader')), findsOneWidget);
      expect(source.requests.length, greaterThan(1));
      expect(
        source.requests.every(
          (request) => request.length < source.bytes.length,
        ),
        isTrue,
      );
    },
  );

  testWidgets('Pro literature strings follow the Desktop 中/EN locale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryLiteratureStore([]);

    Widget build(Locale locale) => _localizedTestApp(
      locale: locale,
      home: ProWorkspaceRoute(section: 'literature', libraryStore: store),
    );

    await tester.pumpWidget(build(const Locale('zh')));
    await tester.pumpAndSettle();
    expect(find.text('文献库'), findsOneWidget);
    expect(find.text('添加文献'), findsOneWidget);
    expect(find.text('文献列表'), findsOneWidget);
    expect(find.text('翻译 · 即将推出'), findsNothing);
    expect(find.textContaining('即可开始阅读'), findsOneWidget);

    await tester.pumpWidget(build(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Literature Library'), findsOneWidget);
    expect(find.text('Add literature'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Translation · Coming next'), findsNothing);
    expect(find.textContaining('to start reading'), findsOneWidget);
    expect(find.text('添加文献'), findsNothing);
  });

  testWidgets('Pro PDF reader controls follow the Desktop 中/EN locale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget build(Locale locale) => _localizedTestApp(
      locale: locale,
      home: Scaffold(
        body: ProLocalPdfReader(
          path: r'X:\synthetic\reader.pdf',
          fileName: 'reader.pdf',
          initialPageNumber: 1,
          onPositionChanged: (_, _) {},
          viewerBuilder: (_) =>
              const SizedBox(key: Key('synthetic-viewer-test-double')),
        ),
      ),
    );

    await tester.pumpWidget(build(const Locale('zh')));
    await tester.pump();
    expect(find.text('本地渲染'), findsOneWidget);
    expect(find.text('搜索 PDF 文本'), findsOneWidget);
    expect(find.text('跳至页'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byKey(const Key('pdf-local-status'))).message,
      contains('不上传、不改写'),
    );

    await tester.pumpWidget(build(const Locale('en')));
    await tester.pump();
    expect(find.text('Local rendering'), findsOneWidget);
    expect(find.text('Search PDF text'), findsOneWidget);
    expect(find.text('Go to page'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byKey(const Key('pdf-local-status'))).message,
      contains('no upload, rewrite'),
    );
    expect(find.text('本地渲染'), findsNothing);
  });

  testWidgets('Pro research route renders all virtual buckets', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const PickLogicDesktopApp(pro: true));
    await tester.ensureVisible(find.text('研究'));
    await tester.tap(find.text('研究'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('research-buckets-view')), findsOneWidget);
    expect(find.byKey(const Key('research-bucket-literature')), findsOneWidget);
    expect(
      find.byKey(const Key('research-bucket-manuscripts')),
      findsOneWidget,
    );
    expect(find.textContaining('不移动文件'), findsWidgets);
  });

  testWidgets('Pro system route is explicit synthetic read-only insight', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const PickLogicDesktopApp(pro: true));
    await tester.ensureVisible(find.text('系统洞察'));
    await tester.tap(find.text('系统洞察'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('system-insight-read-only-view')),
      findsOneWidget,
    );
    expect(find.text('系统洞察 · 只读'), findsOneWidget);
    expect(find.text('不修改系统'), findsOneWidget);
    expect(find.textContaining('未读取真实系统目录'), findsWidgets);
    expect(find.text('查看洞察'), findsNWidgets(3));
    expect(
      find.byKey(const Key('system-insight-dialog-service')),
      findsNothing,
    );
  });

  test('Standard synthetic search requires and ranks every term', () async {
    const repository = SyntheticDesktopRepository();
    final results = await repository.search('paper pdf');
    expect(results.map((record) => record.id), ['paper']);
  });

  test('synthetic literature PDF is deterministic and contains no paths', () {
    final first = buildSyntheticLiteraturePdf();
    final second = buildSyntheticLiteraturePdf();
    expect(first, second);
    final text = String.fromCharCodes(first);
    expect(text, startsWith('%PDF-1.4'));
    expect(text, contains('/Count 2'));
    expect(text, contains('PickLogic synthetic literature sample'));
    expect(text, contains('No real file was read.'));
    expect(text, isNot(contains(r'C:\')));
    expect(text, endsWith('%%EOF\n'));
  });
}

final class _TrackARepository implements DesktopRepository {
  static const drivePath = 'synthetic:/drive';
  static const documentsPath = 'synthetic:/drive/Documents';

  final records = <FileRecord>[
    _record(
      id: 'report',
      name: 'Synthetic report.pdf',
      category: VirtualCategory.pdf,
      size: 30,
    ),
    _record(
      id: 'figure',
      name: 'Synthetic figure.png',
      category: VirtualCategory.images,
      size: 20,
    ),
    _record(
      id: 'duplicate-a',
      name: 'Synthetic duplicate A.txt',
      category: VirtualCategory.documents,
      size: 10,
    ),
    _record(
      id: 'duplicate-b',
      name: 'Synthetic duplicate B.txt',
      category: VirtualCategory.documents,
      size: 10,
    ),
  ];
  final indexedOnlyRecord = _record(
    id: 'indexed-away',
    name: 'Indexed archive.zip',
    category: VirtualCategory.archives,
    size: 64,
  );

  final List<String> opened = <String>[];
  final List<String> revealed = <String>[];
  int commonIndexRuns = 0;
  int duplicateRuns = 0;
  int storageSummaryRuns = 0;

  @override
  Future<List<WindowsBrowseRoot>> browseRoots() async => const [
    WindowsBrowseRoot(
      id: 'drive:synthetic',
      path: drivePath,
      kind: WindowsBrowseRootKind.drive,
    ),
    WindowsBrowseRoot(
      id: 'documents',
      path: documentsPath,
      kind: WindowsBrowseRootKind.documents,
    ),
  ];

  @override
  Future<DirectorySnapshot> browseDirectory(
    String path, {
    int maxEntries = 1000,
  }) async {
    if (path == drivePath) {
      return const DirectorySnapshot(
        path: drivePath,
        parentPath: null,
        crumbs: [BrowseCrumb(label: 'S:', path: drivePath)],
        entries: [
          BrowseEntry(
            id: 'directory:documents',
            path: documentsPath,
            name: 'Documents',
            isDirectory: true,
            sizeBytes: 0,
            modifiedAt: null,
            category: VirtualCategory.unknown,
          ),
        ],
        truncated: false,
      );
    }
    return DirectorySnapshot(
      path: documentsPath,
      parentPath: drivePath,
      crumbs: const [
        BrowseCrumb(label: 'S:', path: drivePath),
        BrowseCrumb(label: 'Documents', path: documentsPath),
      ],
      entries: records
          .map(
            (record) => BrowseEntry(
              id: record.id,
              path: record.locator.value,
              name: record.displayName,
              isDirectory: false,
              sizeBytes: record.sizeBytes,
              modifiedAt: record.modifiedAt,
              category: record.category,
              record: record,
            ),
          )
          .toList(growable: false),
      truncated: false,
    );
  }

  @override
  Future<DesktopDirectoryInspection> inspectDirectory(String path) async {
    if (path == drivePath) {
      return const DesktopDirectoryInspection(
        path: drivePath,
        displayName: 'S:',
        directories: <BrowseEntry>[
          BrowseEntry(
            id: 'directory:documents',
            path: documentsPath,
            name: 'Documents',
            isDirectory: true,
            sizeBytes: 0,
            modifiedAt: null,
            category: VirtualCategory.unknown,
          ),
        ],
        directFileCount: 0,
        directFileBytes: 0,
        mimeFamilyCounts: <String, int>{},
      );
    }
    return const DesktopDirectoryInspection(
      path: documentsPath,
      displayName: 'Documents',
      directories: <BrowseEntry>[],
      directFileCount: 4,
      directFileBytes: 70,
      mimeFamilyCounts: <String, int>{'document': 3, 'image': 1},
    );
  }

  @override
  Future<String?> chooseBrowseFolder({required bool chinese}) async =>
      documentsPath;

  @override
  Future<bool> openBrowseEntry(BrowseEntry entry) async {
    opened.add(entry.id);
    return true;
  }

  @override
  Future<bool> revealBrowseEntry(BrowseEntry entry) async {
    revealed.add(entry.id);
    return true;
  }

  @override
  Stream<DesktopScanProgress> indexCommonFolders() async* {
    commonIndexRuns += 1;
    yield DesktopScanProgress(
      records: records,
      scannedCount: records.length,
      complete: true,
      rootLabel: 'Documents',
    );
  }

  @override
  Stream<DesktopScanProgress> chooseAndScan() async* {
    yield DesktopScanProgress(
      records: records,
      scannedCount: records.length,
      complete: true,
      rootLabel: 'standard-fixtures',
    );
  }

  @override
  Future<void> cancelScan() async {}

  @override
  Future<ExactDuplicateScanResult> findExactDuplicates(
    Iterable<FileRecord> source,
  ) async {
    duplicateRuns += 1;
    final hashed = source
        .map(
          (record) => record.id.startsWith('duplicate-')
              ? record.copyWith(
                  hashState: HashState.complete,
                  sha256:
                      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                )
              : record,
        )
        .toList(growable: false);
    return ExactDuplicateScanResult(
      records: hashed,
      groups: [
        hashed.where((record) => record.id.startsWith('duplicate-')).toList(),
      ],
      hashedCount: 2,
      failedCount: 0,
    );
  }

  @override
  Future<bool> open(FileRecord record) async {
    opened.add(record.id);
    return true;
  }

  @override
  Future<bool> reveal(FileRecord record) async {
    revealed.add(record.id);
    return true;
  }

  @override
  Future<List<FileRecord>> search(String query) async =>
      [...records, indexedOnlyRecord]
          .where(
            (record) => record.displayName.toLowerCase().contains(
              query.trim().toLowerCase(),
            ),
          )
          .toList(growable: false);

  @override
  Future<WindowsStorageSummary?> systemDriveSummary() async {
    storageSummaryRuns += 1;
    return const WindowsStorageSummary(
      root: 'S:\\',
      totalBytes: 100,
      availableBytes: 40,
    );
  }
}

FileRecord _record({
  required String id,
  required String name,
  required VirtualCategory category,
  required int size,
}) => FileRecord(
  id: id,
  locator: FileLocator(
    value: 'synthetic://standard/$id',
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
  ),
  displayName: name,
  extension: name.split('.').last.toLowerCase(),
  mimeType: '',
  sizeBytes: size,
  createdAt: DateTime.utc(2026, 8, 13),
  modifiedAt: DateTime.utc(2026, 8, 13),
  parentLocator: null,
  sourceKind: SourceKind.synthetic,
  platform: PickLogicPlatform.synthetic,
  isHidden: false,
  isSystem: false,
  isAccessible: true,
  isProtected: false,
  category: category,
  hashState: HashState.notRequested,
  ocrState: OcrState.notRequested,
);

Widget _localizedTestApp({required Locale locale, required Widget home}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: PickLogicLocalizations.supportedLocales,
      localizationsDelegates: const [
        PickLogicLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

final class _MemoryLiteratureStore implements LiteratureLibraryStore {
  _MemoryLiteratureStore(List<LiteratureLibraryEntry> entries)
    : entries = List<LiteratureLibraryEntry>.of(entries);

  List<LiteratureLibraryEntry> entries;

  @override
  Future<List<LiteratureLibraryEntry>> load() async =>
      List<LiteratureLibraryEntry>.unmodifiable(entries);

  @override
  Future<void> save(List<LiteratureLibraryEntry> entries) async {
    this.entries = List<LiteratureLibraryEntry>.of(entries);
  }
}

final class _MemoryPdfSource implements PdfByteSource {
  _MemoryPdfSource(this.bytes);

  final List<int> bytes;
  final List<({int offset, int length})> requests = [];

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<List<int>> readRange({
    required int offset,
    required int length,
  }) async {
    requests.add((offset: offset, length: length));
    final end = (offset + length).clamp(0, bytes.length);
    return bytes.sublist(offset, end);
  }
}
