import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'picklogic_android_bridge_platform_interface.dart';
import 'src/android_media.dart';

/// An implementation of [PicklogicAndroidBridgePlatform] that uses method channels.
class MethodChannelPicklogicAndroidBridge
    extends PicklogicAndroidBridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('picklogic_android_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<AndroidMediaPermissionState> getMediaPermissionState() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getMediaPermissionState',
    );
    return AndroidMediaPermissionState.fromMap(raw!);
  }

  @override
  Future<AndroidMediaPermissionState> requestMediaPermissions() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'requestMediaPermissions',
    );
    return AndroidMediaPermissionState.fromMap(raw!);
  }

  @override
  Future<AndroidMediaPage> queryMediaPage(AndroidMediaQuery query) async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'queryMediaPage',
      query.toMap(),
    );
    return AndroidMediaPage.fromMap(raw!);
  }

  @override
  Future<AndroidStorageSnapshot> getStorageSnapshot() async {
    final raw = await methodChannel.invokeMapMethod<Object?, Object?>(
      'getStorageSnapshot',
    );
    return AndroidStorageSnapshot.fromMap(raw!);
  }

  @override
  Future<String?> pickDocumentTree() =>
      methodChannel.invokeMethod<String>('pickDocumentTree');

  @override
  Future<bool> openContentUri(String contentUri) async =>
      await methodChannel.invokeMethod<bool>(
        'openContentUri',
        <String, Object?>{'contentUri': contentUri},
      ) ??
      false;
}
