import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge_platform_interface.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPicklogicAndroidBridgePlatform
    with MockPlatformInterfaceMixin
    implements PicklogicAndroidBridgePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<AndroidMediaPermissionState> getMediaPermissionState() async =>
      const AndroidMediaPermissionState(
        images: false,
        videos: false,
        audio: false,
        partialVisualAccess: false,
      );

  @override
  Future<AndroidMediaPermissionState> requestMediaPermissions() =>
      getMediaPermissionState();

  @override
  Future<AndroidMediaPage> queryMediaPage(AndroidMediaQuery query) async =>
      const AndroidMediaPage(items: [], offset: 0, hasMore: false);

  @override
  Future<int> countMedia(AndroidMediaKind kind) async => 7;

  @override
  Future<AndroidThumbnail?> loadThumbnail(
    AndroidThumbnailRequest request,
  ) async => AndroidThumbnail(bytes: Uint8List.fromList(<int>[1, 2, 3]));

  @override
  Future<AndroidStorageSnapshot> getStorageSnapshot() async =>
      const AndroidStorageSnapshot(
        totalBytes: 100,
        availableBytes: 40,
        canInspectSharedMedia: false,
        canInspectOtherAppPrivateData: false,
        systemRestriction: 'restricted',
      );

  @override
  Future<String> getPrivateIndexDatabasePath() async =>
      'synthetic-private/picklogic-index.sqlite3';

  @override
  Future<String?> pickDocumentTree() async => 'content://tree/test';

  @override
  Future<bool> openContentUri(String contentUri) async =>
      contentUri.startsWith('content://');

  @override
  Future<AndroidPreviewImage?> loadPreviewImage(String contentUri) async =>
      AndroidPreviewImage(bytes: Uint8List.fromList(<int>[1, 2, 3]));

  @override
  Future<AndroidTextPreview> loadTextPreview(String contentUri) async =>
      const AndroidTextPreview(text: 'preview', truncated: false);

  @override
  Future<AndroidArchiveListing> listArchive(String contentUri) async =>
      const AndroidArchiveListing(
        entries: <AndroidArchiveEntry>[],
        totalEntries: 0,
        truncated: false,
      );

  @override
  Future<AndroidApkDetails> inspectApk(String contentUri) async =>
      const AndroidApkDetails(
        applicationName: 'PickLogic test',
        packageName: 'io.picklogic.test',
        versionName: '1',
        versionCode: 1,
        signed: true,
        installed: false,
      );

  @override
  Future<AndroidPdfInfo> getPdfInfo(String contentUri) async =>
      const AndroidPdfInfo(pageCount: 2);

  @override
  Future<AndroidOfficePreview> inspectOffice(
    String contentUri, {
    required String extension,
  }) async => const AndroidOfficePreview(
    kind: 'docx',
    title: 'Fixture',
    sections: <String>['Bounded preview'],
    gridRows: <List<String>>[],
    imageCount: 1,
    itemCount: 2,
    truncated: false,
  );

  @override
  Future<AndroidPreviewImage> renderPdfPage(
    String contentUri, {
    required int pageIndex,
    required int maxWidth,
    required int maxHeight,
  }) async => AndroidPreviewImage(bytes: Uint8List.fromList(<int>[4, 5, 6]));

  @override
  Future<int?> readIntPreference(String key) async => 4;

  @override
  Future<void> writeIntPreference(String key, int value) async {}

  static const workspace = AndroidWorkspaceState(
    authorized: true,
    treeUri: 'content://tree/workspace',
    entries: <AndroidWorkspaceEntry>[],
    undoAvailable: false,
  );

  @override
  Future<AndroidWorkspaceState> getTestWorkspaceState() async => workspace;

  @override
  Future<AndroidWorkspaceState?> pickTestWorkspaceTree() async => workspace;

  @override
  Future<AndroidWorkspaceState?> importTestWorkspaceCopies() async => workspace;

  @override
  Future<AndroidWorkspaceState> createTestWorkspaceFolder({
    String? parentUri,
    required String name,
  }) async => workspace;

  @override
  Future<AndroidWorkspaceState> renameTestWorkspaceItem({
    required String documentUri,
    required String name,
  }) async => workspace;

  @override
  Future<AndroidWorkspaceState> moveTestWorkspaceItem({
    required String documentUri,
    required String sourceParentUri,
    required String targetParentUri,
  }) async => workspace;

  @override
  Future<AndroidWorkspaceState> trashTestWorkspaceItem({
    required String documentUri,
    required String sourceParentUri,
  }) async => workspace;

  @override
  Future<AndroidWorkspaceState> undoTestWorkspaceOperation({
    String? operationId,
  }) async => workspace;

  @override
  Future<bool> requestSystemTrash(List<String> contentUris) async => true;
}

