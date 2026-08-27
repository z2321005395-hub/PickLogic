import 'dart:async';

import 'package:flutter/material.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_insight_engine/picklogic_insight_engine.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

import 'desktop_repository.dart';

final class DesktopFolderInsightService {
  const DesktopFolderInsightService(this.repository);

  final DesktopRepository repository;

  Future<FolderInsight> inspectOne(String path) async {
    final node = _node(path);
    final inspection = await _inspect(node, FolderScanCancellation());
    return const FolderInsightEngine().explain(inspection.observation);
  }

  Future<FolderScanResult> scan(
    String rootPath, {
    FolderScanCancellation? cancellation,
    FolderProgressCallback? onProgress,
    FolderInsightCallback? onInsight,
  }) => const FolderTreeScanner().scan(
    roots: <FolderNode>[_node(rootPath)],
    inspector: _inspect,
    cancellation: cancellation,
    onProgress: onProgress,
    onInsight: onInsight,
  );

  Future<FolderInspection> _inspect(
    FolderNode node,
    FolderScanCancellation cancellation,
  ) async {
    if (cancellation.cancelled) {
      throw StateError('Folder inspection was cancelled.');
    }
    final summary = await repository.inspectDirectory(node.locator);
    return FolderInspection(
      observation: FolderObservation(
        locator: summary.path,
        displayName: node.displayName,
        pathSegments: node.pathSegments,
        platform: PickLogicPlatform.windows,
        directFileCount: summary.directFileCount,
        directDirectoryCount: summary.directDirectoryCount,
        directFileBytes: summary.directFileBytes,
        mimeFamilyCounts: summary.mimeFamilyCounts,
      ),
      children: summary.directories
          .map(
            (entry) => FolderNode(
              locator: entry.path,
              displayName: entry.name,
              pathSegments: <String>[...node.pathSegments, entry.name],
              platform: PickLogicPlatform.windows,
            ),
          )
          .toList(growable: false),
    );
  }

  FolderNode _node(String path) => FolderNode(
    locator: path,
    displayName: _folderName(path),
    pathSegments: _pathSegments(path),
    platform: PickLogicPlatform.windows,
  );
}

final class DesktopFolderInsightCard extends StatefulWidget {
  const DesktopFolderInsightCard({
    super.key,
    required this.repository,
    required this.chinese,
  });

  final DesktopRepository repository;
  final bool chinese;

  @override
  State<DesktopFolderInsightCard> createState() =>
      _DesktopFolderInsightCardState();
}

