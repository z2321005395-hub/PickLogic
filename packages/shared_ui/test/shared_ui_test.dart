import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

void main() {
  testWidgets('safe mode banner is visible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PickLogicTokens.lightTheme(),
        home: const Scaffold(body: SafeModeBanner()),
      ),
    );
    expect(find.text('Developer Safe Mode: ON'), findsOneWidget);
  });
}
