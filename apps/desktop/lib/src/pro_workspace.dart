import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_research_core/picklogic_research_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_system_insight_core/picklogic_system_insight_core.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

import 'pro_pdf_reader.dart';

const Set<String> proWorkspaceSections = {'literature', 'research', 'system'};

typedef LiteraturePdfPicker = Future<String?> Function();
typedef LiteraturePdfSourceBuilder = PdfByteSource Function(String path);
typedef LiteraturePdfReaderBuilder =
    Widget Function(
      BuildContext context,
      LiteratureLibraryEntry entry,
      LiteratureReadingPositionChanged onPositionChanged,
    );

final class ProWorkspaceRoute extends StatelessWidget {
  const ProWorkspaceRoute({
    super.key,
    required this.section,
    this.pdfReaderBuilder,
    this.libraryStore,
    this.pdfPicker,
    this.pdfSourceBuilder,
    this.literaturePdfReaderBuilder,
  });

  final String section;
  final WidgetBuilder? pdfReaderBuilder;
  final LiteratureLibraryStore? libraryStore;
  final LiteraturePdfPicker? pdfPicker;
  final LiteraturePdfSourceBuilder? pdfSourceBuilder;
  final LiteraturePdfReaderBuilder? literaturePdfReaderBuilder;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_routeTitle(section))),
    body: Column(
      children: [
        const Align(alignment: Alignment.centerLeft, child: SafeModeBanner()),
        Expanded(
          child: ProWorkspaceView(
            section: section,
            pdfReaderBuilder: pdfReaderBuilder,
            libraryStore: libraryStore,
            pdfPicker: pdfPicker,
            pdfSourceBuilder: pdfSourceBuilder,
            literaturePdfReaderBuilder: literaturePdfReaderBuilder,
          ),
        ),
      ],
    ),
  );
}

final class ProWorkspaceView extends StatelessWidget {
  const ProWorkspaceView({
    super.key,
    required this.section,
    this.pdfReaderBuilder,
    this.libraryStore,
    this.pdfPicker,
    this.pdfSourceBuilder,
    this.literaturePdfReaderBuilder,
  });

  final String section;
  final WidgetBuilder? pdfReaderBuilder;
  final LiteratureLibraryStore? libraryStore;
  final LiteraturePdfPicker? pdfPicker;
  final LiteraturePdfSourceBuilder? pdfSourceBuilder;
  final LiteraturePdfReaderBuilder? literaturePdfReaderBuilder;

  @override
  Widget build(BuildContext context) => switch (section) {
    'literature' => LiteratureManagerLiteView(
      pdfReaderBuilder: pdfReaderBuilder,
      libraryStore: libraryStore,
      pdfPicker: pdfPicker,
      pdfSourceBuilder: pdfSourceBuilder,
      literaturePdfReaderBuilder: literaturePdfReaderBuilder,
    ),
    'research' => const ResearchBucketsView(),
    'system' => const SystemInsightReadOnlyView(),
    _ => const SizedBox.shrink(),
  };
}

final class LiteratureManagerLiteView extends StatefulWidget {
  const LiteratureManagerLiteView({
    super.key,
    this.pdfReaderBuilder,
    this.libraryStore,
    this.pdfPicker,
    this.pdfSourceBuilder,
    this.literaturePdfReaderBuilder,
  });

  final WidgetBuilder? pdfReaderBuilder;
  final LiteratureLibraryStore? libraryStore;
  final LiteraturePdfPicker? pdfPicker;
  final LiteraturePdfSourceBuilder? pdfSourceBuilder;
  final LiteraturePdfReaderBuilder? literaturePdfReaderBuilder;

  @override
  State<LiteratureManagerLiteView> createState() =>
      _LiteratureManagerLiteViewState();
}

