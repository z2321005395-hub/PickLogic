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
  });
}
