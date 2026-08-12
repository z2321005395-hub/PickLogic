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
  bool _scanning = false;
  int _scannedCount = 0;
  String _rootLabel = 'Synthetic fixtures';
  int _searchGeneration = 0;

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
    setState(() {
      _searchResults = null;
      _scanning = true;
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
          if (progress.complete) _scanning = false;
        });
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
    setState(() => _searchResults = results);
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
  }

  @override
  Widget build(BuildContext context) {
    final strings = PickLogicLocalizations.of(context);
    final query = _searchController.text.toLowerCase();
    final visible = query.isEmpty
        ? _records
        : _searchResults ??
              _records
                  .where(
                    (record) =>
                        record.displayName.toLowerCase().contains(query),
                  )
                  .toList();
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
                                      label: const Text('选择目录 · 只读扫描'),
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
      const SizedBox(height: 32),
      const Text('Read-only metadata preview. Original location is unchanged.'),
    ],
  );
}
