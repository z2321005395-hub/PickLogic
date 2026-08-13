import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_desktop/src/app.dart';
import 'package:picklogic_desktop/src/desktop_repository.dart';
import 'package:picklogic_desktop/src/pro_pdf_reader.dart';
import 'package:picklogic_desktop/src/pro_workspace.dart';
import 'package:picklogic_duplicate_engine/picklogic_duplicate_engine.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

void main() {
  testWidgets('Standard shows safe mode and omits Pro navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const PickLogicDesktopApp(pro: false));
    await tester.pumpAndSettle();
    expect(find.text('Developer Safe Mode: ON'), findsOneWidget);
    expect(
      find.text('Developer Safe Mode — real files are read-only.'),
      findsWidgets,
    );
    expect(find.text('选择文件夹 · 只读扫描'), findsOneWidget);
    expect(find.textContaining('文献'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '移动'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '重命名'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '删除'))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'Standard selected-folder flow exposes categories search duplicates and shell actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _TrackARepository();
      await tester.pumpWidget(
        PickLogicDesktopApp(pro: false, repository: repository),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('选择文件夹 · 只读扫描'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('record-report')), findsOneWidget);
      expect(find.byKey(const ValueKey('record-figure')), findsOneWidget);
      expect(find.text('standard-fixtures · 4 items'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '图片'));
      await tester.pump();
      expect(find.byKey(const ValueKey('record-figure')), findsOneWidget);
      expect(find.byKey(const ValueKey('record-report')), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
      await tester.enterText(find.byType(TextField), 'report');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('record-report')), findsOneWidget);
      expect(find.byKey(const ValueKey('record-figure')), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      await tester.tap(find.text('重复项 · Duplicates'));
      await tester.pumpAndSettle();
      expect(find.textContaining('精确重复项：1 组 · 2 个文件'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-duplicate-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('record-duplicate-b')), findsOneWidget);
      expect(find.byKey(const ValueKey('record-report')), findsNothing);

      await tester.tap(find.text('Synthetic duplicate A.txt'));
      await tester.tap(find.widgetWithText(FilledButton, '打开'));
      await tester.tap(find.widgetWithText(OutlinedButton, '原位置定位'));
      await tester.pump();
      expect(repository.opened, ['duplicate-a']);
      expect(repository.revealed, ['duplicate-a']);
      expect(find.text('知件 · Insight'), findsOneWidget);
      expect(find.textContaining('locally indexed documents'), findsOneWidget);
    },
  );

  testWidgets('Pro composes literature and system navigation', (tester) async {
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
    expect(find.textContaining('文献'), findsOneWidget);
    expect(find.text('系统洞察'), findsOneWidget);
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
      MaterialApp(
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
    expect(find.text('Literature Manager Lite'), findsOneWidget);
    expect(find.text('paper.pdf'), findsWidgets);
    expect(
      find.text('Local-first synthetic literature workflow'),
      findsWidgets,
    );
    expect(find.textContaining('Lin Researcher'), findsWidgets);
    expect(find.text('10.5555/picklogic.synthetic'), findsOneWidget);
    final literatureScrollable = find
        .descendant(
          of: find.byKey(const Key('literature-manager-lite-view')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('test-pdf-reader')),
      300,
      scrollable: literatureScrollable,
    );
    expect(find.byKey(const Key('test-pdf-reader')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('literature-progress-value')),
      240,
      scrollable: literatureScrollable,
    );
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
    await tester.scrollUntilVisible(
      find.textContaining('Preview only'),
      300,
      scrollable: literatureScrollable,
    );
    expect(find.textContaining('Preview only'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Translation · Coming next'),
      300,
      scrollable: literatureScrollable,
    );
    expect(find.text('Translation · Coming next'), findsOneWidget);
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
        MaterialApp(
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

      expect(find.textContaining('暂无文献'), findsOneWidget);
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

  testWidgets('Pro research route renders all virtual buckets', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const PickLogicDesktopApp(pro: true));
    await tester.ensureVisible(find.text('研究 · Research'));
    await tester.tap(find.text('研究 · Research'));
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
    expect(find.text('System Insight · Read-only'), findsOneWidget);
    expect(find.text('NO SYSTEM CHANGES'), findsOneWidget);
    expect(find.textContaining('未读取真实系统目录'), findsOneWidget);
    expect(find.textContaining('platformRestriction'), findsWidgets);
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

  final List<String> opened = <String>[];
  final List<String> revealed = <String>[];

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
  Future<List<FileRecord>> search(String query) async => records
      .where(
        (record) => record.displayName.toLowerCase().contains(
          query.trim().toLowerCase(),
        ),
      )
      .toList(growable: false);

  @override
  Future<WindowsStorageSummary?> systemDriveSummary() async => null;
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
