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
    expect(find.textContaining('一键放心删除'), findsNothing);
  });
}
