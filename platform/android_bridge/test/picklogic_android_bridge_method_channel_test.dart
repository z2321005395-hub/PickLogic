import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelPicklogicAndroidBridge platform =
      MethodChannelPicklogicAndroidBridge();
  const MethodChannel channel = MethodChannel('picklogic_android_bridge');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return switch (methodCall.method) {
            'getPlatformVersion' => '42',
            'getMediaPermissionState' => <String, Object>{
              'images': true,
              'videos': false,
              'audio': false,
              'partialVisualAccess': false,
            },
            'requestMediaPermissions' => <String, Object>{
              'images': true,
              'videos': true,
              'audio': true,
              'partialVisualAccess': false,
            },
            'queryMediaPage' => <String, Object>{
              'items': <Object>[
                <String, Object>{
                  'id': 'screenshots:1',
                  'contentUri': 'content://media/1',
                  'displayName': 'Screenshot_1.png',
                  'mimeType': 'image/png',
                  'sizeBytes': 120,
                  'createdAtEpochSeconds': 10,
                  'modifiedAtEpochSeconds': 12,
                  'relativePath': 'Pictures/Screenshots/',
                },
              ],
              'offset': 0,
              'hasMore': true,
            },
            'getStorageSnapshot' => <String, Object>{
              'totalBytes': 1000,
              'availableBytes': 400,
              'canInspectSharedMedia': true,
              'canInspectOtherAppPrivateData': false,
              'systemRestriction': 'restricted',
            },
            'pickDocumentTree' => 'content://tree/test',
            'openContentUri' => true,
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

  test('parses media metadata without file contents', () async {
    final page = await platform.queryMediaPage(
      const AndroidMediaQuery(kind: AndroidMediaKind.screenshots, limit: 20),
    );
    expect(page.items.single.contentUri, 'content://media/1');
    expect(page.items.single.relativePath, 'Pictures/Screenshots/');
    expect(page.hasMore, isTrue);
  });

  test('parses permission and storage restrictions', () async {
    final permission = await platform.getMediaPermissionState();
    final requested = await platform.requestMediaPermissions();
    final storage = await platform.getStorageSnapshot();
    expect(permission.images, isTrue);
    expect(requested.audio, isTrue);
    expect(storage.canInspectOtherAppPrivateData, isFalse);
  });

  test('delegates user-triggered SAF and open actions', () async {
    expect(await platform.pickDocumentTree(), 'content://tree/test');
    expect(await platform.openContentUri('content://media/1'), isTrue);
  });
}
