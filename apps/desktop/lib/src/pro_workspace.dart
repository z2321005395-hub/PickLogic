import 'package:flutter/material.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_research_core/picklogic_research_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_system_insight_core/picklogic_system_insight_core.dart';

const Set<String> proWorkspaceSections = {'literature', 'research', 'system'};

final class ProWorkspaceRoute extends StatelessWidget {
  const ProWorkspaceRoute({super.key, required this.section});

  final String section;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_routeTitle(section))),
    body: Column(
      children: [
        const Align(alignment: Alignment.centerLeft, child: SafeModeBanner()),
        Expanded(child: ProWorkspaceView(section: section)),
      ],
    ),
  );
}

final class ProWorkspaceView extends StatelessWidget {
  const ProWorkspaceView({super.key, required this.section});

  final String section;

  @override
  Widget build(BuildContext context) => switch (section) {
    'literature' => const LiteratureManagerLiteView(),
    'research' => const ResearchBucketsView(),
    'system' => const SystemInsightReadOnlyView(),
    _ => const SizedBox.shrink(),
  };
}

final class LiteratureManagerLiteView extends StatefulWidget {
  const LiteratureManagerLiteView({super.key});

  @override
  State<LiteratureManagerLiteView> createState() =>
      _LiteratureManagerLiteViewState();
}

final class _LiteratureManagerLiteViewState
    extends State<LiteratureManagerLiteView> {
  LiteratureRecord _record = const LiteratureRecord(
    id: 'synthetic-literature-1',
    localFileId: 'paper',
    doi: '10.5555/picklogic.synthetic',
    title: 'Local-first literature workflows with bounded metadata inspection',
    authors: ['Lin Researcher', 'Morgan Example'],
    journal: 'Synthetic Research Notes',
    year: 2026,
    keywords: ['local-first', 'bounded I/O', 'privacy'],
    tags: ['synthetic', 'demo'],
    readingProgress: 0.35,
    metadataSource: 'bounded local metadata sample',
    metadataConfidence: 0.82,
  );

  static const _probe = PdfMetadataProbe(
    hasPdfHeader: true,
    totalBytes: 184320,
    bytesRead: 32768,
    wasTruncated: true,
    readWindows: [
      PdfReadWindow(offset: 0, length: 16384),
      PdfReadWindow(offset: 167936, length: 16384),
    ],
    title: 'Local-first literature workflows with bounded metadata inspection',
    authors: ['Lin Researcher', 'Morgan Example'],
    keywords: ['local-first', 'bounded I/O', 'privacy'],
    doiCandidates: ['10.5555/picklogic.synthetic'],
    limitations: [
      'Synthetic sample: no real PDF was opened.',
      'The middle of the document was not inspected.',
      'A PDF rendering engine remains dependency-audit gated.',
    ],
  );

  @override
  Widget build(BuildContext context) {
    final renamePreview = const LiteratureNaming().previewRename(
      record: _record,
      originalFileName: 'Synthetic download.pdf',
    );
    final progressPercent = (_record.readingProgress * 100).round();
    return ListView(
      key: const Key('literature-manager-lite-view'),
      padding: const EdgeInsets.all(24),
      children: [
        const _ProHeader(
          icon: Icons.menu_book_outlined,
          title: 'Literature Manager Lite',
          subtitle: '合成垂直视图 · 本地元数据优先 · 不上传 PDF',
          badge: 'SYNTHETIC ONLY',
        ),
        const SizedBox(height: 16),
        _ProCard(
          title: '有界 PDF 元数据与 DOI',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _record.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _LabelValue(label: 'DOI', value: _record.doi ?? '未发现'),
              _LabelValue(label: 'Authors', value: _record.authors.join('; ')),
              _LabelValue(label: 'Journal', value: _record.journal),
              _LabelValue(label: 'Year', value: '${_record.year}'),
              _LabelValue(
                label: 'Bounded read',
                value: '${_probe.bytesRead} / ${_probe.totalBytes} bytes',
              ),
              const SizedBox(height: 8),
              const Text('只检查首尾小窗口；不会一次读取全文，也不会渲染页面。'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ProCard(
          title: 'PDF 阅读区域 · Skeleton',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PDF rendering: audit gated'),
                    SizedBox(height: 6),
                    Text(
                      '未接入 pdfrx/PDFium；许可证、二进制体积、打包和质量审计通过前，'
                      '此处不伪装成完整阅读器。',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ProCard(
          title: '阅读进度',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$progressPercent%',
                key: const Key('literature-progress-value'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Slider(
                value: _record.readingProgress,
                label: '$progressPercent%',
                onChanged: (value) => setState(() {
                  _record = const LiteratureReadingTracker().recordFraction(
                    _record,
                    progress: value,
                    openedAt: DateTime.now().toUtc(),
                  );
                }),
              ),
              const Text('当前仅更新合成会话状态，不写入 PDF 或真实文件。'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ProCard(
          title: '自动命名 Preview',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LabelValue(
                label: 'Current',
                value: 'Synthetic download.pdf',
              ),
              _LabelValue(
                label: 'Preview',
                value: renamePreview.proposedFileName,
              ),
              const SizedBox(height: 8),
              const Text('Preview only · 未创建 OperationPlan · 未执行重命名'),
            ],
          ),
        ),
      ],
    );
  }
}

final class ResearchBucketsView extends StatelessWidget {
  const ResearchBucketsView({super.key});

  @override
  Widget build(BuildContext context) {
    final workspace =
        ResearchWorkspace(
            id: 'synthetic-project',
            name: 'Synthetic microscopy project',
          )
          ..link(
            const ResearchLink(
              projectId: 'synthetic-project',
              fileId: 'paper',
              bucket: ResearchBucket.literature,
              note: 'Local literature record',
            ),
          )
          ..link(
            const ResearchLink(
              projectId: 'synthetic-project',
              fileId: 'table',
              bucket: ResearchBucket.rawData,
              note: 'Synthetic measurements',
            ),
          )
          ..link(
            const ResearchLink(
              projectId: 'synthetic-project',
              fileId: 'image',
              bucket: ResearchBucket.figures,
              note: 'Synthetic figure',
            ),
          );
    return ListView(
      key: const Key('research-buckets-view'),
      padding: const EdgeInsets.all(24),
      children: [
        const _ProHeader(
          icon: Icons.science_outlined,
          title: 'Research buckets',
          subtitle: 'Synthetic microscopy project · 虚拟关联，不移动文件',
          badge: 'VIRTUAL LINKS',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) => GridView.count(
            crossAxisCount: constraints.maxWidth >= 900 ? 4 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.65,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final summary in workspace.bucketSummaries)
                _BucketCard(summary: summary),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('Buckets 只保存文件 ID 的虚拟关联；原位置、文件名和内容均保持不变。'),
      ],
    );
  }
}

final class SystemInsightReadOnlyView extends StatelessWidget {
  const SystemInsightReadOnlyView({super.key});

  static const _observations = [
    SystemObservation(
      kind: SystemObservationKind.softwareCache,
      label: 'Synthetic application cache',
      sizeBytes: 12582912,
      isWindowsCore: false,
      isRunning: false,
      isSigned: true,
      ownerApplication: 'Synthetic App',
      evidence: ['Synthetic cache classification supplied by a fixture.'],
    ),
    SystemObservation(
      kind: SystemObservationKind.service,
      label: 'Synthetic Windows service',
      sizeBytes: 0,
      isWindowsCore: true,
      isRunning: true,
      isSigned: true,
      ownerApplication: 'Windows',
      evidence: ['Fixture marks this observation as Windows core.'],
    ),
    SystemObservation(
      kind: SystemObservationKind.unknown,
      label: 'Synthetic unknown component',
      sizeBytes: 4096,
      isWindowsCore: false,
      isRunning: false,
      isSigned: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final explainer = const SystemObservationExplainer();
    return ListView(
      key: const Key('system-insight-read-only-view'),
      padding: const EdgeInsets.all(24),
      children: [
        const _ProHeader(
          icon: Icons.monitor_heart_outlined,
          title: 'System Insight · Read-only',
          subtitle: '合成观测 · 未读取真实系统目录 · 事实、推断、限制与未知项分开呈现',
          badge: 'NO SYSTEM CHANGES',
        ),
        const SizedBox(height: 16),
        for (final observation in _observations) ...[
          _SystemObservationCard(
            observation: observation,
            insight: explainer.explain(observation),
          ),
          const SizedBox(height: 12),
        ],
        const Text('未读取真实系统目录；未修改注册表、服务、启动项、计划任务、卸载器或系统文件。'),
      ],
    );
  }
}

final class _ProHeader extends StatelessWidget {
  const _ProHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 34, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            Text(subtitle),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Chip(label: Text(badge)),
    ],
  );
}

final class _ProCard extends StatelessWidget {
  const _ProCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

final class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, child: Text(label)),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

final class _BucketCard extends StatelessWidget {
  const _BucketCard({required this.summary});

  final ResearchBucketSummary summary;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('research-bucket-${summary.bucket.name}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(_bucketIcon(summary.bucket)),
          Text(
            _bucketLabel(summary.bucket),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('${summary.count} linked item(s)'),
        ],
      ),
    ),
  );
}

final class _SystemObservationCard extends StatelessWidget {
  const _SystemObservationCard({
    required this.observation,
    required this.insight,
  });

  final SystemObservation observation;
  final InsightRecord insight;

  @override
  Widget build(BuildContext context) => _ProCard(
    title: observation.label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabelValue(label: 'Risk', value: insight.riskLevel.name.toUpperCase()),
        _LabelValue(
          label: 'Confidence',
          value: '${(insight.confidence * 100).round()}%',
        ),
        Text(insight.summary),
        const SizedBox(height: 10),
        for (final evidence in insight.evidence)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.fact_check_outlined, size: 18),
            title: Text(evidence.statement),
            subtitle: Text('${evidence.kind.name} · ${evidence.source}'),
          ),
      ],
    ),
  );
}

