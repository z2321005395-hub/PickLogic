import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_insight_engine/picklogic_insight_engine.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

import 'demo_records.dart';
import 'desktop_repository.dart';
import 'pro_workspace.dart';

void runPickLogicDesktop({required bool pro}) {
  runApp(PickLogicDesktopApp(pro: pro, repository: WindowsDesktopRepository()));
}

final class PickLogicDesktopApp extends StatefulWidget {
  const PickLogicDesktopApp({
    super.key,
    required this.pro,
    this.repository = const SyntheticDesktopRepository(),
    this.proPdfReaderBuilder,
  });

  final bool pro;
  final DesktopRepository repository;
  final WidgetBuilder? proPdfReaderBuilder;

  @override
  State<PickLogicDesktopApp> createState() => _PickLogicDesktopAppState();
}

final class _PickLogicDesktopAppState extends State<PickLogicDesktopApp> {
  Locale _locale = const Locale('zh');

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: widget.pro ? 'PickLogic Pro' : 'PickLogic Desktop',
    theme: PickLogicTokens.lightTheme(),
    darkTheme: PickLogicTokens.darkTheme(),
    locale: _locale,
    supportedLocales: PickLogicLocalizations.supportedLocales,
    localizationsDelegates: const [
      PickLogicLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: DesktopShell(
      pro: widget.pro,
      repository: widget.repository,
      proPdfReaderBuilder: widget.proPdfReaderBuilder,
      locale: _locale,
      onLocaleChanged: (locale) => setState(() => _locale = locale),
    ),
  );
}

final class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.pro,
    required this.repository,
    this.proPdfReaderBuilder,
    required this.locale,
    required this.onLocaleChanged,
  });

  final bool pro;
  final DesktopRepository repository;
  final WidgetBuilder? proPdfReaderBuilder;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

final class _DesktopShellState extends State<DesktopShell> {
  final List<FileRecord> _records = syntheticDesktopRecords();
  final TextEditingController _searchController = TextEditingController();
  List<FileRecord>? _searchResults;
  FileRecord? _selected;
  String _section = 'home';
  String _categoryFilter = 'all';
  bool _scanning = false;
  int _scannedCount = 0;
  String _rootLabel = 'Synthetic fixtures';
  int _searchGeneration = 0;
  int _duplicateGeneration = 0;
  bool _duplicatesRunning = false;
  bool _duplicatesReady = false;
  int _duplicateHashedCount = 0;
  int _duplicateFailedCount = 0;
  List<List<FileRecord>> _duplicateGroups = const <List<FileRecord>>[];

