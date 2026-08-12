import 'package:picklogic_core_models/picklogic_core_models.dart';

final class BasicInsightEngine implements InsightEngine {
  const BasicInsightEngine();

  @override
  InsightRecord explainFile(FileRecord record) {
    final (risk, confidence, limitation) = _risk(record);
    final evidence = <InsightEvidence>[
      InsightEvidence(
        kind: EvidenceKind.fact,
        statement: 'Indexed metadata reports ${record.sizeBytes} bytes.',
        source: 'local metadata',
      ),
      InsightEvidence(
        kind: EvidenceKind.ruleInference,
        statement: 'Virtual category: ${record.category.name}.',
        source: 'classification rules',
      ),
    ];
    if (record.sha256 != null) {
      evidence.add(
        const InsightEvidence(
          kind: EvidenceKind.fact,
          statement: 'A complete SHA-256 fingerprint is available.',
          source: 'local hash',
        ),
      );
    }
    return InsightRecord(
      summary: _summary(record),
      fileType: record.category.name,
      probableOrigin: _origin(record),
      whyItExists:
          'The local index observed this item at its original locator.',
      spaceUsageBytes: record.sizeBytes,
      riskLevel: risk,
      confidence: confidence,
      evidence: evidence,
      recommendedActions: _actions(record, risk),
      limitations: [?limitation],
    );
  }

  String _summary(FileRecord record) =>
      record.category == VirtualCategory.unknown
      ? 'This item is indexed, but its type is not yet understood.'
      : 'This is a locally indexed ${record.category.name} item.';

  String? _origin(FileRecord record) => switch (record.sourceKind) {
    SourceKind.mediaStore => 'Android MediaStore',
    SourceKind.storageAccessFramework => 'User-selected Android storage',
    SourceKind.downloads => 'Downloads source',
    SourceKind.fileSystem => 'Windows file system',
    SourceKind.synthetic => 'Synthetic test fixture',
    _ => null,
  };

  (RiskLevel, double, String?) _risk(FileRecord record) {
    if (record.isProtected || record.isSystem) {
      return (
        RiskLevel.protected,
        1,
        'Protected items are not eligible for direct deletion.',
      );
    }
    if (!record.isAccessible) {
      return (
        RiskLevel.unknown,
        1,
        'The platform does not allow PickLogic to inspect this item.',
      );
    }
    if (record.category == VirtualCategory.unknown) {
      return (
        RiskLevel.unknown,
        0.35,
        'Metadata is insufficient for a reliable recommendation.',
      );
    }
    return (RiskLevel.review, 0.8, null);
  }

  List<String> _actions(FileRecord record, RiskLevel risk) {
    if (risk == RiskLevel.protected || risk == RiskLevel.unknown) {
      return const ['View details', 'Locate original item'];
    }
    return const ['Open', 'Locate original item', 'Add to review list'];
  }
}
