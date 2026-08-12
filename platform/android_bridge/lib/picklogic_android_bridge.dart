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

  Future<AndroidThumbnail?> loadThumbnail(AndroidThumbnailRequest request) =>
      PicklogicAndroidBridgePlatform.instance.loadThumbnail(request);

  Future<AndroidStorageSnapshot> getStorageSnapshot() =>
      PicklogicAndroidBridgePlatform.instance.getStorageSnapshot();

  Future<String?> pickDocumentTree() =>
      PicklogicAndroidBridgePlatform.instance.pickDocumentTree();

  Future<bool> openContentUri(String contentUri) =>
      PicklogicAndroidBridgePlatform.instance.openContentUri(contentUri);
}
