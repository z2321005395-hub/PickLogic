import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

void main() {
  testWidgets('safe mode banner follows locale without mixed labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: PickLogicTokens.lightTheme(),
        home: const Scaffold(body: SafeModeBanner()),
      ),
    );
    expect(find.text('开发者安全模式：已开启，真实文件只读'), findsOneWidget);
    expect(find.textContaining('Developer'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: PickLogicTokens.lightTheme(),
        home: const Scaffold(body: SafeModeBanner()),
      ),
    );
    expect(
      find.text('Developer Safe Mode: On, real files are read-only'),
      findsOneWidget,
    );
    expect(find.textContaining('开发者'), findsNothing);
  });

  testWidgets('Insight labels and separators strictly follow locale', (
    tester,
  ) async {
    const insight = InsightRecord(
      summary: 'Synthetic summary',
      fileType: 'Synthetic type',
      riskLevel: RiskLevel.review,
      confidence: 0.8,
      limitations: ['Synthetic limitation'],
      evidence: [
        InsightEvidence(
          kind: EvidenceKind.fact,
          statement: 'Synthetic fact',
          source: 'Synthetic source',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: InsightPanel(insight: insight)),
      ),
    );
    expect(find.text('知件'), findsOneWidget);
    expect(find.text('类型'), findsOneWidget);
    expect(find.text('风险'), findsOneWidget);
    expect(find.textContaining('事实: Synthetic source'), findsOneWidget);
    expect(find.textContaining('限制: Synthetic limitation'), findsOneWidget);
    expect(find.textContaining('Insight'), findsNothing);
    expect(find.textContaining('·'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: InsightPanel(insight: insight)),
      ),
    );
    expect(find.text('Insight'), findsOneWidget);
    expect(find.text('Type'), findsOneWidget);
    expect(find.text('Risk'), findsOneWidget);
    expect(find.textContaining('Fact: Synthetic source'), findsOneWidget);
    expect(find.textContaining('Limit: Synthetic limitation'), findsOneWidget);
    expect(find.textContaining('知件'), findsNothing);
    expect(find.textContaining('·'), findsNothing);
  });
}
