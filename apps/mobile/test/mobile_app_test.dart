import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_mobile/main.dart';

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
  });

  testWidgets('screenshot route uses review-safe language', (tester) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.tap(find.text('截图'));
    await tester.pumpAndSettle();
    expect(find.textContaining('加入删除审查'), findsOneWidget);
    expect(find.textContaining('来源线索不是应用归属结论'), findsOneWidget);
    expect(find.textContaining('未运行 OCR'), findsOneWidget);
    expect(find.textContaining('一键放心删除'), findsNothing);
  });

  testWidgets('storage insight exposes platform and attribution limits', (
    tester,
  ) async {
    await tester.pumpWidget(const PickLogicMobileApp());
    await tester.tap(find.text('存储'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Storage Insight'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('明确限制'), findsOneWidget);
    expect(find.textContaining('无法枚举或归因'), findsOneWidget);
    expect(find.textContaining('不提供清理按钮'), findsOneWidget);
    expect(find.textContaining('不调度 OCR'), findsOneWidget);
  });
}
