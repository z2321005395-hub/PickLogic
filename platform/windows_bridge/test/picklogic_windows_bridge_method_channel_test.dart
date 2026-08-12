import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelPicklogicWindowsBridge platform =
      MethodChannelPicklogicWindowsBridge();
  const MethodChannel channel = MethodChannel('picklogic_windows_bridge');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return switch (methodCall.method) {
            'getPlatformVersion' => '42',
            'pickDirectory' => 'synthetic-root',
            'openItem' || 'revealItem' => true,
            'getPathAttributes' => <String, Object>{
              'hidden': true,
              'system': false,
              'readOnly': false,
              'directory': false,
            },
            'getSystemDriveSummary' => <String, Object>{
              'root': 'synthetic-root',
              'totalBytes': 1000,
              'availableBytes': 250,
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('parses path attributes and system storage', () async {
    final attributes = await platform.getPathAttributes('synthetic');
    final storage = await platform.getSystemDriveSummary();
    expect(attributes!.hidden, isTrue);
    expect(storage.totalBytes, 1000);
  });

  test('delegates folder, open, and reveal actions', () async {
    expect(await platform.pickDirectory(title: 'Pick'), 'synthetic-root');
    expect(await platform.openItem('synthetic'), isTrue);
    expect(await platform.revealItem('synthetic'), isTrue);
  });
}
