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
  Future<String?> pickPdfFile({String? title}) {
    final arguments = <String, Object?>{};
    if (title != null) arguments['title'] = title;
    return methodChannel.invokeMethod<String>('pickPdfFile', arguments);
  }

  @override
  Future<List<String>> pickPdfFiles({String? title}) async {
    final arguments = <String, Object?>{};
    if (title != null) arguments['title'] = title;
    return await methodChannel.invokeListMethod<String>(
          'pickPdfFiles',
          arguments,
        ) ??
        const <String>[];
  }

  @override
  Future<List<String>> pickFiles({String? title}) async {
    final arguments = <String, Object?>{};
    if (title != null) arguments['title'] = title;
    return await methodChannel.invokeListMethod<String>(
          'pickFiles',
          arguments,
        ) ??
        const <String>[];
  }

  @override
  Future<String?> pickPdfSavePath({String? title, String? suggestedName}) {
    final arguments = <String, Object?>{};
    if (title != null) arguments['title'] = title;
    if (suggestedName != null) arguments['suggestedName'] = suggestedName;
    return methodChannel.invokeMethod<String>('pickPdfSavePath', arguments);
  }

  @override
  Future<String> getApplicationSupportDirectory() async => (await methodChannel
      .invokeMethod<String>('getApplicationSupportDirectory'))!;

  @override
  Future<List<WindowsBrowseRoot>> getBrowseRoots() async {
    final raw = await methodChannel.invokeListMethod<Object?>('getBrowseRoots');
    return (raw ?? const <Object?>[])
        .map(
          (item) => WindowsBrowseRoot.fromMap(
            Map<Object?, Object?>.from(item! as Map<Object?, Object?>),
          ),
        )
        .toList(growable: false);
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

  @override
  Future<WindowsShellThumbnail?> loadShellThumbnail(
    String path, {
    required int size,
  }) async {
    if (size < 16 || size > 512) {
      throw RangeError.range(size, 16, 512, 'size');
    }
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'loadShellThumbnail',
      <String, Object>{'path': path, 'size': size},
    );
    return raw == null ? null : WindowsShellThumbnail.fromMap(raw);
  }

  @override
  Future<WindowsRecycleResult> recycleItem(
    String path, {
    required String operationId,
  }) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'recycleItem',
      <String, Object>{'path': path, 'operationId': operationId},
    );
    return WindowsRecycleResult.fromMap(raw!);
  }

  @override
  Future<bool> restoreRecycledItem(String operationId) async =>
      await methodChannel.invokeMethod<bool>(
        'restoreRecycledItem',
        <String, Object>{'operationId': operationId},
      ) ??
      false;

  @override
  Future<void> writeProtectedSecret(String name, String value) =>
      methodChannel.invokeMethod<void>('writeProtectedSecret', <String, Object>{
        'name': name,
        'value': value,
      });

  @override
  Future<String?> readProtectedSecret(String name) =>
      methodChannel.invokeMethod<String>(
        'readProtectedSecret',
        <String, Object>{'name': name},
      );

  @override
  Future<void> deleteProtectedSecret(String name) =>
      methodChannel.invokeMethod<void>(
        'deleteProtectedSecret',
        <String, Object>{'name': name},
      );

  @override
  Future<bool> copyRichText({
    required String plainText,
    required String rtf,
  }) async =>
      await methodChannel.invokeMethod<bool>('copyRichText', <String, Object>{
        'plainText': plainText,
        'rtf': rtf,
      }) ??
      false;
}
