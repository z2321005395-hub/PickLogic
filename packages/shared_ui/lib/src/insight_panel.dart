import 'package:flutter/material.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

final class InsightPanel extends StatelessWidget {
  const InsightPanel({super.key, required this.insight});

  final InsightRecord insight;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('知件 · Insight', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      Text(insight.summary),
      const SizedBox(height: 16),
      _Detail(label: 'Type', value: insight.fileType),
      _Detail(label: 'Risk', value: insight.riskLevel.name.toUpperCase()),
      _Detail(
        label: 'Confidence',
        value: '${(insight.confidence * 100).round()}%',
      ),
      if (insight.spaceUsageBytes != null)
        _Detail(label: 'Bytes', value: '${insight.spaceUsageBytes}'),
      const SizedBox(height: 12),
      ...insight.evidence.map(
        (item) => ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.fact_check_outlined, size: 18),
          title: Text(item.statement),
          subtitle: Text('${item.kind.name} · ${item.source}'),
        ),
      ),
      if (insight.limitations.isNotEmpty) ...[
        const Divider(),
        ...insight.limitations.map((item) => Text('Limit: $item')),
      ],
    ],
  );
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
