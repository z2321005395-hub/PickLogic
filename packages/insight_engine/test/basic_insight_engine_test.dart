import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_insight_engine/picklogic_insight_engine.dart';
import 'package:test/test.dart';

void main() {
  FileRecord fixture({required bool protected, required bool accessible}) =>
      FileRecord(
        id: 'fixture',
        locator: const FileLocator(
          value: 'synthetic://fixture',
          sourceKind: SourceKind.synthetic,
          platform: PickLogicPlatform.synthetic,
        ),
        displayName: 'fixture.pdf',
        extension: 'pdf',
        mimeType: 'application/pdf',
        sizeBytes: 10,
        createdAt: null,
        modifiedAt: DateTime.utc(2026),
        parentLocator: null,
        sourceKind: SourceKind.synthetic,
        platform: PickLogicPlatform.synthetic,
        isHidden: false,
        isSystem: false,
        isAccessible: accessible,
        isProtected: protected,
        category: VirtualCategory.pdf,
        hashState: HashState.notRequested,
        ocrState: OcrState.notRequested,
      );

  test('protected records never recommend direct deletion', () {
    final insight = const BasicInsightEngine().explainFile(
      fixture(protected: true, accessible: true),
    );
    expect(insight.riskLevel, RiskLevel.protected);
    expect(insight.recommendedActions.join(' '), isNot(contains('Delete')));
  });

  test('platform restrictions remain explicit', () {
    final insight = const BasicInsightEngine().explainFile(
      fixture(protected: false, accessible: false),
    );
    expect(insight.riskLevel, RiskLevel.unknown);
    expect(insight.limitations, isNotEmpty);
  });
}
