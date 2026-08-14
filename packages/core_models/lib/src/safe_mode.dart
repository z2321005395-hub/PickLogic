import 'enums.dart';

final class DeveloperSafeMode {
  const DeveloperSafeMode({required this.enabled});

  const DeveloperSafeMode.on() : enabled = true;

  final bool enabled;

  bool allows(
    SafeCapability capability, {
    bool syntheticTarget = false,
    bool testMutationAuthorized = false,
    bool userAuthorizedManagedTarget = false,
  }) {
    if (!enabled) return true;
    switch (capability) {
      case SafeCapability.scan:
      case SafeCapability.indexFiles:
      case SafeCapability.hash:
      case SafeCapability.thumbnail:
      case SafeCapability.classify:
      case SafeCapability.explain:
      case SafeCapability.benchmark:
        return true;
      case SafeCapability.deleteRealData:
      case SafeCapability.moveRealData:
      case SafeCapability.renameRealData:
        return (syntheticTarget && testMutationAuthorized) ||
            userAuthorizedManagedTarget;
      case SafeCapability.systemChanges:
        return false;
    }
  }

  String get label =>
      enabled ? 'Developer Safe Mode: ON' : 'Developer Safe Mode: OFF';
}