String _bucketLabel(ResearchBucket bucket) => switch (bucket) {
  ResearchBucket.literature => 'Literature',
  ResearchBucket.rawData => 'Raw data',
  ResearchBucket.processedData => 'Processed data',
  ResearchBucket.figures => 'Figures',
  ResearchBucket.scripts => 'Scripts',
  ResearchBucket.notes => 'Notes',
  ResearchBucket.presentations => 'Presentations',
  ResearchBucket.manuscripts => 'Manuscripts',
};

IconData _bucketIcon(ResearchBucket bucket) => switch (bucket) {
  ResearchBucket.literature => Icons.menu_book_outlined,
  ResearchBucket.rawData => Icons.dataset_outlined,
  ResearchBucket.processedData => Icons.analytics_outlined,
  ResearchBucket.figures => Icons.image_outlined,
  ResearchBucket.scripts => Icons.code_outlined,
  ResearchBucket.notes => Icons.note_alt_outlined,
  ResearchBucket.presentations => Icons.slideshow_outlined,
  ResearchBucket.manuscripts => Icons.article_outlined,
};

String _routeTitle(String section) => switch (section) {
  'literature' => '文献 · Literature',
  'research' => '研究 · Research',
  'system' => '系统洞察 · System Insight',
  _ => 'PickLogic Pro',
};