final class _LiteratureManagerLiteViewState
    extends State<LiteratureManagerLiteView> {
  late final Future<LiteratureLibraryStore> _storeFuture;
  Future<void> _saveTail = Future<void>.value();
  List<LiteratureLibraryEntry> _entries = const <LiteratureLibraryEntry>[];
  String? _selectedId;
  String? _status;
  bool _loading = true;
  bool _adding = false;
  bool _catalogAvailable = true;

  @override
  void initState() {
    super.initState();
    _storeFuture = widget.libraryStore == null
        ? _createDefaultStore()
        : Future<LiteratureLibraryStore>.value(widget.libraryStore);
    unawaited(_loadLibrary());
  }

  Future<LiteratureLibraryStore> _createDefaultStore() async {
    final supportDirectory = await const PicklogicWindowsBridge()
        .getApplicationSupportDirectory();
    return JsonFileLiteratureLibraryStore(
      '$supportDirectory${Platform.pathSeparator}literature_catalog_v1.json',
    );
  }

  Future<void> _loadLibrary() async {
    try {
      final store = await _storeFuture;
      final entries = await store.load();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _selectedId = entries.firstOrNull?.id;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _catalogAvailable = false;
        _status = '文献目录不可用；为避免覆盖现有状态，添加功能已暂停。';
      });
    }
  }

  Future<void> _addLiterature() async {
    if (_adding || !_catalogAvailable) return;
    setState(() {
      _adding = true;
      _status = null;
    });
    try {
      final path =
          await (widget.pdfPicker?.call() ??
              const PicklogicWindowsBridge().pickPdfFile(title: '添加本地 PDF 文献'));
      if (path == null) return;
      if (!path.toLowerCase().endsWith('.pdf')) {
        setState(() => _status = '仅支持本地 PDF 文件。');
        return;
      }
      final normalizedPath = path.toLowerCase();
      final existing = _entries
          .where((entry) => entry.localPath.toLowerCase() == normalizedPath)
          .firstOrNull;
      if (existing != null) {
        setState(() {
          _selectedId = existing.id;
          _status = '该 PDF 已在文献列表中。';
        });
        return;
      }

      final source =
          widget.pdfSourceBuilder?.call(path) ?? FilePdfByteSource(path);
      final probe = await const BoundedPdfMetadataReader().read(source);
      if (!probe.hasPdfHeader) {
        setState(() => _status = '所选文件未通过 PDF 头部验证，未添加。');
        return;
      }
      final entry = LiteratureLibraryEntry.fromProbe(
        localPath: path,
        fileName: _fileNameFromPath(path),
        probe: probe,
        addedAt: DateTime.now().toUtc(),
      );
      final updated = List<LiteratureLibraryEntry>.unmodifiable([
        entry,
        ..._entries,
      ]);
      await _enqueueSave(updated);
      if (!mounted) return;
      setState(() {
        _entries = updated;
        _selectedId = entry.id;
        _status = '文献已添加；PDF 原文件保持只读且位置不变。';
      });
    } on Object {
      if (mounted) {
        setState(() => _status = '无法添加此 PDF；目录状态与原文件均未更改。');
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _enqueueSave(List<LiteratureLibraryEntry> entries) {
    final operation = _saveTail.then((_) async {
      final store = await _storeFuture;
      await store.save(entries);
    });
    _saveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _recordPosition(String id, int currentPage, int totalPages) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final updatedEntry = _entries[index].recordPosition(
      currentPage: currentPage,
      totalPages: totalPages,
      openedAt: DateTime.now().toUtc(),
    );
    final updated = List<LiteratureLibraryEntry>.of(_entries);
    updated[index] = updatedEntry;
    final snapshot = List<LiteratureLibraryEntry>.unmodifiable(updated);
    setState(() => _entries = snapshot);
    unawaited(_persistReadingPosition(snapshot));
  }

  Future<void> _persistReadingPosition(
    List<LiteratureLibraryEntry> snapshot,
  ) async {
    try {
      await _enqueueSave(snapshot);
    } on Object {
      if (mounted) setState(() => _status = '阅读位置暂未保存；PDF 未被修改。');
    }
  }

  LiteratureLibraryEntry? get _selectedEntry =>
      _entries.where((entry) => entry.id == _selectedId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedEntry;
    final renamePreview = selected == null
        ? null
        : const LiteratureNaming().previewRename(
            record: selected.record,
            originalFileName: selected.fileName,
          );
    final progressPercent = selected == null
        ? 0
        : (selected.record.readingProgress * 100).round();
    return ListView(
      key: const Key('literature-manager-lite-view'),
      padding: const EdgeInsets.all(24),
      children: [
        _ProHeader(
          icon: Icons.menu_book_outlined,
          title: 'Literature Manager Lite',
          subtitle: '本地目录 · 有界元数据 · PDF 不上传、不改写',
          badge: 'LOCAL READ-ONLY',
          trailing: FilledButton.icon(
            key: const Key('literature-add-action'),
            onPressed: _loading || _adding || !_catalogAvailable
                ? null
                : _addLiterature,
            icon: _adding
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: const Text('添加文献'),
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(_status!, key: const Key('literature-status')),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_entries.isEmpty)
          const _ProCard(
            title: '文献列表',
            child: Text('暂无文献。点击“添加文献”选择一个本地 PDF；不会扫描目录。'),
          )
        else
          _ProCard(
            title: '文献列表 · Persistent',
            child: ListView.separated(
              key: const Key('literature-library-list'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final record = entry.record;
                return ListTile(
                  key: Key('literature-entry-${entry.id}'),
                  selected: entry.id == _selectedId,
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(record.title),
                  subtitle: Text(
                    '${entry.fileName}\n'
                    '${record.authors.isEmpty ? 'Author unknown' : record.authors.join('; ')} · '
                    '${record.year?.toString() ?? 'Year unknown'} · '
                    '${record.doi ?? 'DOI not found'}',
                  ),
                  isThreeLine: true,
                  trailing: Text('${(record.readingProgress * 100).round()}%'),
                  onTap: () => setState(() => _selectedId = entry.id),
                );
              },
            ),
          ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          _ProCard(
            title: '文献元数据',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LabelValue(label: 'Filename', value: selected.fileName),
                _LabelValue(label: 'Title', value: selected.record.title),
                _LabelValue(
                  label: 'Author',
                  value: selected.record.authors.isEmpty
                      ? '未发现'
                      : selected.record.authors.join('; '),
                ),
                _LabelValue(label: 'DOI', value: selected.record.doi ?? '未发现'),
                _LabelValue(
                  label: 'Year',
                  value: selected.record.year?.toString() ?? '未发现',
                ),
                const SizedBox(height: 8),
                const Text('元数据来自 PDF 首尾有界窗口；压缩或加密字段可能无法识别。'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ProCard(
            title: 'PDF 阅读区域 · Local',
            child:
                widget.literaturePdfReaderBuilder?.call(
                  context,
                  selected,
                  (currentPage, totalPages) =>
                      _recordPosition(selected.id, currentPage, totalPages),
                ) ??
                widget.pdfReaderBuilder?.call(context) ??
                ProLocalPdfReader(
                  key: ValueKey<String>(selected.id),
                  path: selected.localPath,
                  fileName: selected.fileName,
                  initialPageNumber: selected.currentPage,
                  onPositionChanged: (currentPage, totalPages) =>
                      _recordPosition(selected.id, currentPage, totalPages),
                ),
          ),
          const SizedBox(height: 12),
          _ProCard(
            title: '阅读进度 · Persistent',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$progressPercent%',
                  key: const Key('literature-progress-value'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                LinearProgressIndicator(value: selected.record.readingProgress),
                const SizedBox(height: 8),
                Text(
                  selected.totalPages == null
                      ? '页码将在 PDF 打开后保存。'
                      : '第 ${selected.currentPage} / ${selected.totalPages} 页',
                  key: const Key('literature-page-position'),
                ),
                const Text('进度仅写入 PickLogic 私有目录，不写入 PDF。'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ProCard(
            title: '自动命名 Preview',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LabelValue(label: 'Current', value: selected.fileName),
                _LabelValue(
                  label: 'Preview',
                  value: renamePreview!.proposedFileName,
                ),
                const SizedBox(height: 8),
                const Text('Preview only · 未创建 OperationPlan · 未执行重命名'),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const _ProCard(
          title: 'Translation · Coming next',
          child: Text('翻译尚未启用；未来只处理用户明确选择的文本，默认关闭。'),
        ),
        const SizedBox(height: 12),
        const Text('列表仅保存本地引用和阅读状态；不会扫描文献目录、上传 PDF 或改动原文件。'),
      ],
    );
  }

  String _fileNameFromPath(String path) =>
      path.replaceAll('\\', '/').split('/').last;
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
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Widget? trailing;

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
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
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