final class _DesktopFolderInsightCardState
    extends State<DesktopFolderInsightCard> {
  final List<FolderInsight> _live = <FolderInsight>[];
  String? _rootPath;
  FolderScanProgress? _progress;
  FolderScanResult? _result;
  FolderScanCancellation? _cancellation;
  bool _choosing = false;
  bool _scanning = false;
  bool _failed = false;

  _DesktopFolderStrings get _strings => _DesktopFolderStrings(widget.chinese);

  Future<void> _chooseAndScan() async {
    if (_choosing || _scanning) return;
    setState(() => _choosing = true);
    try {
      final path = await widget.repository.chooseBrowseFolder(
        chinese: widget.chinese,
      );
      if (!mounted || path == null) return;
      setState(() => _rootPath = path);
      await _scan();
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _scan() async {
    final rootPath = _rootPath;
    if (rootPath == null || _scanning) return;
    final cancellation = FolderScanCancellation();
    setState(() {
      _cancellation = cancellation;
      _scanning = true;
      _failed = false;
      _progress = null;
      _result = null;
      _live.clear();
    });
    try {
      final result = await DesktopFolderInsightService(widget.repository).scan(
        rootPath,
        cancellation: cancellation,
        onInsight: (insight) {
          if (mounted) setState(() => _live.add(insight));
        },
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) setState(() => _result = result);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _cancellation = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings;
    final available = _result?.insights ?? _live;
    final unresolved = available.where((item) => item.unresolved).length;
    return Card(
      key: const Key('desktop-folder-insight-card'),
      child: Padding(
        padding: const EdgeInsets.all(PickLogicTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_special_outlined),
                const SizedBox(width: PickLogicTokens.spaceSm),
                Expanded(
                  child: Text(
                    strings.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PickLogicTokens.spaceSm),
            Text(strings.description),
            if (_rootPath case final path?) ...[
              const SizedBox(height: PickLogicTokens.spaceMd),
              SelectableText(path, maxLines: 2),
            ],
            if (_scanning) ...[
              const SizedBox(height: PickLogicTokens.spaceMd),
              const LinearProgressIndicator(),
              const SizedBox(height: PickLogicTokens.spaceXs),
              Text(strings.progress(_progress, _live.length, unresolved)),
            ],
            if (_failed) ...[
              const SizedBox(height: PickLogicTokens.spaceSm),
              Text(strings.failed),
            ],
            const SizedBox(height: PickLogicTokens.spaceMd),
            Wrap(
              spacing: PickLogicTokens.spaceSm,
              runSpacing: PickLogicTokens.spaceSm,
              children: [
                FilledButton.icon(
                  key: const Key('desktop-folder-insight-choose'),
                  onPressed: _choosing || _scanning ? null : _chooseAndScan,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(strings.choose),
                ),
                if (_rootPath != null)
                  OutlinedButton.icon(
                    key: const Key('desktop-folder-insight-rescan'),
                    onPressed: _scanning ? null : _scan,
                    icon: const Icon(Icons.refresh),
                    label: Text(strings.rescan),
                  ),
                if (_scanning)
                  TextButton.icon(
                    onPressed: _cancellation?.cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(strings.stop),
                  ),
              ],
            ),
            if (available.isNotEmpty) ...[
              const Divider(height: PickLogicTokens.spaceLg),
              Text(strings.summary(available.length, unresolved)),
              const SizedBox(height: PickLogicTokens.spaceSm),
              for (final insight in available.take(4))
                _DesktopFolderInsightTile(insight: insight, strings: strings),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('desktop-folder-insight-view-all'),
                  onPressed: () => _showResults(context, available),
                  icon: const Icon(Icons.list_alt_outlined),
                  label: Text(strings.viewAll(available.length)),
                ),
              ),
            ],
            const SizedBox(height: PickLogicTokens.spaceSm),
            Text(strings.safety, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Future<void> _showResults(
    BuildContext context,
    List<FolderInsight> insights,
  ) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 820,
        height: 680,
        child: _DesktopFolderResults(
          insights: List<FolderInsight>.unmodifiable(insights),
          strings: _strings,
        ),
      ),
    ),
  );
}

final class DesktopSelectedFolderInsight extends StatefulWidget {
  const DesktopSelectedFolderInsight({
    super.key,
    required this.repository,
    required this.path,
    required this.chinese,
  });

  final DesktopRepository repository;
  final String path;
  final bool chinese;

  @override
  State<DesktopSelectedFolderInsight> createState() =>
      _DesktopSelectedFolderInsightState();
}

final class _DesktopSelectedFolderInsightState
    extends State<DesktopSelectedFolderInsight> {
  late Future<FolderInsight> _future;

  @override
  void initState() {
    super.initState();
    _future = DesktopFolderInsightService(
      widget.repository,
    ).inspectOne(widget.path);
  }

  @override
  void didUpdateWidget(covariant DesktopSelectedFolderInsight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.repository != widget.repository) {
      _future = DesktopFolderInsightService(
        widget.repository,
      ).inspectOne(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FolderInsight>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text(
          widget.chinese
              ? '无法读取该文件夹；它可能受保护或已经不可用。'
              : 'This folder could not be read. It may be protected or unavailable.',
        );
      }
      final insight = snapshot.data;
      if (insight == null) return const LinearProgressIndicator();
      return DesktopFolderInsightDetails(
        insight: insight,
        chinese: widget.chinese,
        compact: true,
      );
    },
  );
}

final class _DesktopFolderResults extends StatefulWidget {
  const _DesktopFolderResults({required this.insights, required this.strings});

  final List<FolderInsight> insights;
  final _DesktopFolderStrings strings;

  @override
  State<_DesktopFolderResults> createState() => _DesktopFolderResultsState();
}

final class _DesktopFolderResultsState extends State<_DesktopFolderResults> {
  final TextEditingController _search = TextEditingController();
  bool _unresolvedOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = widget.insights
        .where((insight) {
          if (_unresolvedOnly && !insight.unresolved) return false;
          return query.isEmpty ||
              insight.observation.displayPath.toLowerCase().contains(query);
        })
        .toList(growable: false);
    return Column(
      children: [
        ListTile(
          title: Text(widget.strings.title),
          subtitle: Text(widget.strings.visible(visible.length)),
          trailing: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PickLogicTokens.spaceLg,
          ),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: widget.strings.search,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(PickLogicTokens.spaceMd),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: Text(widget.strings.unresolvedOnly),
              selected: _unresolvedOnly,
              onSelected: (value) => setState(() => _unresolvedOnly = value),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(widget.strings.noMatches))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PickLogicTokens.spaceLg,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) => _DesktopFolderInsightTile(
                    insight: visible[index],
                    strings: widget.strings,
                  ),
                ),
        ),
      ],
    );
  }
}

