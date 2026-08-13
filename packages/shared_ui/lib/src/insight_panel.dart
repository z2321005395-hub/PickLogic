import 'package:flutter/material.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

final class InsightPanel extends StatelessWidget {
  const InsightPanel({super.key, required this.insight});

  final InsightRecord insight;

  @override
  Widget build(BuildContext context) {
    final strings = _InsightStrings(
      Localizations.localeOf(context).languageCode == 'zh',
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(strings.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Text(insight.summary),
        const SizedBox(height: 16),
        _Detail(label: strings.type, value: insight.fileType),
        _Detail(
          label: strings.risk,
          value: strings.riskName(insight.riskLevel),
        ),
        _Detail(
          label: strings.confidence,
          value: '${(insight.confidence * 100).round()}%',
        ),
        if (insight.spaceUsageBytes != null)
          _Detail(label: strings.bytes, value: '${insight.spaceUsageBytes}'),
        const SizedBox(height: 12),
        ...insight.evidence.map(
          (item) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.fact_check_outlined, size: 18),
            title: Text(item.statement),
            subtitle: Text(
              '${strings.evidenceKind(item.kind)}: ${item.source}',
            ),
          ),
        ),
        if (insight.limitations.isNotEmpty) ...[
          const Divider(),
          ...insight.limitations.map((item) => Text('${strings.limit}: $item')),
        ],
      ],
    );
  }
}

final class _InsightStrings {
  const _InsightStrings(this.chinese);

  final bool chinese;

  String get title => chinese ? '知件' : 'Insight';
  String get type => chinese ? '类型' : 'Type';
  String get risk => chinese ? '风险' : 'Risk';
  String get confidence => chinese ? '置信度' : 'Confidence';
  String get bytes => chinese ? '字节数' : 'Bytes';
  String get limit => chinese ? '限制' : 'Limit';

  String riskName(RiskLevel risk) => switch (risk) {
    RiskLevel.safe => chinese ? '安全' : 'Safe',
    RiskLevel.review => chinese ? '需复核' : 'Review',
    RiskLevel.protected => chinese ? '受保护' : 'Protected',
    RiskLevel.unknown => chinese ? '未知' : 'Unknown',
  };

  String evidenceKind(EvidenceKind kind) => switch (kind) {
    EvidenceKind.fact => chinese ? '事实' : 'Fact',
    EvidenceKind.ruleInference => chinese ? '规则推断' : 'Rule inference',
    EvidenceKind.lowConfidenceGuess =>
      chinese ? '低置信推测' : 'Low-confidence guess',
    EvidenceKind.platformRestriction =>
      chinese ? '平台限制' : 'Platform restriction',
  };
}

final class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(width: 88, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
