import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'picklogic_windows_bridge_platform_interface.dart';
import 'src/windows_metadata.dart';

/// An implementation of [PicklogicWindowsBridgePlatform] that uses method channels.
class MethodChannelPicklogicWindowsBridge
    extends PicklogicWindowsBridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('picklogic_windows_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<String?> pickDirectory({String? title}) {
    final arguments = <String, Object?>{};
    if (title != null) arguments['title'] = title;
    return methodChannel.invokeMethod<String>('pickDirectory', arguments);
  }

  @override
  Future<bool> openItem(String path) async =>
      await methodChannel.invokeMethod<bool>('openItem', {'path': path}) ??
      false;

  @override
  Future<bool> revealItem(String path) async =>
      await methodChannel.invokeMethod<bool>('revealItem', {'path': path}) ??
      false;

  @override
  Future<WindowsPathAttributes?> getPathAttributes(String path) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getPathAttributes',
      {'path': path},
    );
    return raw == null ? null : WindowsPathAttributes.fromMap(raw);
  }

  @override
  Future<WindowsStorageSummary> getSystemDriveSummary() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getSystemDriveSummary',
    );
    return WindowsStorageSummary.fromMap(raw!);
  }
}
