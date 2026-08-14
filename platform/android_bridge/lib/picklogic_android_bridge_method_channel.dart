import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'picklogic_android_bridge_platform_interface.dart';
import 'src/android_media.dart';

/// An implementation of [PicklogicAndroidBridgePlatform] that uses method channels.
class MethodChannelPicklogicAndroidBridge
    extends PicklogicAndroidBridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('picklogic_android_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<AndroidMediaPermissionState> getMediaPermissionState() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getMediaPermissionState',
    );
    return AndroidMediaPermissionState.fromMap(raw!);
  }

  @override
  Future<AndroidMediaPermissionState> requestMediaPermissions() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'requestMediaPermissions',
    );
    return AndroidMediaPermissionState.fromMap(raw!);
  }

  @override
  Future<AndroidMediaPage> queryMediaPage(AndroidMediaQuery query) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'queryMediaPage',
      query.toMap(),
    );
    return AndroidMediaPage.fromMap(raw!);
  }

  @override
  Future<int> countMedia(AndroidMediaKind kind) async =>
      await methodChannel.invokeMethod<int>('countMedia', <String, Object>{
        'kind': kind.name,
      }) ??
      0;

  @override
  Future<AndroidThumbnail?> loadThumbnail(
    AndroidThumbnailRequest request,
  ) async {
    final bytes = await methodChannel.invokeMethod<Uint8List>(
      'loadThumbnail',
      request.toMap(),
    );
    return bytes == null
        ? null
        : AndroidThumbnail.fromBytes(bytes, maxBytes: request.maxBytes);
  }

  @override
  Future<AndroidStorageSnapshot> getStorageSnapshot() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getStorageSnapshot',
    );
    return AndroidStorageSnapshot.fromMap(raw!);
  }

  @override
  Future<String> getPrivateIndexDatabasePath() async {
    final path = await methodChannel.invokeMethod<String>(
      'getPrivateIndexDatabasePath',
    );
    if (path == null || path.trim().isEmpty) {
      throw const FormatException(
        'Android returned an invalid private index database path.',
      );
    }
    return path;
  }

  @override
  Future<String?> pickDocumentTree() =>
      methodChannel.invokeMethod<String>('pickDocumentTree');

  @override
  Future<bool> openContentUri(String contentUri) async =>
      await methodChannel.invokeMethod<bool>(
        'openContentUri',
        <String, Object?>{'contentUri': contentUri},
      ) ??
      false;

  @override
  Future<AndroidPreviewImage?> loadPreviewImage(String contentUri) async {
    final bytes = await methodChannel.invokeMethod<Uint8List>(
      'loadPreviewImage',
      <String, Object>{'contentUri': contentUri},
    );
    return bytes == null ? null : AndroidPreviewImage.fromBytes(bytes);
  }

  @override
  Future<AndroidTextPreview> loadTextPreview(String contentUri) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'loadTextPreview',
      <String, Object>{'contentUri': contentUri},
    );
    return AndroidTextPreview.fromMap(raw!);
  }

  @override
  Future<AndroidArchiveListing> listArchive(String contentUri) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'listArchive',
      <String, Object>{'contentUri': contentUri},
    );
    return AndroidArchiveListing.fromMap(raw!);
  }

  @override
  Future<AndroidApkDetails> inspectApk(String contentUri) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'inspectApk',
      <String, Object>{'contentUri': contentUri},
    );
    return AndroidApkDetails.fromMap(raw!);
  }

  @override
  Future<AndroidPdfInfo> getPdfInfo(String contentUri) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getPdfInfo',
      <String, Object>{'contentUri': contentUri},
    );
    return AndroidPdfInfo.fromMap(raw!);
  }

  @override
  Future<AndroidOfficePreview> inspectOffice(
    String contentUri, {
    required String extension,
  }) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'inspectOffice',
      <String, Object>{'contentUri': contentUri, 'extension': extension},
    );
    return AndroidOfficePreview.fromMap(raw!);
  }

  @override
  Future<AndroidPreviewImage> renderPdfPage(
    String contentUri, {
    required int pageIndex,
    required int maxWidth,
    required int maxHeight,
  }) async {
    final bytes = await methodChannel
        .invokeMethod<Uint8List>('renderPdfPage', <String, Object>{
          'contentUri': contentUri,
          'pageIndex': pageIndex,
          'maxWidth': maxWidth,
          'maxHeight': maxHeight,
        });
    if (bytes == null) {
      throw const FormatException('Android returned no PDF page.');
    }
    return AndroidPreviewImage.fromBytes(bytes);
  }

  @override
  Future<int?> readIntPreference(String key) => methodChannel.invokeMethod<int>(
    'readIntPreference',
    <String, Object>{'key': key},
  );

  @override
  Future<void> writeIntPreference(String key, int value) =>
      methodChannel.invokeMethod<void>('writeIntPreference', <String, Object>{
        'key': key,
        'value': value,
      });

  Future<AndroidWorkspaceState> _workspaceState(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    return AndroidWorkspaceState.fromMap(raw!);
  }

  @override
  Future<AndroidWorkspaceState> getTestWorkspaceState() =>
      _workspaceState('getTestWorkspaceState');

  @override
  Future<AndroidWorkspaceState?> pickTestWorkspaceTree() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'pickTestWorkspaceTree',
    );
    return raw == null ? null : AndroidWorkspaceState.fromMap(raw);
  }

  @override
  Future<AndroidWorkspaceState?> importTestWorkspaceCopies() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'importTestWorkspaceCopies',
    );
    return raw == null ? null : AndroidWorkspaceState.fromMap(raw);
  }

  @override
  Future<AndroidWorkspaceState> createTestWorkspaceFolder({
    String? parentUri,
    required String name,
  }) => _workspaceState('createTestWorkspaceFolder', <String, Object?>{
    'parentUri': parentUri,
    'name': name,
  });

  @override
  Future<AndroidWorkspaceState> renameTestWorkspaceItem({
    required String documentUri,
    required String name,
  }) => _workspaceState('renameTestWorkspaceItem', <String, Object>{
    'documentUri': documentUri,
    'name': name,
  });

  @override
  Future<AndroidWorkspaceState> moveTestWorkspaceItem({
    required String documentUri,
    required String sourceParentUri,
    required String targetParentUri,
  }) => _workspaceState('moveTestWorkspaceItem', <String, Object>{
    'documentUri': documentUri,
    'sourceParentUri': sourceParentUri,
    'targetParentUri': targetParentUri,
  });

  @override
  Future<AndroidWorkspaceState> trashTestWorkspaceItem({
    required String documentUri,
    required String sourceParentUri,
  }) => _workspaceState('trashTestWorkspaceItem', <String, Object>{
    'documentUri': documentUri,
    'sourceParentUri': sourceParentUri,
  });

  @override
  Future<AndroidWorkspaceState> undoTestWorkspaceOperation({
    String? operationId,
  }) => _workspaceState('undoTestWorkspaceOperation', <String, Object?>{
    'operationId': operationId,
  });

  @override
  Future<bool> requestSystemTrash(List<String> contentUris) async =>
      await methodChannel.invokeMethod<bool>(
        'requestSystemTrash',
        <String, Object>{'contentUris': contentUris},
      ) ??
      false;
}
