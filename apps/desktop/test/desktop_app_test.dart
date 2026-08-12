import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_desktop/src/app.dart';
import 'package:picklogic_desktop/src/desktop_repository.dart';

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

  test('Standard synthetic search requires and ranks every term', () async {
    const repository = SyntheticDesktopRepository();
    final results = await repository.search('paper pdf');
    expect(results.map((record) => record.id), ['paper']);
  });
}
