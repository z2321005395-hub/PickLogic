import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_operation_planner/picklogic_operation_planner.dart';
import 'package:test/test.dart';

void main() {
  const locator = FileLocator(
    value: 'synthetic://item',
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
  );

  test('plans never start confirmed', () {
    final plan = const OperationPlanner().planDeleteToTrash(
      operationId: 'delete-1',
      source: locator,
    );
    expect(plan.status, OperationStatus.planned);
  });

  test('safe gate requires confirmation and authorized synthetic target', () {
    final planned = const OperationPlanner().planRename(
      operationId: 'rename-1',
      source: locator,
      destination: locator,
    );
    final confirmed = planned
        .transitionTo(OperationStatus.previewed)
        .transitionTo(OperationStatus.confirmed);
    const gate = SafeOperationGate(DeveloperSafeMode.on());
    expect(
      gate.mayExecute(
        confirmed,
        syntheticTarget: true,
        testMutationAuthorized: true,
      ),
      isTrue,
    );
    expect(
      gate.mayExecute(
        confirmed,
        syntheticTarget: false,
        testMutationAuthorized: true,
      ),
      isFalse,
    );
  });
}
