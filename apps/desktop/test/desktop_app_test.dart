import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_desktop/src/app.dart';
import 'package:picklogic_desktop/src/desktop_repository.dart';
import 'package:picklogic_desktop/src/pro_pdf_reader.dart';

void main() {
  testWidgets('Standard shows safe mode and omits Pro navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicDesktopApp(pro: false));
    await tester.pumpAndSettle();
    expect(find.text('Developer Safe Mode: ON'), findsOneWidget);
    expect(find.textContaining('文献'), findsNothing);
  });

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
