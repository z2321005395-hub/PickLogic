import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge_platform_interface.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPicklogicWindowsBridgePlatform
    with MockPlatformInterfaceMixin
    implements PicklogicWindowsBridgePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<String?> pickDirectory({String? title}) async => 'synthetic-root';

  @override
  Future<String?> pickPdfFile({String? title}) async =>
      r'X:\synthetic\paper.pdf';

  @override
  Future<List<String>> pickPdfFiles({String? title}) async => <String>[
    r'X:\synthetic\paper.pdf',
    r'X:\synthetic\second.pdf',
  ];

  @override
  Future<String> getApplicationSupportDirectory() async =>
      r'X:\synthetic\app-support';

  @override
  Future<List<WindowsBrowseRoot>> getBrowseRoots() async => const [
    WindowsBrowseRoot(
      id: 'drive:X',
      path: r'X:\',
      kind: WindowsBrowseRootKind.drive,
    ),
  ];

  @override
  Future<bool> openItem(String path) async => true;

  @override
  Future<bool> revealItem(String path) async => true;

  @override
  Future<WindowsPathAttributes?> getPathAttributes(String path) async =>
      const WindowsPathAttributes(
        hidden: false,
        system: false,
        readOnly: true,
        directory: false,
      );

  @override
  Future<WindowsStorageSummary> getSystemDriveSummary() async =>
      const WindowsStorageSummary(
        root: 'synthetic-root',
        totalBytes: 100,
        availableBytes: 40,
      );
}

void main() {
  final PicklogicWindowsBridgePlatform initialPlatform =
      PicklogicWindowsBridgePlatform.instance;

  test('$MethodChannelPicklogicWindowsBridge is the default instance', () {
    expect(
      initialPlatform,
      isInstanceOf<MethodChannelPicklogicWindowsBridge>(),
    );
  });

  test('getPlatformVersion', () async {
    const picklogicWindowsBridgePlugin = PicklogicWindowsBridge();
    MockPicklogicWindowsBridgePlatform fakePlatform =
        MockPicklogicWindowsBridgePlatform();
    PicklogicWindowsBridgePlatform.instance = fakePlatform;

    expect(await picklogicWindowsBridgePlugin.getPlatformVersion(), '42');
  });

  test('delegates read-only Windows shell and storage calls', () async {
    const bridge = PicklogicWindowsBridge();
    expect(await bridge.pickDirectory(), 'synthetic-root');
    expect(await bridge.pickPdfFile(), r'X:\synthetic\paper.pdf');
    expect(await bridge.pickPdfFiles(), hasLength(2));
    expect(
      await bridge.getApplicationSupportDirectory(),
      r'X:\synthetic\app-support',
    );
    expect(
      (await bridge.getBrowseRoots()).single.kind,
      WindowsBrowseRootKind.drive,
    );
    expect((await bridge.getPathAttributes('synthetic'))!.readOnly, isTrue);
    expect((await bridge.getSystemDriveSummary()).availableBytes, 40);
    expect(await bridge.openItem('synthetic'), isTrue);
    expect(await bridge.revealItem('synthetic'), isTrue);
  });
}