  @override
  void initState() {
    super.initState();
    _selected = _records.first;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanSelectedDirectory() async {
    if (_scanning) return;
    var firstBatch = true;
    _searchController.clear();
    _searchGeneration += 1;
    _duplicateGeneration += 1;
    setState(() {
      _searchResults = null;
      _scanning = true;
      _duplicatesReady = false;
      _duplicatesRunning = false;
      _duplicateGroups = const <List<FileRecord>>[];
    });
    try {
      await for (final progress in widget.repository.chooseAndScan()) {
        if (!mounted) return;
        setState(() {
          if (firstBatch) {
            _records.clear();
            _selected = null;
            firstBatch = false;
          }
          final removedIds = progress.removedIds.toSet();
          final recordsById = <String, FileRecord>{
            for (final record in _records)
              if (!removedIds.contains(record.id)) record.id: record,
            for (final record in progress.records) record.id: record,
          };
          _records
            ..clear()
            ..addAll(recordsById.values);
          _selected ??= _records.firstOrNull;
          _scannedCount = progress.scannedCount;
          _rootLabel = progress.rootLabel;
          if (progress.complete) {
            _scanning = false;
          }
        });
        if (progress.complete && _section == 'duplicates') {
          await _findDuplicates();
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('只读扫描已停止；未修改任何文件。')));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _cancelScan() async {
    await widget.repository.cancelScan();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _search(String query) async {
    final generation = ++_searchGeneration;
    if (query.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    setState(() => _searchResults = null);
    List<FileRecord> results;
    try {
      results = await widget.repository.search(query);
    } catch (_) {
      results = const <FileRecord>[];
    }
    if (!mounted || generation != _searchGeneration) return;
    final currentIds = _records.map((record) => record.id).toSet();
    setState(
      () => _searchResults = results
          .where((record) => currentIds.contains(record.id))
          .toList(growable: false),
    );
  }

  Future<void> _findDuplicates() async {
    if (_scanning || _duplicatesRunning) return;
    final generation = ++_duplicateGeneration;
    setState(() {
      _duplicatesRunning = true;
      _duplicatesReady = false;
    });
    try {
      final result = await widget.repository.findExactDuplicates(_records);
      if (!mounted || generation != _duplicateGeneration) return;
      final updatedById = {
        for (final record in result.records) record.id: record,
      };
      setState(() {
        for (var index = 0; index < _records.length; index += 1) {
          _records[index] = updatedById[_records[index].id] ?? _records[index];
        }
        _duplicateGroups = result.groups;
        _duplicateHashedCount = result.hashedCount;
        _duplicateFailedCount = result.failedCount;
        _duplicatesReady = true;
      });
    } catch (_) {
      if (!mounted || generation != _duplicateGeneration) return;
      setState(() {
        _duplicateGroups = const <List<FileRecord>>[];
        _duplicateFailedCount = 1;
        _duplicatesReady = true;
      });
    } finally {
      if (mounted && generation == _duplicateGeneration) {
        setState(() => _duplicatesRunning = false);
      }
    }
  }

  Future<void> _openSelected() async {
    final selected = _selected;
    if (selected == null) return;
    final opened = await widget.repository.open(selected);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Windows 没有可用的打开方式。')));
    }
  }

  Future<void> _revealSelected() async {
    final selected = _selected;
    if (selected == null) return;
    final revealed = await widget.repository.reveal(selected);
    if (!revealed && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法在资源管理器中定位此项目。')));
    }
  }

  void _selectSection(String value) {
    if (widget.pro && proWorkspaceSections.contains(value)) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProWorkspaceRoute(
            section: value,
            pdfReaderBuilder: widget.proPdfReaderBuilder,
          ),
        ),
      );
      return;
    }
    setState(() => _section = value);
    if (value == 'duplicates') {
      _findDuplicates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = PickLogicLocalizations.of(context);
    final query = _searchController.text.toLowerCase();
    var visible = query.isEmpty
        ? _records
        : _searchResults ??
              _records
                  .where(
                    (record) =>
                        record.displayName.toLowerCase().contains(query),
                  )
                  .toList();
    visible = visible
        .where((record) => _matchesCategory(record, _categoryFilter))
        .toList(growable: false);
    if (_section == 'duplicates') {
      final duplicateIds = _duplicateGroups
          .expand((group) => group)
          .map((record) => record.id)
          .toSet();
      visible = visible
          .where((record) => duplicateIds.contains(record.id))
          .toList(growable: false);
    }
    final selected = _selected;
    final insight = selected == null
        ? const InsightRecord(
            summary: 'Select a local item to inspect its evidence.',
            fileType: 'No selection',
            riskLevel: RiskLevel.unknown,
            confidence: 0,
          )
        : const BasicInsightEngine().explainFile(selected);

    return Scaffold(
      body: Column(
        children: [
          const Align(alignment: Alignment.centerLeft, child: SafeModeBanner()),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text('Developer Safe Mode — real files are read-only.'),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 1180;
                return Row(
                  children: [
                    SizedBox(
                      width: compact ? 184 : 220,
                      child: _Navigation(
                        pro: widget.pro,
                        selected: _section,
                        onSelected: _selectSection,
                        locale: widget.locale,
                        onLocaleChanged: widget.onLocaleChanged,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: compact ? 3 : 4,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: _scanning
                                          ? null
                                          : _scanSelectedDirectory,
                                      icon: const Icon(Icons.folder_open),
                                      label: const Text('选择文件夹 · 只读扫描'),
                                    ),
                                    if (_scanning)
                                      OutlinedButton.icon(
                                        onPressed: _cancelScan,
                                        icon: const Icon(
                                          Icons.stop_circle_outlined,
                                        ),
                                        label: const Text('暂停'),
                                      ),
                                    Text('$_rootLabel · $_scannedCount items'),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _CategoryFilters(
                                  selected: _categoryFilter,
                                  onSelected: (value) =>
                                      setState(() => _categoryFilter = value),
                                ),
                                if (_section == 'duplicates') ...[
                                  const SizedBox(height: 12),
                                  _DuplicateStatus(
                                    running: _duplicatesRunning,
                                    ready: _duplicatesReady,
                                    groupCount: _duplicateGroups.length,
                                    fileCount: _duplicateGroups.fold(
                                      0,
                                      (total, group) => total + group.length,
                                    ),
                                    hashedCount: _duplicateHashedCount,
                                    failedCount: _duplicateFailedCount,
                                  ),
                                ],
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _searchController,
                                  onChanged: _search,
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.search),
                                    hintText: strings.text('search'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final record = visible[index];
                                return Card(
                                  key: ValueKey('record-${record.id}'),
                                  color: record.id == _selected?.id
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.secondaryContainer
                                      : null,
                                  child: ListTile(
                                    leading: Icon(
                                      _categoryIcon(record.category),
                                    ),
                                    title: Text(record.displayName),
                                    subtitle: Text(
                                      '${record.category.name} · '
                                      '${record.sizeBytes} bytes',
                                    ),
                                    onTap: () =>
                                        setState(() => _selected = record),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    if (compact)
                      Expanded(
                        flex: 2,
                        child: _CompactDetailPane(
                          record: _selected,
                          section: _section,
                          insight: insight,
                          onOpen: _selected == null ? null : _openSelected,
                          onReveal: _selected == null ? null : _revealSelected,
                        ),
                      )
                    else ...[
                      Expanded(
                        flex: 3,
                        child: _PreviewPane(
                          record: _selected,
                          section: _section,
                          onOpen: _selected == null ? null : _openSelected,
                          onReveal: _selected == null ? null : _revealSelected,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 340,
                        child: InsightPanel(insight: insight),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(VirtualCategory category) => switch (category) {
    VirtualCategory.pdf ||
    VirtualCategory.academicPapers => Icons.picture_as_pdf_outlined,
    VirtualCategory.spreadsheets => Icons.table_chart_outlined,
    VirtualCategory.images => Icons.image_outlined,
    VirtualCategory.archives => Icons.archive_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

final class _CompactDetailPane extends StatelessWidget {
  const _CompactDetailPane({
    required this.record,
    required this.section,
    required this.insight,
    required this.onOpen,
    required this.onReveal,
  });

  final FileRecord? record;
  final String section;
  final InsightRecord insight;
  final VoidCallback? onOpen;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Preview'),
            Tab(text: '知件'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _PreviewPane(
                record: record,
                section: section,
                onOpen: onOpen,
                onReveal: onReveal,
              ),
              InsightPanel(insight: insight),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = <(String, String)>[
      ('all', '全部'),
      ('documents', '文档/PDF'),
      ('spreadsheets', '表格'),
      ('images', '图片'),
      ('media', '音视频'),
      ('archives', '压缩包'),
      ('other', '其他'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in filters)
          ChoiceChip(
            label: Text(filter.$2),
            selected: selected == filter.$1,
            onSelected: (_) => onSelected(filter.$1),
          ),
      ],
    );
  }
}

final class _DuplicateStatus extends StatelessWidget {
  const _DuplicateStatus({
    required this.running,
    required this.ready,
    required this.groupCount,
    required this.fileCount,
    required this.hashedCount,
    required this.failedCount,
  });

  final bool running;
  final bool ready;
  final int groupCount;
  final int fileCount;
  final int hashedCount;
  final int failedCount;

  @override
  Widget build(BuildContext context) {
    if (running) {
      return const Row(
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Expanded(child: Text('正在只读计算 SHA-256 精确重复项…')),
        ],
      );
    }
    if (!ready) {
      return const Text('选择重复项后，将只读计算大小相同文件的 SHA-256。');
    }
    if (groupCount == 0) {
      return Text(
        failedCount == 0
            ? '未发现精确重复项；原文件未更改。'
            : '重复项检查完成，但有 $failedCount 个候选无法读取；原文件未更改。',
      );
    }
    return Text(
      '精确重复项：$groupCount 组 · $fileCount 个文件 · '
      '本次哈希 $hashedCount 个${failedCount == 0 ? '' : ' · 失败 $failedCount 个'}。',
    );
  }
}

final class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.pro,
    required this.selected,
    required this.onSelected,
    required this.locale,
    required this.onLocaleChanged,
  });

  final bool pro;
  final String selected;
  final ValueChanged<String> onSelected;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String, IconData)>[
      ('home', '首页 · Home', Icons.home_outlined),
      ('files', '文件 · Files', Icons.folder_outlined),
      ('search', '搜索 · Search', Icons.search),
      ('duplicates', '重复项 · Duplicates', Icons.copy_all_outlined),
      ('storage', '存储 · Storage', Icons.storage_outlined),
      if (pro) ('literature', '文献 · Literature', Icons.menu_book_outlined),
      if (pro) ('research', '研究 · Research', Icons.science_outlined),
      if (pro) ('system', '系统洞察', Icons.monitor_heart_outlined),
    ];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                pro ? 'PickLogic Pro' : 'PickLogic Desktop',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ...entries.map(
              (entry) => ListTile(
                selected: selected == entry.$1,
                leading: Icon(entry.$3),
                title: Text(entry.$2),
                onTap: () => onSelected(entry.$1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<Locale>(
                segments: const [
                  ButtonSegment(value: Locale('zh'), label: Text('中')),
                  ButtonSegment(value: Locale('en'), label: Text('EN')),
                ],
                selected: {locale},
                onSelectionChanged: (value) => onLocaleChanged(value.single),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.record,
    required this.section,
    required this.onOpen,
    required this.onReveal,
  });

  final FileRecord? record;
  final String section;
  final VoidCallback? onOpen;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Preview', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 24),
      Icon(
        Icons.description_outlined,
        size: 72,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 20),
      Text(record?.displayName ?? 'No selection'),
      const SizedBox(height: 8),
      Text('Section: $section'),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开'),
          ),
          OutlinedButton.icon(
            onPressed: onReveal,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('原位置定位'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('Developer Safe Mode — real files are read-only.'),
      const SizedBox(height: 8),
      const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(onPressed: null, child: Text('移动')),
          OutlinedButton(onPressed: null, child: Text('重命名')),
          OutlinedButton(onPressed: null, child: Text('删除')),
        ],
      ),
      const SizedBox(height: 32),
      const Text('Read-only metadata preview. Original location is unchanged.'),
    ],
  );
}

bool _matchesCategory(FileRecord record, String filter) => switch (filter) {
  'all' => true,
  'documents' => const {
    VirtualCategory.documents,
    VirtualCategory.pdf,
    VirtualCategory.academicPapers,
    VirtualCategory.presentations,
    VirtualCategory.code,
  }.contains(record.category),
  'spreadsheets' => record.category == VirtualCategory.spreadsheets,
  'images' => const {
    VirtualCategory.images,
    VirtualCategory.screenshots,
  }.contains(record.category),
  'media' => const {
    VirtualCategory.videos,
    VirtualCategory.audio,
  }.contains(record.category),
  'archives' => record.category == VirtualCategory.archives,
  'other' => !const {
    VirtualCategory.documents,
    VirtualCategory.pdf,
    VirtualCategory.academicPapers,
    VirtualCategory.presentations,
    VirtualCategory.code,
    VirtualCategory.spreadsheets,
    VirtualCategory.images,
    VirtualCategory.screenshots,
    VirtualCategory.videos,
    VirtualCategory.audio,
    VirtualCategory.archives,
  }.contains(record.category),
  _ => true,
};
