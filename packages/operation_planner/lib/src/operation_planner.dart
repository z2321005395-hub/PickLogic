import 'package:picklogic_core_models/picklogic_core_models.dart';

final class OperationPlanner {
  const OperationPlanner();

  OperationPlan planRename({
    required String operationId,
    required FileLocator source,
    required FileLocator destination,
    List<String> warnings = const [],
  }) => _plan(
    operationId: operationId,
    type: OperationType.rename,
    source: source,
    destination: destination,
    preview: 'Preview rename',
    warnings: warnings,
  );

  OperationPlan planMove({
    required String operationId,
    required FileLocator source,
    required FileLocator destination,
    List<String> warnings = const [],
  }) => _plan(
    operationId: operationId,
    type: OperationType.move,
    source: source,
    destination: destination,
    preview: 'Preview move',
    warnings: warnings,
  );

  OperationPlan planDeleteToTrash({
    required String operationId,
    required FileLocator source,
    List<String> warnings = const [],
  }) => _plan(
    operationId: operationId,
    type: OperationType.deleteToTrash,
    source: source,
    preview: 'Preview move to platform trash',
    warnings: warnings,
  );

  OperationPlan _plan({
    required String operationId,
    required OperationType type,
    required FileLocator source,
    FileLocator? destination,
    required String preview,
    required List<String> warnings,
  }) => OperationPlan(
    operationId: operationId,
    operationType: type,
    source: source,
    destination: destination,
    preview: preview,
    warnings: List<String>.unmodifiable(warnings),
    rollbackMetadata: const {},
    status: OperationStatus.planned,
  );
}

final class SafeOperationGate {
  const SafeOperationGate(this.mode);

  final DeveloperSafeMode mode;

  bool mayExecute(
    OperationPlan plan, {
    required bool syntheticTarget,
    required bool testMutationAuthorized,
  }) {
    if (plan.status != OperationStatus.confirmed) return false;
    final capability = switch (plan.operationType) {
      OperationType.rename => SafeCapability.renameRealData,
      OperationType.move => SafeCapability.moveRealData,
      OperationType.deleteToTrash => SafeCapability.deleteRealData,
    };
    return mode.allows(
      capability,
      syntheticTarget: syntheticTarget,
      testMutationAuthorized: testMutationAuthorized,
    );
  }
}
