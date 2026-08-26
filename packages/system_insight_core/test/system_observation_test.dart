import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_system_insight_core/picklogic_system_insight_core.dart';
import 'package:test/test.dart';

void main() {
  test('system observations remain protected and read-only', () {
    const observation = SystemObservation(
      kind: SystemObservationKind.service,
      label: 'Synthetic service',
      sizeBytes: 0,
      isWindowsCore: true,
      isRunning: true,
      isSigned: true,
    );
    final insight = const SystemObservationExplainer().explain(observation);
    expect(insight.riskLevel, RiskLevel.protected);
    expect(insight.recommendedActions.join(' '), isNot(contains('Disable')));
    expect(insight.limitations, isNotEmpty);
    expect(
      insight.evidence.map((item) => item.kind),
      containsAll([
        EvidenceKind.ruleInference,
        EvidenceKind.platformRestriction,
      ]),
    );
    expect(
      insight.recommendedActions.join(' ').toLowerCase(),
      isNot(anyOf(contains('delete'), contains('clean'), contains('remove'))),
    );
  });

  test('unknown observations stay unknown and offer review only', () {
    const observation = SystemObservation(
      kind: SystemObservationKind.unknown,
      label: 'Synthetic unknown item',
      sizeBytes: 64,
      isWindowsCore: false,
      isRunning: false,
      isSigned: false,
    );
    final insight = const SystemObservationExplainer().explain(observation);
    expect(insight.riskLevel, RiskLevel.unknown);
    expect(insight.confidence, lessThan(0.5));
    expect(insight.recommendedActions, contains('Add to review list'));
    expect(
      insight.recommendedActions,
      isNot(contains('Open official settings')),
    );
  });
}
