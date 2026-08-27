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
            'getBrowseRoots' => <Object>[
              <String, Object>{
                'treeUri': 'content://tree/test',
                'documentUri': 'content://tree/test/document/root',
                'displayName': 'Documents',
              },
            ],
            'listBrowseDirectory' => <String, Object>{
              'treeUri': 'content://tree/test',
              'directoryUri': 'content://tree/test/document/root',
              'directoryName': 'Documents',
              'items': <Object>[
                <String, Object>{
                  'documentUri':
                      'content://tree/test/document/root%2Fpaper.pdf',
                  'parentUri': 'content://tree/test/document/root',
                  'displayName': 'paper.pdf',
                  'mimeType': 'application/pdf',
                  'directory': false,
                  'sizeBytes': 4096,
                  'modifiedAtMillis': 1000,
                },
              ],
              'offset': 0,
              'hasMore': false,
            },
            'inspectBrowseDirectory' => <String, Object>{
              'treeUri': 'content://tree/test',
              'directoryUri': 'content://tree/test/document/root',
              'directoryName': 'Documents',
              'directories': <Object>[],
              'directFileCount': 4,
              'directFileBytes': 8192,
              'mimeFamilyCounts': <String, Object>{'document': 4},
            },
            'openContentUri' => true,
            'loadPreviewImage' => Uint8List.fromList(<int>[1, 2, 3]),
            'loadTextPreview' => <String, Object>{
              'text': 'bounded text',
              'truncated': false,
            },
            'listArchive' => <String, Object>{
              'entries': <Object>[
                <String, Object>{
                  'name': 'folder/readme.txt',
                  'directory': false,
                  'sizeBytes': 20,
                  'compressedBytes': 12,
                },
              ],
              'totalEntries': 1,
              'truncated': false,
            },
            'inspectApk' => <String, Object>{
              'applicationName': 'Fixture',
              'packageName': 'io.picklogic.fixture',
              'versionName': '1.0',
              'versionCode': 1,
              'signed': true,
              'installed': false,
            },
            'getPdfInfo' => <String, Object>{'pageCount': 3},
            'inspectOffice' => <String, Object>{
              'kind': 'docx',
              'title': 'Fixture',
              'sections': <String>['Bounded preview'],
              'gridRows': <Object>[],
              'imageCount': 1,
              'itemCount': 2,
              'truncated': false,
            },
            'renderPdfPage' => Uint8List.fromList(<int>[4, 5, 6]),
            'readIntPreference' => 4,
            'writeIntPreference' => null,
            'getTestWorkspaceState' => <String, Object?>{
              'authorized': true,
              'treeUri': 'content://tree/workspace',
              'entries': <Object>[],
              'undoAvailable': false,
            },
            'requestSystemTrash' => true,
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
    expect(requested.images, isTrue);
    expect(requested.videos, isTrue);
    expect(requested.audio, isTrue);
    expect(storage.canInspectOtherAppPrivateData, isFalse);
    expect(storage.isAggregateOnly, isTrue);
    expect(storage.canClean, isFalse);
    expect(storage.limitations, <String>['aggregate only']);
  });

  test('delegates user-triggered SAF and open actions', () async {
    expect(await platform.pickDocumentTree(), 'content://tree/test');
    final roots = await platform.getBrowseRoots();
    final page = await platform.listBrowseDirectory(
      treeUri: roots.single.treeUri,
      directoryUri: roots.single.documentUri,
    );
    final inspection = await platform.inspectBrowseDirectory(
      treeUri: roots.single.treeUri,
      directoryUri: roots.single.documentUri,
    );
    expect(roots.single.displayName, 'Documents');
    expect(page.directoryName, 'Documents');
    expect(page.items.single.displayName, 'paper.pdf');
    expect(inspection.directFileCount, 4);
    expect(inspection.directFileBytes, 8192);
    expect(await platform.openContentUri('content://media/1'), isTrue);
  });

  test('returns a fixed app-private index path', () async {
    expect(
      await platform.getPrivateIndexDatabasePath(),
      endsWith('picklogic-index.sqlite3'),
    );
  });

  test('parses internal viewers and SAF workspace state', () async {
    expect((await platform.loadPreviewImage('content://media/1'))?.bytes, <int>[
      1,
      2,
      3,
    ]);
    expect(
      (await platform.loadTextPreview('content://media/1')).text,
      'bounded text',
    );
    expect(
      (await platform.listArchive(
        'content://media/1',
      )).entries.single.compressedBytes,
      12,
    );
    expect(
      (await platform.inspectApk('content://media/1')).packageName,
      'io.picklogic.fixture',
    );
    expect((await platform.getPdfInfo('content://media/1')).pageCount, 3);
    expect(
      (await platform.inspectOffice(
        'content://media/1',
        extension: 'docx',
      )).title,
      'Fixture',
    );
    expect(
      (await platform.renderPdfPage(
        'content://media/1',
        pageIndex: 0,
        maxWidth: 800,
        maxHeight: 1000,
      )).bytes,
      <int>[4, 5, 6],
    );
    expect(await platform.readIntPreference('photoGridColumns'), 4);
    expect((await platform.getTestWorkspaceState()).authorized, isTrue);
    expect(
      await platform.requestSystemTrash(<String>['content://media/1']),
      isTrue,
    );
  });
}
