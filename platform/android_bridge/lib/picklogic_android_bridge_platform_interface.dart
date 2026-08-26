import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'picklogic_android_bridge_method_channel.dart';
import 'src/android_media.dart';

abstract class PicklogicAndroidBridgePlatform extends PlatformInterface {
  /// Constructs a PicklogicAndroidBridgePlatform.
  PicklogicAndroidBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static PicklogicAndroidBridgePlatform _instance =
      MethodChannelPicklogicAndroidBridge();

  /// The default instance of [PicklogicAndroidBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelPicklogicAndroidBridge].
  static PicklogicAndroidBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PicklogicAndroidBridgePlatform] when
  /// they register themselves.
  static set instance(PicklogicAndroidBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<AndroidMediaPermissionState> getMediaPermissionState() {
    throw UnimplementedError(
      'getMediaPermissionState() has not been implemented.',
    );
  }

  Future<AndroidMediaPermissionState> requestMediaPermissions() {
    throw UnimplementedError(
      'requestMediaPermissions() has not been implemented.',
    );
  }

  Future<AndroidMediaPage> queryMediaPage(AndroidMediaQuery query) {
    throw UnimplementedError('queryMediaPage() has not been implemented.');
  }

  Future<int> countMedia(AndroidMediaKind kind) {
    throw UnimplementedError('countMedia() has not been implemented.');
  }

  Future<AndroidThumbnail?> loadThumbnail(AndroidThumbnailRequest request) {
    throw UnimplementedError('loadThumbnail() has not been implemented.');
  }

  Future<AndroidStorageSnapshot> getStorageSnapshot() {
    throw UnimplementedError('getStorageSnapshot() has not been implemented.');
  }

  Future<String> getPrivateIndexDatabasePath() {
    throw UnimplementedError(
      'getPrivateIndexDatabasePath() has not been implemented.',
    );
  }

  Future<String?> pickDocumentTree() {
    throw UnimplementedError('pickDocumentTree() has not been implemented.');
  }

  Future<List<AndroidBrowseRoot>> getBrowseRoots() {
    throw UnimplementedError('getBrowseRoots() has not been implemented.');
  }

  Future<AndroidBrowsePage> listBrowseDirectory({
    required String treeUri,
    String? directoryUri,
    int offset = 0,
    int limit = 200,
  }) {
    throw UnimplementedError('listBrowseDirectory() has not been implemented.');
  }

  Future<bool> openContentUri(String contentUri) {
    throw UnimplementedError('openContentUri() has not been implemented.');
  }

  Future<AndroidPreviewImage?> loadPreviewImage(String contentUri) {
    throw UnimplementedError('loadPreviewImage() has not been implemented.');
  }

  Future<AndroidTextPreview> loadTextPreview(String contentUri) {
    throw UnimplementedError('loadTextPreview() has not been implemented.');
  }

  Future<AndroidArchiveListing> listArchive(String contentUri) {
    throw UnimplementedError('listArchive() has not been implemented.');
  }

  Future<AndroidApkDetails> inspectApk(String contentUri) {
    throw UnimplementedError('inspectApk() has not been implemented.');
  }

  Future<AndroidPdfInfo> getPdfInfo(String contentUri) {
    throw UnimplementedError('getPdfInfo() has not been implemented.');
  }

  Future<AndroidOfficePreview> inspectOffice(
    String contentUri, {
    required String extension,
  }) {
    throw UnimplementedError('inspectOffice() has not been implemented.');
  }

  Future<AndroidPreviewImage> renderPdfPage(
    String contentUri, {
    required int pageIndex,
    required int maxWidth,
    required int maxHeight,
  }) {
    throw UnimplementedError('renderPdfPage() has not been implemented.');
  }

  Future<int?> readIntPreference(String key) {
    throw UnimplementedError('readIntPreference() has not been implemented.');
  }

  Future<void> writeIntPreference(String key, int value) {
    throw UnimplementedError('writeIntPreference() has not been implemented.');
  }

  Future<AndroidWorkspaceState> getTestWorkspaceState() {
    throw UnimplementedError(
      'getTestWorkspaceState() has not been implemented.',
    );
  }

  Future<AndroidWorkspaceState?> pickTestWorkspaceTree() {
    throw UnimplementedError(
      'pickTestWorkspaceTree() has not been implemented.',
    );
  }

  Future<AndroidWorkspaceState?> importTestWorkspaceCopies() {
    throw UnimplementedError(
      'importTestWorkspaceCopies() has not been implemented.',
    );
  }

  Future<AndroidWorkspaceState> createTestWorkspaceFolder({
    String? parentUri,
    required String name,
  }) {
    throw UnimplementedError(
      'createTestWorkspaceFolder() has not been implemented.',
    );
  }

  Future<AndroidWorkspaceState> renameTestWorkspaceItem({
    required String documentUri,
    required String name,
  }) {
    throw UnimplementedError(
      'renameTestWorkspaceItem() has not been implemented.',
    );
  }

  Future<AndroidWorkspaceState> moveTestWorkspaceItem({
    required String documentUri,
    required String sourceParentUri,
    required String targetParentUri,
  }) {
    throw UnimplementedError(
      'moveTestWorkspaceItem() has not been implemented.',
    );
  }

  Future<AndroidWorkspaceState> trashTestWorkspaceItem({
    required String documentUri,
    required String sourceParentUri,
  }) {
    throw UnimplementedError(
      'trashTestWorkspaceItem() has not been implemented.',
    );
  }

  Future<AndroidWorkspaceState> undoTestWorkspaceOperation({
    String? operationId,
  }) {
    throw UnimplementedError(
      'undoTestWorkspaceOperation() has not been implemented.',
    );
  }

  Future<bool> requestSystemTrash(List<String> contentUris) {
    throw UnimplementedError('requestSystemTrash() has not been implemented.');
  }
}