final class _DesktopFolderInsightTile extends StatelessWidget {
  const _DesktopFolderInsightTile({
    required this.insight,
    required this.strings,
  });

  final FolderInsight insight;
  final _DesktopFolderStrings strings;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      insight.unresolved ? Icons.help_outline : Icons.folder_special_outlined,
    ),
    title: Text(insight.observation.displayName),
    subtitle: Text(
      '${strings.role(insight.role)} · ${strings.confidence(insight.confidence)}\n'
      '${insight.observation.displayPath}',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
    isThreeLine: true,
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(insight.observation.displayName),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: DesktopFolderInsightDetails(
              insight: insight,
              chinese: strings.chinese,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.close),
          ),
        ],
      ),
    ),
  );
}

final class DesktopFolderInsightDetails extends StatelessWidget {
  const DesktopFolderInsightDetails({
    super.key,
    required this.insight,
    required this.chinese,
    this.compact = false,
  });

  final FolderInsight insight;
  final bool chinese;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = _DesktopFolderStrings(chinese);
    final observation = insight.observation;
    final facts = <String>[
      strings.access,
      strings.children(observation),
      strings.directSize(observation.directFileBytes),
    ];
    return Column(
      key: const Key('desktop-folder-insight-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          context,
          strings.location,
          observation.displayPath,
          selectable: true,
        ),
        _section(context, strings.whatItIs, strings.purpose(insight)),
        _section(context, strings.facts, facts.join('\n')),
        _section(
          context,
          strings.inference,
          '${strings.owner(insight)}\n${strings.role(insight.role)}\n'
          '${strings.risk(insight.riskLevel)} · ${strings.confidence(insight.confidence)}',
        ),
        if (!compact)
          _section(
            context,
            strings.evidence,
            insight.evidence
                .map((item) => '• ${strings.evidenceText(item)}')
                .join('\n'),
          ),
        _section(context, strings.recommendation, strings.recommend(insight)),
        _section(context, strings.limitations, strings.limitation(insight)),
      ],
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    String body, {
    bool selectable = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: PickLogicTokens.spaceMd),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: PickLogicTokens.spaceXs),
        if (selectable) SelectableText(body) else Text(body),
      ],
    ),
  );
}

final class _DesktopFolderStrings {
  const _DesktopFolderStrings(this.chinese);

  final bool chinese;

  String get title => chinese ? '文件夹知件' : 'Folder Insight';
  String get description => chinese
      ? '选择一个目录后，拾理会只读遍历全部子目录，并优先列出尚未识别的文件夹。'
      : 'Choose a folder to traverse all subfolders read-only and surface unresolved folders first.';
  String get choose => chinese ? '选择目录并开始分析' : 'Choose folder and analyze';
  String get rescan => chinese ? '重新分析' : 'Analyze again';
  String get stop => chinese ? '停止' : 'Stop';
  String get failed => chinese
      ? '分析未完成；部分目录可能受保护。没有修改任何文件。'
      : 'Analysis did not finish; some folders may be protected. No file was changed.';
  String get safety => chinese
      ? '只读取文件夹名称和直接子项元数据；不会打开文件正文、修改目录或把未知项目判定为垃圾。'
      : 'Reads only folder names and direct-child metadata. It never opens file bodies, changes folders, or labels unknown items as junk.';
  String get search => chinese ? '搜索文件夹名称或路径' : 'Search folder name or path';
  String get unresolvedOnly => chinese ? '只看尚未识别' : 'Unresolved only';
  String get noMatches => chinese ? '没有匹配的文件夹' : 'No matching folders';
  String get close => chinese ? '关闭' : 'Close';
  String get location => chinese ? '位置' : 'Location';
  String get whatItIs => chinese ? '这是什么' : 'What it is';
  String get facts => chinese ? '已验证事实' : 'Verified facts';
  String get inference => chinese ? '规则推断' : 'Rule inference';
  String get evidence => chinese ? '判断证据' : 'Evidence';
  String get recommendation => chinese ? '建议操作' : 'Recommended action';
  String get limitations => chinese ? '无法确认的部分' : 'Limitations';
  String get access => chinese ? '访问状态：本地只读' : 'Access: local, read-only';

