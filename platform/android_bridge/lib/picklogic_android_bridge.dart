import 'picklogic_android_bridge_platform_interface.dart';
import 'src/android_media.dart';

export 'src/android_media.dart';

final class PicklogicAndroidBridge {
  const PicklogicAndroidBridge();

  Future<String?> getPlatformVersion() =>
      PicklogicAndroidBridgePlatform.instance.getPlatformVersion();

  Future<AndroidMediaPermissionState> getMediaPermissionState() =>
      PicklogicAndroidBridgePlatform.instance.getMediaPermissionState();

  Future<AndroidMediaPermissionState> requestMediaPermissions() =>
      PicklogicAndroidBridgePlatform.instance.requestMediaPermissions();

  Future<AndroidMediaPage> queryMediaPage(AndroidMediaQuery query) =>
      PicklogicAndroidBridgePlatform.instance.queryMediaPage(query);

  Future<int> countMedia(AndroidMediaKind kind) =>
      PicklogicAndroidBridgePlatform.instance.countMedia(kind);

  Future<AndroidThumbnail?> loadThumbnail(AndroidThumbnailRequest request) =>
      PicklogicAndroidBridgePlatform.instance.loadThumbnail(request);

  Future<AndroidStorageSnapshot> getStorageSnapshot() =>
      PicklogicAndroidBridgePlatform.instance.getStorageSnapshot();

  Future<String> getPrivateIndexDatabasePath() =>
      PicklogicAndroidBridgePlatform.instance.getPrivateIndexDatabasePath();

  Future<String?> pickDocumentTree() =>
      PicklogicAndroidBridgePlatform.instance.pickDocumentTree();

  Future<List<AndroidBrowseRoot>> getBrowseRoots() =>
      PicklogicAndroidBridgePlatform.instance.getBrowseRoots();

  Future<AndroidBrowsePage> listBrowseDirectory({
    required String treeUri,
    String? directoryUri,
    int offset = 0,
    int limit = 200,
  }) => PicklogicAndroidBridgePlatform.instance.listBrowseDirectory(
    treeUri: treeUri,
    directoryUri: directoryUri,
    offset: offset,
    limit: limit,
  );

  Future<AndroidBrowseDirectorySummary> inspectBrowseDirectory({
    required String treeUri,
    String? directoryUri,
  }) => PicklogicAndroidBridgePlatform.instance.inspectBrowseDirectory(
    treeUri: treeUri,
    directoryUri: directoryUri,
  );

  Future<bool> openContentUri(String contentUri) =>
      PicklogicAndroidBridgePlatform.instance.openContentUri(contentUri);

  Future<AndroidPreviewImage?> loadPreviewImage(String contentUri) =>
      PicklogicAndroidBridgePlatform.instance.loadPreviewImage(contentUri);

  Future<AndroidTextPreview> loadTextPreview(String contentUri) =>
      PicklogicAndroidBridgePlatform.instance.loadTextPreview(contentUri);

  Future<AndroidArchiveListing> listArchive(String contentUri) =>
      PicklogicAndroidBridgePlatform.instance.listArchive(contentUri);

  Future<AndroidApkDetails> inspectApk(String contentUri) =>
      PicklogicAndroidBridgePlatform.instance.inspectApk(contentUri);

  Future<AndroidPdfInfo> getPdfInfo(String contentUri) =>
      PicklogicAndroidBridgePlatform.instance.getPdfInfo(contentUri);

  Future<AndroidOfficePreview> inspectOffice(
    String contentUri, {
    required String extension,
  }) => PicklogicAndroidBridgePlatform.instance.inspectOffice(
    contentUri,
    extension: extension,
  );

  Future<AndroidPreviewImage> renderPdfPage(
    String contentUri, {
    required int pageIndex,
    required int maxWidth,
    required int maxHeight,
  }) => PicklogicAndroidBridgePlatform.instance.renderPdfPage(
    contentUri,
    pageIndex: pageIndex,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );

  Future<int?> readIntPreference(String key) =>
      PicklogicAndroidBridgePlatform.instance.readIntPreference(key);

  Future<void> writeIntPreference(String key, int value) =>
      PicklogicAndroidBridgePlatform.instance.writeIntPreference(key, value);

  Future<AndroidWorkspaceState> getTestWorkspaceState() =>
      PicklogicAndroidBridgePlatform.instance.getTestWorkspaceState();

  Future<AndroidWorkspaceState?> pickTestWorkspaceTree() =>
      PicklogicAndroidBridgePlatform.instance.pickTestWorkspaceTree();

  Future<AndroidWorkspaceState?> importTestWorkspaceCopies() =>
      PicklogicAndroidBridgePlatform.instance.importTestWorkspaceCopies();

  Future<AndroidWorkspaceState> createTestWorkspaceFolder({
    String? parentUri,
    required String name,
  }) => PicklogicAndroidBridgePlatform.instance.createTestWorkspaceFolder(
    parentUri: parentUri,
    name: name,
  );

  Future<AndroidWorkspaceState> renameTestWorkspaceItem({
    required String documentUri,
    required String name,
  }) => PicklogicAndroidBridgePlatform.instance.renameTestWorkspaceItem(
    documentUri: documentUri,
    name: name,
  );

  Future<AndroidWorkspaceState> moveTestWorkspaceItem({
    required String documentUri,
    required String sourceParentUri,
    required String targetParentUri,
  }) => PicklogicAndroidBridgePlatform.instance.moveTestWorkspaceItem(
    documentUri: documentUri,
    sourceParentUri: sourceParentUri,
    targetParentUri: targetParentUri,
  );

  Future<AndroidWorkspaceState> trashTestWorkspaceItem({
    required String documentUri,
    required String sourceParentUri,
  }) => PicklogicAndroidBridgePlatform.instance.trashTestWorkspaceItem(
    documentUri: documentUri,
    sourceParentUri: sourceParentUri,
  );

  Future<AndroidWorkspaceState> undoTestWorkspaceOperation({
    String? operationId,
  }) => PicklogicAndroidBridgePlatform.instance.undoTestWorkspaceOperation(
    operationId: operationId,
  );

  Future<bool> requestSystemTrash(List<String> contentUris) =>
      PicklogicAndroidBridgePlatform.instance.requestSystemTrash(contentUris);
}
