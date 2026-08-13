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
                  'sourceHint': 'com.example.synthetic',
                },
              ],
              'offset': 0,
              'hasMore': true,
            },
            'countMedia' => 37,
            'loadThumbnail' => Uint8List.fromList(<int>[1, 2, 3, 4]),
            'getStorageSnapshot' => <String, Object>{
              'totalBytes': 1000,
              'availableBytes': 400,
              'canInspectSharedMedia': true,
              'canInspectOtherAppPrivateData': false,
              'canInspectDownloads': false,
              'isAggregateOnly': true,
              'canClean': false,
              'systemRestriction': 'restricted',
              'limitations': <String>['aggregate only'],
            },
            'getPrivateIndexDatabasePath' =>
              'synthetic-private/picklogic-index.sqlite3',
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
    expect(page.items.single.sourceHint, 'com.example.synthetic');
    expect(page.hasMore, isTrue);
    expect(await platform.countMedia(AndroidMediaKind.screenshots), 37);
  });

  test('requests a strictly bounded thumbnail', () async {
    final thumbnail = await platform.loadThumbnail(
      const AndroidThumbnailRequest(
        contentUri: 'content://media/1',
        maxWidth: 160,
        maxHeight: 120,
        maxBytes: 4096,
      ),
    );
    expect(thumbnail?.bytes, <int>[1, 2, 3, 4]);
  });

  test('parses permission and storage restrictions', () async {
    final permission = await platform.getMediaPermissionState();
    final requested = await platform.requestMediaPermissions();
    final storage = await platform.getStorageSnapshot();
    expect(permission.images, isTrue);
    expect(requested.audio, isTrue);
    expect(storage.canInspectOtherAppPrivateData, isFalse);
    expect(storage.isAggregateOnly, isTrue);
    expect(storage.canClean, isFalse);
    expect(storage.limitations, <String>['aggregate only']);
  });

  test('delegates user-triggered SAF and open actions', () async {
    expect(await platform.pickDocumentTree(), 'content://tree/test');
    expect(await platform.openContentUri('content://media/1'), isTrue);
  });

  test('returns a fixed app-private index path', () async {
    expect(
      await platform.getPrivateIndexDatabasePath(),
      endsWith('picklogic-index.sqlite3'),
    );
  });
}
