import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_desktop/src/desktop_folder_insight.dart';
import 'package:picklogic_desktop/src/desktop_repository.dart';
import 'package:picklogic_insight_engine/picklogic_insight_engine.dart';

void main() {
  const repository = SyntheticDesktopRepository();

  test('desktop scanner explains every synthetic subfolder', () async {
    final result = await const DesktopFolderInsightService(
      repository,
    ).scan('synthetic:/drive');

    expect(result.complete, isTrue);
    expect(result.insights, hasLength(2));
    expect(
      result.insights
          .singleWhere(
            (insight) => insight.observation.displayName == 'Documents',
          )
          .role,
      FolderRole.documents,
    );
  });

  testWidgets('storage card starts analysis immediately after folder choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DesktopFolderInsightCard(
              repository: repository,
              chinese: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('选择目录并开始分析'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-folder-insight-choose')));
    await tester.pumpAndSettle();

    expect(find.textContaining('已解释 1 个文件夹'), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-folder-insight-view-all')),
      findsOneWidget,
    );
  });

  testWidgets('selected folder details separate facts and inference', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopSelectedFolderInsight(
            repository: repository,
            path: 'synthetic:/drive/Documents',
            chinese: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('这是什么'), findsOneWidget);
    expect(find.text('已验证事实'), findsOneWidget);
    expect(find.text('规则推断'), findsOneWidget);
    expect(find.textContaining('文档目录'), findsWidgets);
  });
}
