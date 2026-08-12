import 'picklogic_windows_bridge_platform_interface.dart';
import 'src/windows_metadata.dart';

export 'src/windows_metadata.dart';

final class PicklogicWindowsBridge {
  const PicklogicWindowsBridge();

  Future<String?> getPlatformVersion() =>
      PicklogicWindowsBridgePlatform.instance.getPlatformVersion();

  Future<String?> pickDirectory({String? title}) =>
      PicklogicWindowsBridgePlatform.instance.pickDirectory(title: title);

  Future<bool> openItem(String path) =>
      PicklogicWindowsBridgePlatform.instance.openItem(path);

  Future<bool> revealItem(String path) =>
      PicklogicWindowsBridgePlatform.instance.revealItem(path);

  Future<WindowsPathAttributes?> getPathAttributes(String path) =>
      PicklogicWindowsBridgePlatform.instance.getPathAttributes(path);

  Future<WindowsStorageSummary> getSystemDriveSummary() =>
      PicklogicWindowsBridgePlatform.instance.getSystemDriveSummary();
}