  String progress(FolderScanProgress? progress, int count, int unresolved) {
    if (progress == null) return chinese ? '正在准备…' : 'Preparing…';
    return chinese
        ? '已解释 $count 个文件夹，尚未识别 $unresolved 个，待分析 ${progress.pending} 个。'
        : '$count folders explained; $unresolved unresolved; ${progress.pending} pending.';
  }

  String summary(int count, int unresolved) => chinese
      ? '已解释 $count 个文件夹，其中 $unresolved 个仍需人工判断。'
      : '$count folders explained; $unresolved still need review.';
  String viewAll(int count) => chinese ? '查看全部 $count 个' : 'View all $count';
  String visible(int count) => chinese ? '显示 $count 项' : '$count shown';
  String children(FolderObservation observation) => chinese
      ? '当前层：${observation.directDirectoryCount} 个子目录，${observation.directFileCount} 个文件'
      : 'Direct children: ${observation.directDirectoryCount} folders and ${observation.directFileCount} files';
  String directSize(int bytes) => chinese
      ? '当前层文件合计：${formatFileSize(bytes)}'
      : 'Direct-file total: ${formatFileSize(bytes)}';
  String confidence(double value) => chinese
      ? '置信度 ${(value * 100).round()}%'
      : '${(value * 100).round()}% confidence';
  String owner(FolderInsight insight) => insight.probableOwner == null
      ? (chinese ? '可能所属：无法确认' : 'Probable owner: not confirmed')
      : (chinese
            ? '可能所属：${insight.probableOwner}'
            : 'Probable owner: ${insight.probableOwner}');
  String purpose(FolderInsight insight) => insight.unresolved
      ? (chinese
            ? '现有路径和直接子项元数据不足以确定用途；未知不等于无用或可删除。'
            : 'Path and direct-child metadata are insufficient. Unknown does not mean useless or safe to delete.')
      : (chinese
            ? '最可能是“${role(insight.role)}”。这是基于本地元数据的规则判断。'
            : 'Most likely: ${role(insight.role)}. This is a local metadata rule inference.');
  String recommend(FolderInsight insight) {
    if (insight.riskLevel == RiskLevel.protected) {
      return chinese
          ? '保持原状；通过 Windows 或所属软件的官方设置确认用途。'
          : 'Leave it unchanged and confirm it through Windows or the owning app.';
    }
    if (insight.unresolved) {
      return chinese
          ? '先查看其中的文件类型和来源；确认用途前不要删除、移动或重命名。'
          : 'Inspect file types and origin before deleting, moving, or renaming.';
    }
    return chinese
        ? '可继续只读查看并用于虚拟分类；知件不会直接清理该目录。'
        : 'Continue read-only inspection and virtual classification; Insight will not clean it directly.';
  }

  String limitation(FolderInsight insight) => insight.observation.accessible
      ? (chinese
            ? '未读取文件正文，也未核验注册表、服务或应用私有数据库。'
            : 'File bodies, registry, services, and private app databases were not inspected.')
      : (chinese
            ? 'Windows 拒绝读取该目录；拾理不会绕过权限。'
            : 'Windows denied this directory; PickLogic will not bypass permissions.');

  String risk(RiskLevel risk) => switch (risk) {
    RiskLevel.safe => chinese ? '可安全处理' : 'Safe',
    RiskLevel.review => chinese ? '需要审查' : 'Review',
    RiskLevel.protected => chinese ? '受保护' : 'Protected',
    RiskLevel.unknown => chinese ? '未知' : 'Unknown',
  };

