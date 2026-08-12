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

  Future<AndroidStorageSnapshot> getStorageSnapshot() {
    throw UnimplementedError('getStorageSnapshot() has not been implemented.');
  }

  Future<String?> pickDocumentTree() {
    throw UnimplementedError('pickDocumentTree() has not been implemented.');
  }

  Future<bool> openContentUri(String contentUri) {
    throw UnimplementedError('openContentUri() has not been implemented.');
  }
}