void main() {
  final PicklogicAndroidBridgePlatform initialPlatform =
      PicklogicAndroidBridgePlatform.instance;

  test('$MethodChannelPicklogicAndroidBridge is the default instance', () {
    expect(
      initialPlatform,
      isInstanceOf<MethodChannelPicklogicAndroidBridge>(),
    );
  });

  test('getPlatformVersion', () async {
    const picklogicAndroidBridgePlugin = PicklogicAndroidBridge();
    MockPicklogicAndroidBridgePlatform fakePlatform =
        MockPicklogicAndroidBridgePlatform();
    PicklogicAndroidBridgePlatform.instance = fakePlatform;

    expect(await picklogicAndroidBridgePlugin.getPlatformVersion(), '42');
  });

  test('delegates bounded media and storage calls', () async {
    const bridge = PicklogicAndroidBridge();
    final state = await bridge.getMediaPermissionState();
    final page = await bridge.queryMediaPage(
      const AndroidMediaQuery(kind: AndroidMediaKind.screenshots),
    );
    final count = await bridge.countMedia(AndroidMediaKind.screenshots);
    final storage = await bridge.getStorageSnapshot();
    final indexPath = await bridge.getPrivateIndexDatabasePath();
    final thumbnail = await bridge.loadThumbnail(
      const AndroidThumbnailRequest(
        contentUri: 'content://media/1',
        maxWidth: 128,
        maxHeight: 96,
      ),
    );
    final tree = await bridge.pickDocumentTree();
    final opened = await bridge.openContentUri('content://media/1');

    expect(state.canReadVisualMedia, isFalse);
    expect(page.items, isEmpty);
    expect(count, 7);
    expect(storage.canInspectOtherAppPrivateData, isFalse);
    expect(indexPath, endsWith('picklogic-index.sqlite3'));
    expect(thumbnail?.bytes, <int>[1, 2, 3]);
    expect(tree, 'content://tree/test');
    expect(opened, isTrue);
  });

  test('thumbnail requests enforce URI, dimension, and byte bounds', () {
    expect(
      () => const AndroidThumbnailRequest(
        contentUri: 'file:///private/image.png',
        maxWidth: 128,
        maxHeight: 128,
      ).toMap(),
      throwsArgumentError,
    );
    expect(
      () => const AndroidThumbnailRequest(
        contentUri: 'content://media/1',
        maxWidth: 513,
        maxHeight: 128,
      ).toMap(),
      throwsRangeError,
    );
  });

  test('permission state distinguishes full and selected visual access', () {
    const full = AndroidMediaPermissionState(
      images: true,
      videos: true,
      audio: true,
      partialVisualAccess: false,
    );
    const selected = AndroidMediaPermissionState(
      images: false,
      videos: false,
      audio: false,
      partialVisualAccess: true,
    );

    expect(full.canReadVisualMedia, isTrue);
    expect(full.videos, isTrue);
    expect(full.audio, isTrue);
    expect(selected.canReadImages, isTrue);
    expect(selected.videos, isFalse);
    expect(selected.audio, isFalse);
  });
}
