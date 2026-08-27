import 'picklogic_windows_bridge_platform_interface.dart';
import 'src/windows_metadata.dart';

export 'src/windows_metadata.dart';

final class PicklogicWindowsBridge {
  const PicklogicWindowsBridge();

  Future<String?> getPlatformVersion() =>
      PicklogicWindowsBridgePlatform.instance.getPlatformVersion();

  Future<String?> pickDirectory({String? title}) =>
      PicklogicWindowsBridgePlatform.instance.pickDirectory(title: title);

  Future<String?> pickPdfFile({String? title}) =>
      PicklogicWindowsBridgePlatform.instance.pickPdfFile(title: title);

  Future<List<String>> pickPdfFiles({String? title}) =>
      PicklogicWindowsBridgePlatform.instance.pickPdfFiles(title: title);

  Future<List<String>> pickFiles({String? title}) =>
      PicklogicWindowsBridgePlatform.instance.pickFiles(title: title);

  Future<String> getApplicationSupportDirectory() =>
      PicklogicWindowsBridgePlatform.instance.getApplicationSupportDirectory();

  Future<List<WindowsBrowseRoot>> getBrowseRoots() =>
      PicklogicWindowsBridgePlatform.instance.getBrowseRoots();

  Future<bool> openItem(String path) =>
      PicklogicWindowsBridgePlatform.instance.openItem(path);

  Future<bool> revealItem(String path) =>
      PicklogicWindowsBridgePlatform.instance.revealItem(path);

  Future<WindowsPathAttributes?> getPathAttributes(String path) =>
      PicklogicWindowsBridgePlatform.instance.getPathAttributes(path);

  Future<WindowsStorageSummary> getSystemDriveSummary() =>
      PicklogicWindowsBridgePlatform.instance.getSystemDriveSummary();

  Future<WindowsShellThumbnail?> loadShellThumbnail(
    String path, {
    required int size,
  }) => PicklogicWindowsBridgePlatform.instance.loadShellThumbnail(
    path,
    size: size,
  );

  Future<WindowsRecycleResult> recycleItem(
    String path, {
    required String operationId,
  }) => PicklogicWindowsBridgePlatform.instance.recycleItem(
    path,
    operationId: operationId,
  );

  Future<bool> restoreRecycledItem(String operationId) =>
      PicklogicWindowsBridgePlatform.instance.restoreRecycledItem(operationId);

  Future<void> writeProtectedSecret(String name, String value) =>
      PicklogicWindowsBridgePlatform.instance.writeProtectedSecret(name, value);

  Future<String?> readProtectedSecret(String name) =>
      PicklogicWindowsBridgePlatform.instance.readProtectedSecret(name);

  Future<void> deleteProtectedSecret(String name) =>
      PicklogicWindowsBridgePlatform.instance.deleteProtectedSecret(name);

  Future<bool> copyRichText({required String plainText, required String rtf}) =>
      PicklogicWindowsBridgePlatform.instance.copyRichText(
        plainText: plainText,
        rtf: rtf,
      );
}
