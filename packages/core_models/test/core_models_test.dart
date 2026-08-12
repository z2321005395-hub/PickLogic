import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:test/test.dart';

void main() {
  const locator = FileLocator(
    value: 'synthetic://document.txt',
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
  );

  test('locators redact their concrete value in logs', () {
    expect(locator.toString(), isNot(contains('document.txt')));
    expect(locator.redactedLabel, 'synthetic:synthetic');
  });

  test('operation plans enforce confirmation lifecycle', () {
    const plan = OperationPlan(
      operationId: 'op-1',
      operationType: OperationType.rename,
      source: locator,
      preview: 'Rename synthetic fixture',
      status: OperationStatus.planned,
    );

    final confirmed = plan
        .transitionTo(OperationStatus.previewed)
        .transitionTo(OperationStatus.confirmed);
    expect(confirmed.canTransitionTo(OperationStatus.executing), isTrue);
    expect(
      () => plan.transitionTo(OperationStatus.executing),
      throwsStateError,
    );
  });

  test('safe mode blocks real mutations and allows approved fixture tests', () {
    const mode = DeveloperSafeMode.on();
    expect(mode.allows(SafeCapability.hash), isTrue);
    expect(mode.allows(SafeCapability.deleteRealData), isFalse);
    expect(
      mode.allows(
        SafeCapability.renameRealData,
        syntheticTarget: true,
        testMutationAuthorized: true,
      ),
      isTrue,
    );
    expect(mode.allows(SafeCapability.systemChanges), isFalse);
  });
}
