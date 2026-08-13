import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_desktop/src/app.dart';
import 'package:picklogic_desktop/src/desktop_repository.dart';
import 'package:picklogic_desktop/src/pro_pdf_reader.dart';
import 'package:picklogic_duplicate_engine/picklogic_duplicate_engine.dart';
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

  testWidgets('Pro literature route shows bounded synthetic vertical slice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 650));
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
    await tester.tap(find.text('文献 · Literature'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('literature-manager-lite-view')),
      findsOneWidget,
    );
    expect(find.text('Literature Manager Lite'), findsOneWidget);
    expect(find.text('10.5555/picklogic.synthetic'), findsOneWidget);
    expect(find.byKey(const Key('test-pdf-reader')), findsOneWidget);
    expect(find.text('Embedded PDF reader test double'), findsOneWidget);
    final literatureScrollable = find
        .descendant(
          of: find.byKey(const Key('literature-manager-lite-view')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('literature-progress-value')),
      240,
      scrollable: literatureScrollable,
    );
    expect(find.text('35%'), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.8);
    await tester.pump();
    expect(find.text('80%'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Preview only'),
      300,
      scrollable: literatureScrollable,
    );
    expect(find.textContaining('Preview only'), findsOneWidget);
  });

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