  String role(FolderRole role) => switch (role) {
    FolderRole.driveRoot => chinese ? '磁盘根目录' : 'Drive root',
    FolderRole.userHome => chinese ? '用户主目录' : 'User home',
    FolderRole.desktop => chinese ? '桌面目录' : 'Desktop',
    FolderRole.camera => chinese ? '相机媒体目录' : 'Camera media',
    FolderRole.screenshots => chinese ? '截图目录' : 'Screenshots',
    FolderRole.downloads => chinese ? '下载目录' : 'Downloads',
    FolderRole.documents => chinese ? '文档目录' : 'Documents',
    FolderRole.images => chinese ? '图片目录' : 'Images',
    FolderRole.videos => chinese ? '视频目录' : 'Videos',
    FolderRole.audio => chinese ? '音频目录' : 'Audio',
    FolderRole.recordings => chinese ? '录音目录' : 'Recordings',
    FolderRole.appSharedMedia => chinese ? '应用共享媒体' : 'App shared media',
    FolderRole.applicationData => chinese ? '应用数据目录' : 'Application data',
    FolderRole.applicationInstall =>
      chinese ? '程序安装目录' : 'Program installation',
    FolderRole.systemManaged => chinese ? '系统管理目录' : 'System-managed folder',
    FolderRole.cache => chinese ? '缓存线索' : 'Cache clue',
    FolderRole.thumbnails => chinese ? '缩略图缓存线索' : 'Thumbnail cache clue',
    FolderRole.temporary => chinese ? '临时文件线索' : 'Temporary-file clue',
    FolderRole.logs => chinese ? '日志线索' : 'Log clue',
    FolderRole.backups => chinese ? '备份线索' : 'Backup clue',
    FolderRole.trash => chinese ? '回收目录' : 'Trash area',
    FolderRole.hidden => chinese ? '隐藏目录' : 'Hidden folder',
    FolderRole.cloudSync => chinese ? '云同步目录' : 'Cloud-sync folder',
    FolderRole.development => chinese ? '开发项目目录' : 'Development folder',
    FolderRole.researchData => chinese ? '科研资料目录' : 'Research folder',
    FolderRole.mixedContent => chinese ? '混合内容目录' : 'Mixed-content folder',
    FolderRole.unknown => chinese ? '尚未识别' : 'Unresolved',
  };

  String evidenceText(FolderEvidence evidence) => switch (evidence) {
    FolderEvidence.readOnlyMetadata =>
      chinese
          ? '来自本地只读目录枚举。'
          : 'Observed through local read-only directory enumeration.',
    FolderEvidence.standardFolderName =>
      chinese ? '名称匹配常见文件夹约定。' : 'The name matches a common folder convention.',
    FolderEvidence.platformPathConvention =>
      chinese
          ? '路径匹配 Windows 或 Android 平台结构约定。'
          : 'The path matches a Windows or Android platform convention.',
    FolderEvidence.packageIdentifier =>
      chinese
          ? '路径包含应用包标识。'
          : 'The path contains an application package identifier.',
    FolderEvidence.parentContext =>
      chinese ? '父目录结构提供了用途线索。' : 'The parent path provides a purpose clue.',
    FolderEvidence.directChildMetadata =>
      chinese
          ? '直接子项类型构成提供了内容线索。'
          : 'Direct-child types provide a content clue.',
    FolderEvidence.hiddenName =>
      chinese ? '名称表明这是隐藏目录。' : 'The name indicates a hidden folder.',
    FolderEvidence.emptyFolder =>
      chinese ? '当前层没有可见文件。' : 'No directly visible files were found.',
    FolderEvidence.providerFailure =>
      chinese
          ? '平台拒绝或未能读取该目录。'
          : 'The platform denied or failed this directory read.',
    FolderEvidence.boundedObservation =>
      chinese ? '仅取得有界元数据样本。' : 'Only a bounded metadata sample was available.',
  };
}

String _folderName(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  if (RegExp(r'^[A-Za-z]:$').hasMatch(normalized)) return normalized;
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

List<String> _pathSegments(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  return normalized.split('/').where((part) => part.isNotEmpty).toList();
}
