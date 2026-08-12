import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_desktop/src/app.dart';

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
    await tester.pumpWidget(const PickLogicDesktopApp(pro: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('文献'), findsOneWidget);
    expect(find.text('系统洞察'), findsOneWidget);
  });
}
