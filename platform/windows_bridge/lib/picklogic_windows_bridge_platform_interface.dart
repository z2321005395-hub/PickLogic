import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'picklogic_windows_bridge_method_channel.dart';
import 'src/windows_metadata.dart';

abstract class PicklogicWindowsBridgePlatform extends PlatformInterface {
  /// Constructs a PicklogicWindowsBridgePlatform.
  PicklogicWindowsBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static PicklogicWindowsBridgePlatform _instance =
      MethodChannelPicklogicWindowsBridge();

  /// The default instance of [PicklogicWindowsBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelPicklogicWindowsBridge].
  static PicklogicWindowsBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PicklogicWindowsBridgePlatform] when
  /// they register themselves.
  static set instance(PicklogicWindowsBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String?> pickDirectory({String? title}) {
    throw UnimplementedError('pickDirectory() has not been implemented.');
  }

  Future<String?> pickPdfFile({String? title}) {
    throw UnimplementedError('pickPdfFile() has not been implemented.');
  }

  Future<List<String>> pickPdfFiles({String? title}) {
    throw UnimplementedError('pickPdfFiles() has not been implemented.');
  }

  Future<String> getApplicationSupportDirectory() {
    throw UnimplementedError(
      'getApplicationSupportDirectory() has not been implemented.',
    );
  }

  Future<List<WindowsBrowseRoot>> getBrowseRoots() {
    throw UnimplementedError('getBrowseRoots() has not been implemented.');
  }

  Future<bool> openItem(String path) {
    throw UnimplementedError('openItem() has not been implemented.');
  }

  Future<bool> revealItem(String path) {
    throw UnimplementedError('revealItem() has not been implemented.');
  }

  Future<WindowsPathAttributes?> getPathAttributes(String path) {
    throw UnimplementedError('getPathAttributes() has not been implemented.');
  }

  Future<WindowsStorageSummary> getSystemDriveSummary() {
    throw UnimplementedError(
      'getSystemDriveSummary() has not been implemented.',
    );
  }
}
