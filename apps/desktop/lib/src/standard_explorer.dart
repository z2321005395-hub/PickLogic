import 'dart:io';

import 'package:flutter/material.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

import 'desktop_repository.dart';
import 'file_preview.dart';
import 'pro_workspace.dart';

final class StandardExplorer extends StatefulWidget {
  const StandardExplorer({
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
  State<StandardExplorer> createState() => _StandardExplorerState();
}

enum _DetailMode { hidden, context }

enum _WorkspaceViewMode { list, grid, dual }

enum _AutoIndexStatus { off, running, complete, failed }

enum _WorkspaceSection {
  home,
  files,
  search,
  duplicates,
  storage,
  literature,
  research,
  system,
}

final class _StandardExplorerState extends State<StandardExplorer> {
  final _panes = [_PaneState(), _PaneState()];
  final _searchController = TextEditingController();
  List<WindowsBrowseRoot> _roots = const [];
  final List<WindowsBrowseRoot> _extraRoots = [];
  int _activePane = 0;
  bool _rootsLoading = true;
  String? _rootsError;
  _AutoIndexStatus _autoIndexStatus = _AutoIndexStatus.off;
  _DetailMode _detailMode = _DetailMode.hidden;
  _WorkspaceViewMode _viewMode = _WorkspaceViewMode.dual;
  _WorkspaceSection _section = _WorkspaceSection.home;
  WindowsStorageSummary? _storageSummary;
  bool _storageLoading = false;
  bool _storageError = false;
  final List<BrowseEntry> _recentEntries = <BrowseEntry>[];

  @override
  void initState() {
    super.initState();
    _loadRoots();
    _loadStorageSummary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRoots() async {
    try {
      final roots = await widget.repository.browseRoots();
      if (!mounted) return;
      setState(() {
        _roots = roots;
        _rootsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rootsLoading = false;
        _rootsError = 'roots';
      });
    }
  }

  void _activatePane(int index) {
    if (_activePane == index) return;
    setState(() {
      _activePane = index;
      _searchController.text = _panes[index].query;
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
      _detailMode = _DetailMode.hidden;
    });
  }

  Future<void> _navigate(int paneIndex, String path) async {
    final pane = _panes[paneIndex];
    setState(() {
      pane.loading = true;
      pane.error = false;
      pane.selected = null;
      _detailMode = _DetailMode.hidden;
    });
    try {
      final snapshot = await widget.repository.browseDirectory(path);
      if (!mounted) return;
      setState(() {
        pane.snapshot = snapshot;
        pane.loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        pane.loading = false;
        pane.error = true;
      });
    }
  }

  void _goHome(int paneIndex) {
    setState(() {
      final pane = _panes[paneIndex];
      pane.snapshot = null;
      pane.selected = null;
      pane.error = false;
      pane.loading = false;
      _detailMode = _DetailMode.hidden;
    });
  }

  void _selectEntry(int paneIndex, BrowseEntry entry) {
    setState(() {
      _activePane = paneIndex;
      _panes[paneIndex].selected = entry;
      _searchController.text = _panes[paneIndex].query;
      _detailMode = _DetailMode.context;
      _recentEntries.removeWhere((recent) => recent.id == entry.id);
      _recentEntries.insert(0, entry);
      if (_recentEntries.length > 12) _recentEntries.removeLast();
    });
  }

  Future<void> _chooseFolder() async {
    final selected = await widget.repository.chooseBrowseFolder(
      chinese: widget.locale.languageCode == 'zh',
    );
    if (!mounted || selected == null) return;
    if (!_extraRoots.any((root) => root.path == selected)) {
      setState(() {
        _extraRoots.add(
          WindowsBrowseRoot(
            id: 'folder:$selected',
            path: selected,
            kind: WindowsBrowseRootKind.folder,
          ),
        );
      });
    }
    await _navigate(_activePane, selected);
  }

  Future<void> _openEntry(int paneIndex, BrowseEntry entry) async {
    _activatePane(paneIndex);
    if (entry.isDirectory) {
      await _navigate(paneIndex, entry.path);
      return;
    }
    final opened = await widget.repository.openBrowseEntry(entry);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_ExplorerStrings.of(context).openFailed)),
    );
  }

  Future<void> _revealSelected() async {
    final selected = _panes[_activePane].selected;
    if (selected == null) return;
    final revealed = await widget.repository.revealBrowseEntry(selected);
    if (!mounted || revealed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_ExplorerStrings.of(context).revealFailed)),
    );
  }

  Future<void> _openSelected() async {
    final selected = _panes[_activePane].selected;
    if (selected != null) await _openEntry(_activePane, selected);
  }

  void _openWorkspace({_WorkspaceViewMode? mode}) {
    setState(() {
      _section = _WorkspaceSection.files;
      if (mode != null) _viewMode = mode;
    });
  }

  void _openRoot(WindowsBrowseRoot root) {
    _openWorkspace();
    _navigate(_activePane, root.path);
  }

  void _openCategory(VirtualCategory category) {
    setState(() {
      _section = _WorkspaceSection.files;
      _panes[_activePane].categoryFilter = category;
    });
  }

  Future<void> _searchIndex() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final paneIndex = _activePane;
    final pane = _panes[paneIndex];
    setState(() {
      _section = _WorkspaceSection.search;
      pane.loading = true;
      pane.error = false;
      pane.selected = null;
      _detailMode = _DetailMode.hidden;
    });
    try {
      final records = await widget.repository.search(query);
      if (!mounted || paneIndex != _activePane) return;
      final strings = _ExplorerStrings.of(context);
      setState(() {
        pane.query = '';
        pane.loading = false;
        pane.snapshot = DirectorySnapshot(
          path: 'search:$query',
          parentPath: null,
          crumbs: [
            BrowseCrumb(
              label: strings.searchResults(query),
              path: 'search:$query',
            ),
          ],
          entries: records.map(_browseEntryForRecord).toList(growable: false),
          truncated: false,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        pane.loading = false;
        pane.error = true;
      });
    }
  }

  void _selectSection(int index) {
    final sections = _navigationSections(widget.pro);
    final section = sections[index];
    if (section == _WorkspaceSection.literature ||
        section == _WorkspaceSection.research ||
        section == _WorkspaceSection.system) {
      _openProSection(section.name);
      return;
    }
    setState(() {
      _section = section;
      _detailMode = _DetailMode.hidden;
    });
    switch (section) {
      case _WorkspaceSection.duplicates:
        _findExactDuplicates();
      case _WorkspaceSection.storage:
        _loadStorageSummary();
      case _WorkspaceSection.home ||
          _WorkspaceSection.files ||
          _WorkspaceSection.search:
        break;
      case _WorkspaceSection.literature ||
          _WorkspaceSection.research ||
          _WorkspaceSection.system:
        break;
    }
  }

  Future<void> _findExactDuplicates() async {
    final paneIndex = _activePane;
    final pane = _panes[paneIndex];
    final source =
        pane.snapshot?.entries
            .where((entry) => !entry.isDirectory && entry.record != null)
            .map((entry) => entry.record!)
            .toList(growable: false) ??
        const <FileRecord>[];
    if (source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_ExplorerStrings.of(context).duplicatesNeedFiles),
        ),
      );
      return;
    }
    setState(() {
      pane.loading = true;
      pane.error = false;
      pane.selected = null;
      _detailMode = _DetailMode.hidden;
    });
    try {
      final result = await widget.repository.findExactDuplicates(source);
      if (!mounted) return;
      final records = result.groups.expand((group) => group).toList();
      final strings = _ExplorerStrings.of(context);
      setState(() {
        pane.query = '';
        pane.loading = false;
        pane.snapshot = DirectorySnapshot(
          path: 'duplicates:$paneIndex',
          parentPath: null,
          crumbs: [
            BrowseCrumb(
              label: strings.duplicateResults(records.length),
              path: 'duplicates:$paneIndex',
            ),
          ],
          entries: records.map(_browseEntryForRecord).toList(growable: false),
          truncated: false,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        pane.loading = false;
        pane.error = true;
      });
    }
  }

  Future<void> _loadStorageSummary() async {
    setState(() {
      _storageLoading = true;
      _storageError = false;
      _detailMode = _DetailMode.hidden;
    });
    try {
      final summary = await widget.repository.systemDriveSummary();
      if (!mounted) return;
      setState(() {
        _storageSummary = summary;
        _storageLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _storageLoading = false;
        _storageError = true;
      });
    }
  }

  Future<void> _requestAutoIndex(bool enabled) async {
    if (!enabled) {
      setState(() => _autoIndexStatus = _AutoIndexStatus.off);
      return;
    }
    final strings = _ExplorerStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.autoIndexTitle),
        content: Text(strings.autoIndexDisclosure),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('confirm-auto-index'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.enable),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _autoIndexStatus = _AutoIndexStatus.running);
    try {
      await for (final _ in widget.repository.indexCommonFolders()) {}
      if (!mounted) return;
      setState(() => _autoIndexStatus = _AutoIndexStatus.complete);
    } catch (_) {
      if (!mounted) return;
      setState(() => _autoIndexStatus = _AutoIndexStatus.failed);
    }
  }

  void _openProSection(String section) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProWorkspaceRoute(
          section: section,
          pdfReaderBuilder: widget.proPdfReaderBuilder,
        ),
      ),
    );
  }

  void _changeLocale(Locale locale) {
    ScaffoldMessenger.of(context).clearSnackBars();
    widget.onLocaleChanged(locale);
  }

  @override
  Widget build(BuildContext context) {
    final strings = _ExplorerStrings.of(context);
    final selected = _panes[_activePane].selected;
    final navigationSections = _navigationSections(widget.pro);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            key: const Key('primary-navigation'),
            selectedIndex: navigationSections.indexOf(_section).clamp(0, 4),
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: _selectSection,
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: Text(strings.homeNav, key: const Key('nav-home')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.folder_copy_outlined),
                selectedIcon: const Icon(Icons.folder_copy),
                label: Text(strings.files, key: const Key('nav-files')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.manage_search_outlined),
                selectedIcon: const Icon(Icons.manage_search),
                label: Text(strings.search, key: const Key('nav-search')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.file_copy_outlined),
                selectedIcon: const Icon(Icons.file_copy),
                label: Text(
                  strings.duplicates,
                  key: const Key('nav-duplicates'),
                ),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.storage_outlined),
                selectedIcon: const Icon(Icons.storage),
                label: Text(strings.storage, key: const Key('nav-storage')),
              ),
              if (widget.pro) ...[
                NavigationRailDestination(
                  icon: const Icon(Icons.menu_book_outlined),
                  selectedIcon: const Icon(Icons.menu_book),
                  label: Text(strings.literature),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.science_outlined),
                  selectedIcon: const Icon(Icons.science),
                  label: Text(strings.research),
                ),
                NavigationRailDestination(
                  icon: const Icon(Icons.monitor_heart_outlined),
                  selectedIcon: const Icon(Icons.monitor_heart),
                  label: Text(strings.systemInsight),
                ),
              ],
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  strings: strings,
                  locale: widget.locale,
                  searchController: _searchController,
                  onLocaleChanged: _changeLocale,
                  onChooseFolder: _chooseFolder,
                  onSearchChanged: (value) => setState(() {
                    _panes[_activePane].query = value;
                  }),
                  onIndexSearch: _searchIndex,
                  canShowDetails: selected != null,
                  detailMode: _detailMode,
                  onDetailModeChanged: (mode) => setState(() {
                    _detailMode = _detailMode == mode
                        ? _DetailMode.hidden
                        : mode;
                  }),
                  activePane: _activePane,
                  viewMode: _viewMode,
                  onViewModeChanged: (mode) => setState(() => _viewMode = mode),
                ),
                _StatusStrip(
                  strings: strings,
                  status: _autoIndexStatus,
                  onChanged: _requestAutoIndex,
                ),
                Expanded(
                  child: _section == _WorkspaceSection.home
                      ? _DesktopHome(
                          strings: strings,
                          roots: [..._roots, ..._extraRoots],
                          rootsLoading: _rootsLoading,
                          storage: _storageSummary,
                          recent: _recentEntries,
                          onSearch: _searchIndex,
                          onOpenRoot: _openRoot,
                          onOpenCategory: _openCategory,
                          onOpenRecent: (entry) {
                            _openWorkspace();
                            _selectEntry(_activePane, entry);
                          },
                          onOpenDualPane: () =>
                              _openWorkspace(mode: _WorkspaceViewMode.dual),
                        )
                      : _section == _WorkspaceSection.storage
                      ? _StorageView(
                          strings: strings,
                          summary: _storageSummary,
                          loading: _storageLoading,
                          error: _storageError,
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _BrowserPane(
                                index: 0,
                                active: _activePane == 0,
                                state: _panes[0],
                                roots: [..._roots, ..._extraRoots],
                                rootsLoading: _rootsLoading,
                                rootsError: _rootsError != null,
                                strings: strings,
                                onHome: () {
                                  _activatePane(0);
                                  _goHome(0);
                                },
                                onNavigate: (path) {
                                  _activatePane(0);
                                  _navigate(0, path);
                                },
                                onSelect: (entry) => _selectEntry(0, entry),
                                onOpen: (entry) => _openEntry(0, entry),
                                viewMode: _viewMode,
                              ),
                            ),
                            if (_viewMode == _WorkspaceViewMode.dual) ...[
                              const VerticalDivider(width: 1),
                              Expanded(
                                child: _BrowserPane(
                                  index: 1,
                                  active: _activePane == 1,
                                  state: _panes[1],
                                  roots: [..._roots, ..._extraRoots],
                                  rootsLoading: _rootsLoading,
                                  rootsError: _rootsError != null,
                                  strings: strings,
                                  onHome: () {
                                    _activatePane(1);
                                    _goHome(1);
                                  },
                                  onNavigate: (path) {
                                    _activatePane(1);
                                    _navigate(1, path);
                                  },
                                  onSelect: (entry) => _selectEntry(1, entry),
                                  onOpen: (entry) => _openEntry(1, entry),
                                  viewMode: _WorkspaceViewMode.list,
                                ),
                              ),
                            ],
                            if (_detailMode != _DetailMode.hidden) ...[
                              const VerticalDivider(width: 1),
                              SizedBox(
                                width: 340,
                                child: _DetailPane(
                                  mode: _detailMode,
                                  entry: selected,
                                  strings: strings,
                                  onClose: () => setState(
                                    () => _detailMode = _DetailMode.hidden,
                                  ),
                                  onReveal: selected == null
                                      ? null
                                      : _revealSelected,
                                  onOpen: selected == null
                                      ? null
                                      : _openSelected,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BrowseEntry _browseEntryForRecord(FileRecord record) => BrowseEntry(
  id: record.id,
  path: record.locator.value,
  name: record.displayName,
  isDirectory: false,
  sizeBytes: record.sizeBytes,
  modifiedAt: record.modifiedAt,
  category: record.category,
  record: record,
);

final class _PaneState {
  DirectorySnapshot? snapshot;
  BrowseEntry? selected;
  String query = '';
  bool loading = false;
  bool error = false;
  VirtualCategory? categoryFilter;
}

List<_WorkspaceSection> _navigationSections(bool pro) => [
  _WorkspaceSection.home,
  _WorkspaceSection.files,
  _WorkspaceSection.search,
  _WorkspaceSection.duplicates,
  _WorkspaceSection.storage,
  if (pro) ...[
    _WorkspaceSection.literature,
    _WorkspaceSection.research,
    _WorkspaceSection.system,
  ],
];

final class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.strings,
    required this.locale,
    required this.searchController,
    required this.onLocaleChanged,
    required this.onChooseFolder,
    required this.onSearchChanged,
    required this.onIndexSearch,
    required this.canShowDetails,
    required this.detailMode,
    required this.onDetailModeChanged,
    required this.activePane,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final _ExplorerStrings strings;
  final Locale locale;
  final TextEditingController searchController;
  final ValueChanged<Locale> onLocaleChanged;
  final VoidCallback onChooseFolder;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onIndexSearch;
  final bool canShowDetails;
  final _DetailMode detailMode;
  final ValueChanged<_DetailMode> onDetailModeChanged;
  final int activePane;
  final _WorkspaceViewMode viewMode;
  final ValueChanged<_WorkspaceViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.all(PickLogicTokens.spaceMd),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              strings.productName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: PickLogicTokens.spaceLg),
            FilledButton.tonalIcon(
              key: const Key('choose-folder'),
              onPressed: onChooseFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(strings.addFolder),
            ),
            const SizedBox(width: PickLogicTokens.spaceMd),
            SizedBox(
              width: 360,
              child: TextField(
                key: const Key('active-pane-search'),
                controller: searchController,
                onChanged: onSearchChanged,
                onSubmitted: (_) => onIndexSearch(),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: strings.searchInPane(activePane),
                ),
              ),
            ),
            const SizedBox(width: PickLogicTokens.spaceSm),
            IconButton.filledTonal(
              key: const Key('search-index'),
              onPressed: onIndexSearch,
              tooltip: strings.searchIndex,
              icon: const Icon(Icons.manage_search),
            ),
            const SizedBox(width: PickLogicTokens.spaceMd),
            SegmentedButton<_WorkspaceViewMode>(
              key: const Key('workspace-view-mode'),
              segments: [
                ButtonSegment(
                  value: _WorkspaceViewMode.list,
                  icon: const Icon(Icons.view_list_outlined),
                  tooltip: strings.listView,
                ),
                ButtonSegment(
                  value: _WorkspaceViewMode.grid,
                  icon: const Icon(Icons.grid_view_outlined),
                  tooltip: strings.gridView,
                ),
                ButtonSegment(
                  value: _WorkspaceViewMode.dual,
                  icon: const Icon(Icons.vertical_split_outlined),
                  tooltip: strings.dualPane,
                ),
              ],
              selected: {viewMode},
              onSelectionChanged: (value) => onViewModeChanged(value.first),
              showSelectedIcon: false,
            ),
            const SizedBox(width: PickLogicTokens.spaceMd),
            IconButton.filledTonal(
              key: const Key('insight-tool'),
              onPressed: canShowDetails
                  ? () => onDetailModeChanged(_DetailMode.context)
                  : null,
              tooltip: strings.contextPanel,
              isSelected: detailMode == _DetailMode.context,
              icon: const Icon(Icons.view_sidebar_outlined),
            ),
            const SizedBox(width: PickLogicTokens.spaceSm),
            IconButton(
              key: const Key('toggle-language'),
              onPressed: () => onLocaleChanged(
                locale.languageCode == 'zh'
                    ? const Locale('en')
                    : const Locale('zh'),
              ),
              tooltip: strings.switchLanguage,
              icon: const Icon(Icons.language),
            ),
            const SizedBox(width: PickLogicTokens.spaceXs),
            PopupMenuButton<String>(
              key: const Key('safe-file-actions'),
              tooltip: strings.moreActions,
              icon: const Icon(Icons.more_horiz),
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: ListTile(
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: Text(strings.newFolder),
                    subtitle: Text(strings.safeModeReadOnly),
                  ),
                ),
                PopupMenuItem<String>(
                  key: const Key('move-to-target'),
                  enabled: false,
                  child: ListTile(
                    leading: const Icon(Icons.drive_file_move_outline),
                    title: Text(strings.moveToTarget(activePane)),
                    subtitle: Text(strings.safeModeReadOnly),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

final class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.strings,
    required this.status,
    required this.onChanged,
  });

  final _ExplorerStrings strings;
  final _AutoIndexStatus status;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PickLogicTokens.spaceMd,
        vertical: PickLogicTokens.spaceXs,
      ),
      child: Row(
        children: [
          const SafeModeBanner(key: Key('standard-safe-mode')),
          const SizedBox(width: PickLogicTokens.spaceMd),
          Icon(
            status == _AutoIndexStatus.running
                ? Icons.sync
                : status == _AutoIndexStatus.complete
                ? Icons.check_circle_outline
                : Icons.manage_search_outlined,
            size: PickLogicTokens.iconSmall,
          ),
          const SizedBox(width: PickLogicTokens.spaceSm),
          Expanded(
            child: Text(
              switch (status) {
                _AutoIndexStatus.off => strings.autoIndexOff,
                _AutoIndexStatus.running => strings.autoIndexRunning,
                _AutoIndexStatus.complete => strings.autoIndexComplete,
                _AutoIndexStatus.failed => strings.autoIndexFailed,
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Switch(
            key: const Key('auto-index-switch'),
            value:
                status == _AutoIndexStatus.running ||
                status == _AutoIndexStatus.complete,
            onChanged: status == _AutoIndexStatus.running ? null : onChanged,
          ),
        ],
      ),
    ),
  );
}

final class _BrowserPane extends StatelessWidget {
  const _BrowserPane({
    required this.index,
    required this.active,
    required this.state,
    required this.roots,
    required this.rootsLoading,
    required this.rootsError,
    required this.strings,
    required this.onHome,
    required this.onNavigate,
    required this.onSelect,
    required this.onOpen,
    required this.viewMode,
  });

  final int index;
  final bool active;
  final _PaneState state;
  final List<WindowsBrowseRoot> roots;
  final bool rootsLoading;
  final bool rootsError;
  final _ExplorerStrings strings;
  final VoidCallback onHome;
  final ValueChanged<String> onNavigate;
  final ValueChanged<BrowseEntry> onSelect;
  final ValueChanged<BrowseEntry> onOpen;
  final _WorkspaceViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot;
    final entries =
        snapshot?.entries
            .where(
              (entry) =>
                  entry.name.toLowerCase().contains(
                    state.query.trim().toLowerCase(),
                  ) &&
                  (state.categoryFilter == null ||
                      entry.category == state.categoryFilter ||
                      entry.isDirectory),
            )
            .toList(growable: false) ??
        const <BrowseEntry>[];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: active
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          _PaneHeader(
            index: index,
            active: active,
            snapshot: snapshot,
            strings: strings,
            onHome: onHome,
            onNavigate: onNavigate,
          ),
          const Divider(height: 1),
          Expanded(
            child: state.loading || (snapshot == null && rootsLoading)
                ? const Center(child: CircularProgressIndicator())
                : state.error || (snapshot == null && rootsError)
                ? Center(child: Text(strings.folderUnavailable))
                : snapshot == null
                ? _RootList(
                    paneIndex: index,
                    roots: roots,
                    strings: strings,
                    onNavigate: onNavigate,
                  )
                : _EntryList(
                    paneIndex: index,
                    entries: entries,
                    selected: state.selected,
                    truncated: snapshot.truncated,
                    strings: strings,
                    onSelect: onSelect,
                    onOpen: onOpen,
                    grid: viewMode == _WorkspaceViewMode.grid,
                  ),
          ),
        ],
      ),
    );
  }
}

final class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.index,
    required this.active,
    required this.snapshot,
    required this.strings,
    required this.onHome,
    required this.onNavigate,
  });

  final int index;
  final bool active;
  final DirectorySnapshot? snapshot;
  final _ExplorerStrings strings;
  final VoidCallback onHome;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: PickLogicTokens.spaceSm,
      vertical: PickLogicTokens.spaceXs,
    ),
    child: Row(
      children: [
        Tooltip(
          message: strings.home,
          child: IconButton(
            key: ValueKey('pane-$index-home'),
            onPressed: onHome,
            icon: const Icon(Icons.home_outlined),
          ),
        ),
        Tooltip(
          message: strings.up,
          child: IconButton(
            key: ValueKey('pane-$index-up'),
            onPressed: snapshot?.parentPath == null
                ? null
                : () => onNavigate(snapshot!.parentPath!),
            icon: const Icon(Icons.arrow_upward),
          ),
        ),
        const SizedBox(width: PickLogicTokens.spaceSm),
        Text(
          strings.paneName(index),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: active ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        const SizedBox(width: PickLogicTokens.spaceMd),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: snapshot == null
                  ? [Text(strings.locations)]
                  : [
                      for (final crumb in snapshot!.crumbs)
                        TextButton(
                          key: ValueKey('pane-$index-crumb-${crumb.path}'),
                          onPressed:
                              crumb.path.startsWith('search:') ||
                                  crumb.path.startsWith('duplicates:')
                              ? null
                              : () => onNavigate(crumb.path),
                          child: Text(
                            crumb.path.startsWith('search:')
                                ? strings.searchResults(
                                    crumb.path.substring('search:'.length),
                                  )
                                : crumb.path.startsWith('duplicates:')
                                ? strings.duplicateResults(
                                    snapshot!.entries.length,
                                  )
                                : crumb.label,
                          ),
                        ),
                    ],
            ),
          ),
        ),
      ],
    ),
  );
}

final class _RootList extends StatelessWidget {
  const _RootList({
    required this.paneIndex,
    required this.roots,
    required this.strings,
    required this.onNavigate,
  });

  final int paneIndex;
  final List<WindowsBrowseRoot> roots;
  final _ExplorerStrings strings;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(PickLogicTokens.spaceSm),
    itemCount: roots.length,
    separatorBuilder: (_, _) => const SizedBox(height: PickLogicTokens.spaceXs),
    itemBuilder: (context, rootIndex) {
      final root = roots[rootIndex];
      return InkWell(
        key: ValueKey('pane-$paneIndex-root-${root.id}'),
        onDoubleTap: () => onNavigate(root.path),
        child: ListTile(
          leading: Icon(
            root.kind == WindowsBrowseRootKind.drive
                ? Icons.storage_outlined
                : Icons.folder_outlined,
          ),
          title: Text(strings.rootLabel(root)),
          subtitle: Text(
            root.kind == WindowsBrowseRootKind.drive
                ? strings.localDisk
                : strings.commonFolder,
          ),
        ),
      );
    },
  );
}

final class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.paneIndex,
    required this.entries,
    required this.selected,
    required this.truncated,
    required this.strings,
    required this.onSelect,
    required this.onOpen,
    required this.grid,
  });

  final int paneIndex;
  final List<BrowseEntry> entries;
  final BrowseEntry? selected;
  final bool truncated;
  final _ExplorerStrings strings;
  final ValueChanged<BrowseEntry> onSelect;
  final ValueChanged<BrowseEntry> onOpen;
  final bool grid;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (truncated)
        MaterialBanner(
          content: Text(strings.listTruncated),
          actions: const [SizedBox.shrink()],
        ),
      Expanded(
        child: entries.isEmpty
            ? Center(child: Text(strings.emptyFolder))
            : grid
            ? GridView.builder(
                padding: const EdgeInsets.all(PickLogicTokens.spaceSm),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisExtent: 150,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: entries.length,
                itemBuilder: (context, entryIndex) {
                  final entry = entries[entryIndex];
                  return InkWell(
                    key: ValueKey('pane-$paneIndex-entry-${entry.id}'),
                    borderRadius: BorderRadius.circular(
                      PickLogicTokens.radiusMedium,
                    ),
                    onTap: () => onSelect(entry),
                    onDoubleTap: () => onOpen(entry),
                    child: Card(
                      color: selected?.id == entry.id
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Expanded(child: _DesktopEntryVisual(entry: entry)),
                            const SizedBox(height: 6),
                            Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              entry.isDirectory
                                  ? strings.folder
                                  : strings.compactMetadata(entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )
            : ListView.separated(
                padding: const EdgeInsets.all(PickLogicTokens.spaceSm),
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: PickLogicTokens.spaceXs),
                itemBuilder: (context, entryIndex) {
                  final entry = entries[entryIndex];
                  return InkWell(
                    key: ValueKey('pane-$paneIndex-entry-${entry.id}'),
                    onTap: () => onSelect(entry),
                    onDoubleTap: () => onOpen(entry),
                    child: ListTile(
                      selected: selected?.id == entry.id,
                      leading: SizedBox.square(
                        dimension: 46,
                        child: _DesktopEntryVisual(entry: entry),
                      ),
                      title: Text(entry.name, maxLines: 1),
                      subtitle: Text(
                        entry.isDirectory
                            ? strings.folder
                            : '${strings.metadataSummary(entry)} · '
                                  '${entry.modifiedAt == null ? strings.unknown : strings.date(entry.modifiedAt!)}',
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

final class _DesktopEntryVisual extends StatelessWidget {
  const _DesktopEntryVisual({required this.entry});

  final BrowseEntry entry;

  @override
  Widget build(BuildContext context) {
    if (!entry.isDirectory &&
        (entry.category == VirtualCategory.images ||
            entry.category == VirtualCategory.screenshots)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(PickLogicTokens.radiusSmall),
        child: Image.file(
          File(entry.path),
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, _, _) =>
              PickLogicIcon(PickLogicVisualIcon.image, size: 42),
        ),
      );
    }
    return Center(
      child: PickLogicIcon(
        _visualIconForEntry(entry),
        size: entry.isDirectory ? 48 : 42,
      ),
    );
  }
}

PickLogicVisualIcon _visualIconForEntry(BrowseEntry entry) {
  if (entry.isDirectory) return PickLogicVisualIcon.folder;
  return switch (entry.category) {
    VirtualCategory.pdf ||
    VirtualCategory.academicPapers => PickLogicVisualIcon.pdf,
    VirtualCategory.images ||
    VirtualCategory.screenshots => PickLogicVisualIcon.image,
    VirtualCategory.videos => PickLogicVisualIcon.video,
    VirtualCategory.audio => PickLogicVisualIcon.audio,
    VirtualCategory.archives => PickLogicVisualIcon.archive,
    VirtualCategory.installers => PickLogicVisualIcon.application,
    _ => PickLogicVisualIcon.document,
  };
}

final class _DesktopHome extends StatelessWidget {
  const _DesktopHome({
    required this.strings,
    required this.roots,
    required this.rootsLoading,
    required this.storage,
    required this.recent,
    required this.onSearch,
    required this.onOpenRoot,
    required this.onOpenCategory,
    required this.onOpenRecent,
    required this.onOpenDualPane,
  });

  final _ExplorerStrings strings;
  final List<WindowsBrowseRoot> roots;
  final bool rootsLoading;
  final WindowsStorageSummary? storage;
  final List<BrowseEntry> recent;
  final VoidCallback onSearch;
  final ValueChanged<WindowsBrowseRoot> onOpenRoot;
  final ValueChanged<VirtualCategory> onOpenCategory;
  final ValueChanged<BrowseEntry> onOpenRecent;
  final VoidCallback onOpenDualPane;

  @override
  Widget build(BuildContext context) {
    final categories =
        <({PickLogicVisualIcon icon, VirtualCategory category, String label})>[
          (
            icon: PickLogicVisualIcon.image,
            category: VirtualCategory.images,
            label: strings.category(VirtualCategory.images),
          ),
          (
            icon: PickLogicVisualIcon.audio,
            category: VirtualCategory.audio,
            label: strings.category(VirtualCategory.audio),
          ),
          (
            icon: PickLogicVisualIcon.video,
            category: VirtualCategory.videos,
            label: strings.category(VirtualCategory.videos),
          ),
          (
            icon: PickLogicVisualIcon.pdf,
            category: VirtualCategory.pdf,
            label: strings.category(VirtualCategory.pdf),
          ),
          (
            icon: PickLogicVisualIcon.archive,
            category: VirtualCategory.archives,
            label: strings.category(VirtualCategory.archives),
          ),
          (
            icon: PickLogicVisualIcon.document,
            category: VirtualCategory.documents,
            label: strings.category(VirtualCategory.documents),
          ),
        ];
    final storageUsed = storage == null
        ? 0
        : storage!.totalBytes - storage!.availableBytes;
    return ListView(
      key: const Key('desktop-home'),
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          strings.homeGreeting,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in categories)
              SizedBox(
                width: 150,
                height: 120,
                child: Card(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      PickLogicTokens.radiusMedium,
                    ),
                    onTap: () => onOpenCategory(item.category),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          PickLogicIcon(item.icon, size: 48),
                          const SizedBox(height: 4),
                          Text(item.label),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _HomePanel(
                title: strings.locations,
                child: rootsLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final root in roots)
                            ActionChip(
                              avatar: PickLogicIcon(
                                root.kind == WindowsBrowseRootKind.drive
                                    ? PickLogicVisualIcon.storage
                                    : PickLogicVisualIcon.folder,
                                size: 26,
                              ),
                              label: Text(strings.rootLabel(root)),
                              onPressed: () => onOpenRoot(root),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _HomePanel(
                title: strings.storageSummary,
                child: storage == null
                    ? Text(strings.storageUnavailable)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(storage!.root),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: storage!.totalBytes == 0
                                ? 0
                                : storageUsed / storage!.totalBytes,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${strings.bytes(storageUsed)} / '
                            '${strings.bytes(storage!.totalBytes)}',
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _HomePanel(
          title: strings.recentFiles,
          trailing: FilledButton.tonalIcon(
            key: const Key('home-dual-pane'),
            onPressed: onOpenDualPane,
            icon: const Icon(Icons.vertical_split_outlined),
            label: Text(strings.dualPane),
          ),
          child: recent.isEmpty
              ? Text(strings.noRecentFiles)
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in recent.take(8))
                      ActionChip(
                        avatar: PickLogicIcon(
                          _visualIconForEntry(entry),
                          size: 26,
                        ),
                        label: Text(entry.name),
                        onPressed: () => onOpenRecent(entry),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

final class _HomePanel extends StatelessWidget {
  const _HomePanel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

final class _StorageView extends StatelessWidget {
  const _StorageView({
    required this.strings,
    required this.summary,
    required this.loading,
    required this.error,
  });

  final _ExplorerStrings strings;
  final WindowsStorageSummary? summary;
  final bool loading;
  final bool error;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error || summary == null) {
      return Center(child: Text(strings.storageUnavailable));
    }
    final current = summary!;
    final usedBytes = (current.totalBytes - current.availableBytes).clamp(
      0,
      current.totalBytes,
    );
    final usedFraction = current.totalBytes == 0
        ? 0.0
        : usedBytes / current.totalBytes;
    return ListView(
      key: const Key('storage-summary-view'),
      padding: const EdgeInsets.all(PickLogicTokens.spaceLg),
      children: [
        Text(
          strings.storageSummary,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: PickLogicTokens.spaceSm),
        Text(strings.storageReadOnly),
        const SizedBox(height: PickLogicTokens.spaceLg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(PickLogicTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.root,
                  key: const Key('storage-root'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: PickLogicTokens.spaceLg),
                LinearProgressIndicator(value: usedFraction),
                const SizedBox(height: PickLogicTokens.spaceLg),
                _Fact(
                  label: strings.storageUsed,
                  value: strings.bytes(usedBytes),
                ),
                _Fact(
                  label: strings.storageAvailable,
                  value: strings.bytes(current.availableBytes),
                ),
                _Fact(
                  label: strings.storageTotal,
                  value: strings.bytes(current.totalBytes),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

final class _DetailPane extends StatelessWidget {
  const _DetailPane({
    required this.mode,
    required this.entry,
    required this.strings,
    required this.onClose,
    required this.onReveal,
    required this.onOpen,
  });

  final _DetailMode mode;
  final BrowseEntry? entry;
  final _ExplorerStrings strings;
  final VoidCallback onClose;
  final VoidCallback? onReveal;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final selected = entry;
    return Material(
      key: const Key('detail-pane'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          ListTile(
            title: Text(strings.contextPanel),
            trailing: IconButton(
              key: const Key('close-detail-pane'),
              onPressed: onClose,
              tooltip: strings.close,
              icon: const Icon(Icons.close),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: selected == null
                ? Center(child: Text(strings.noSelection))
                : Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: DesktopFilePreview(
                          key: ValueKey('preview-${selected.id}'),
                          entry: selected,
                          chinese: strings.chinese,
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        flex: 4,
                        child: ListView(
                          padding: const EdgeInsets.all(
                            PickLogicTokens.spaceMd,
                          ),
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.lightbulb_outline, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  strings.insight,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _Fact(label: strings.name, value: selected.name),
                            _Fact(
                              label: strings.type,
                              value: selected.isDirectory
                                  ? strings.folder
                                  : strings.category(selected.category),
                            ),
                            _Fact(label: strings.path, value: selected.path),
                            _Fact(
                              label: strings.size,
                              value: selected.isDirectory
                                  ? strings.estimatedInPreview
                                  : strings.bytes(selected.sizeBytes),
                            ),
                            _Fact(
                              label: strings.modified,
                              value: selected.modifiedAt == null
                                  ? strings.unknown
                                  : strings.date(selected.modifiedAt!),
                            ),
                            _Fact(
                              label: strings.source,
                              value: strings.localMetadata,
                            ),
                            _Fact(
                              label: strings.hidden,
                              value: selected.record?.isHidden == true
                                  ? strings.yes
                                  : strings.no,
                            ),
                            _Fact(
                              label: strings.systemRelated,
                              value: selected.record?.isSystem == true
                                  ? strings.yes
                                  : strings.noEvidence,
                            ),
                            _Fact(
                              label: strings.duplicates,
                              value:
                                  selected.record?.hashState ==
                                      HashState.complete
                                  ? strings.hashAvailable
                                  : strings.notCalculated,
                            ),
                            _Fact(
                              label: strings.risk,
                              value: selected.record?.isProtected == true
                                  ? strings.protected
                                  : strings.reviewOnly,
                            ),
                            _Fact(
                              label: strings.confidence,
                              value:
                                  selected.category == VirtualCategory.unknown
                                  ? '35%'
                                  : '80%',
                            ),
                            const SizedBox(height: 8),
                            Text(strings.insightExplanation),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                key: const Key('context-open'),
                                onPressed: onOpen,
                                icon: const Icon(Icons.open_in_new),
                                label: Text(strings.open),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.outlined(
                              onPressed: onReveal,
                              tooltip: strings.reveal,
                              icon: const Icon(Icons.folder_open_outlined),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

final class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: PickLogicTokens.spaceSm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 88, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

final class _ExplorerStrings {
  const _ExplorerStrings(this.chinese);

  factory _ExplorerStrings.of(BuildContext context) =>
      _ExplorerStrings(Localizations.localeOf(context).languageCode == 'zh');

  final bool chinese;

  String get productName => chinese ? '拾理' : 'PickLogic';
  String get homeNav => chinese ? '首页' : 'Home';
  String get files => chinese ? '文件' : 'Files';
  String get search => chinese ? '搜索' : 'Search';
  String get duplicates => chinese ? '重复项' : 'Duplicates';
  String get duplicatesNeedFiles => chinese
      ? '请先在活动栏打开包含文件的目录，再检查精确重复项。'
      : 'Open a folder containing files in the active pane before checking exact duplicates.';
  String get storage => chinese ? '存储' : 'Storage';
  String get proTools => chinese ? '专业工具' : 'Professional tools';
  String get literature => chinese ? '文献' : 'Literature';
  String get research => chinese ? '研究' : 'Research';
  String get systemInsight => chinese ? '系统洞察' : 'System Insight';
  String get addFolder => chinese ? '选择文件夹' : 'Choose folder';
  String get moreActions => chinese ? '更多文件操作' : 'More file actions';
  String get safeModeReadOnly =>
      chinese ? '安全模式下不可用' : 'Unavailable in Safe Mode';
  String get searchIndex => chinese ? '在索引中搜索' : 'Search index';
  String get newFolder => chinese ? '新建文件夹' : 'New folder';
  String get preview => chinese ? '预览' : 'Preview';
  String get insight => chinese ? '知件' : 'Insight';
  String get contextPanel => chinese ? '预览与知件' : 'Preview and Insight';
  String get listView => chinese ? '列表' : 'List';
  String get gridView => chinese ? '网格' : 'Grid';
  String get dualPane => chinese ? '双栏工作区' : 'Dual pane';
  String get homeGreeting => chinese
      ? '不用记文件在哪里，只需要知道它是什么。'
      : 'Find files by what they are, not where they are.';
  String get recentFiles => chinese ? '最近选择' : 'Recently selected';
  String get noRecentFiles => chinese
      ? '选择文件后会显示在这里；不会复制或移动原文件。'
      : 'Selected files appear here; originals are not copied or moved.';
  String get home => chinese ? '位置入口' : 'Locations';
  String get up => chinese ? '上一级' : 'Up';
  String get locations => chinese ? '磁盘与常用目录' : 'Drives and common folders';
  String get localDisk => chinese ? '本地磁盘' : 'Local disk';
  String get commonFolder => chinese ? '常用目录' : 'Common folder';
  String get folder => chinese ? '文件夹' : 'Folder';
  String get emptyFolder => chinese ? '此文件夹为空' : 'This folder is empty';
  String get folderUnavailable => chinese ? '无法读取此文件夹' : 'Folder unavailable';
  String get storageSummary => chinese ? '存储概览' : 'Storage summary';
  String get storageReadOnly => chinese
      ? '仅显示系统磁盘容量摘要；不会扫描或修改文件。'
      : 'Shows system-drive capacity only; files are not scanned or changed.';
  String get storageUnavailable =>
      chinese ? '无法读取系统磁盘容量摘要。' : 'System-drive summary is unavailable.';
  String get storageUsed => chinese ? '已用' : 'Used';
  String get storageAvailable => chinese ? '可用' : 'Available';
  String get storageTotal => chinese ? '总容量' : 'Total';
  String get listTruncated => chinese
      ? '为保持响应速度，仅显示前 1000 项。'
      : 'Only the first 1,000 items are shown to keep browsing responsive.';
  String get autoIndexTitle =>
      chinese ? '自动索引常用目录' : 'Automatically index common folders';
  String get autoIndexOff => chinese
      ? '默认关闭；磁盘根仅用于浏览，不会递归扫描。'
      : 'Off by default; drive roots are browsed without recursive scanning.';
  String get autoIndexRunning => chinese
      ? '正在索引桌面、文档和下载目录的本地元数据。'
      : 'Indexing local metadata from Desktop, Documents, and Downloads.';
  String get autoIndexComplete => chinese
      ? '本次常用目录索引已完成；磁盘根未递归扫描。'
      : 'Common-folder indexing completed; drive roots were not recursively scanned.';
  String get autoIndexFailed => chinese
      ? '常用目录索引未完成；未修改任何文件。'
      : 'Common-folder indexing did not complete; no files were changed.';
  String get autoIndexDisclosure => chinese
      ? '来源包括桌面、文档和下载目录。启用后可递归读取文件名、大小、类型和修改时间并写入本地索引；不会修改或上传文件。磁盘根仍不会自动递归扫描。'
      : 'Sources include Desktop, Documents, and Downloads. Enabling allows recursive reads of names, sizes, types, and modified times into the local index; files are not changed or uploaded. Drive roots are still not recursively scanned.';
  String get cancel => chinese ? '取消' : 'Cancel';
  String get enable => chinese ? '启用' : 'Enable';
  String get switchLanguage =>
      chinese ? '切换至英文界面' : 'Switch to Chinese interface';
  String get openFailed =>
      chinese ? '无法打开此文件。' : 'The file could not be opened.';
  String get revealFailed =>
      chinese ? '无法定位此文件。' : 'The file could not be revealed.';
  String get close => chinese ? '关闭' : 'Close';
  String get noSelection => chinese ? '尚未选择文件' : 'No file selected';
  String get readOnlyPreview => chinese
      ? '只读元数据预览；原位置保持不变。'
      : 'Read-only metadata preview; the original location is unchanged.';
  String get open => chinese ? '打开' : 'Open';
  String get reveal => chinese ? '在资源管理器中定位' : 'Reveal in File Explorer';
  String get name => chinese ? '名称' : 'Name';
  String get path => chinese ? '实际路径' : 'Path';
  String get type => chinese ? '类型' : 'Type';
  String get size => chinese ? '大小' : 'Size';
  String get modified => chinese ? '修改时间' : 'Modified';
  String get source => chinese ? '来源' : 'Source';
  String get confidence => chinese ? '置信度' : 'Confidence';
  String get localMetadata => chinese ? '本地文件元数据' : 'Local file metadata';
  String get unknown => chinese ? '无法确认' : 'Unknown';
  String get risk => chinese ? '风险' : 'Risk';
  String get reviewOnly => chinese ? '仅供查看' : 'Review only';
  String get estimatedInPreview =>
      chinese ? '见上方有界估算' : 'See bounded estimate above';
  String get hidden => chinese ? '隐藏属性' : 'Hidden';
  String get systemRelated => chinese ? '系统相关' : 'System-related';
  String get yes => chinese ? '是' : 'Yes';
  String get no => chinese ? '否' : 'No';
  String get noEvidence => chinese ? '无证据' : 'No evidence';
  String get hashAvailable =>
      chinese ? '哈希已计算，需在重复项中核对' : 'Hash available; review in Duplicates';
  String get notCalculated => chinese ? '尚未计算' : 'Not calculated';
  String get protected => chinese ? '受保护' : 'Protected';
  String get insightExplanation => chinese
      ? '事实来自当前文件的本地元数据；分类属于规则推断。无法确认所属软件或系统关系时保持“无法确认”。安全模式禁止真实文件移动、重命名和删除。'
      : 'Facts come from local metadata; category is a rule inference. Ownership and system relationships remain Unknown when evidence is insufficient. Safe Mode blocks real-file move, rename, and delete operations.';

  String date(DateTime value) {
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String paneName(int index) => chinese
      ? (index == 0 ? '左栏' : '右栏')
      : (index == 0 ? 'Left pane' : 'Right pane');
  String searchInPane(int index) => chinese
      ? '在${index == 0 ? '左栏' : '右栏'}中搜索'
      : 'Search the ${index == 0 ? 'left' : 'right'} pane';
  String moveToTarget(int activePane) => chinese
      ? '移动到${activePane == 0 ? '右栏' : '左栏'}'
      : 'Move to ${activePane == 0 ? 'right' : 'left'} pane';
  String bytes(int count) => chinese ? '$count 字节' : '$count bytes';
  String metadataSummary(BrowseEntry entry) => chinese
      ? '${category(entry.category)}，${bytes(entry.sizeBytes)}'
      : '${category(entry.category)}, ${bytes(entry.sizeBytes)}';
  String compactMetadata(BrowseEntry entry) =>
      entry.isDirectory ? folder : bytes(entry.sizeBytes);
  String searchResults(String query) =>
      chinese ? '索引搜索：$query' : 'Index search: $query';
  String duplicateResults(int count) =>
      chinese ? '精确重复项：$count 个文件' : 'Exact duplicates: $count files';

  String rootLabel(WindowsBrowseRoot root) => switch (root.kind) {
    WindowsBrowseRootKind.drive => root.path.replaceAll('\\', '/'),
    WindowsBrowseRootKind.desktop => chinese ? '桌面' : 'Desktop',
    WindowsBrowseRootKind.documents => chinese ? '文档' : 'Documents',
    WindowsBrowseRootKind.downloads => chinese ? '下载' : 'Downloads',
    WindowsBrowseRootKind.folder => _basename(root.path),
  };

  String category(VirtualCategory category) => switch (category) {
    VirtualCategory.documents => chinese ? '文档' : 'Document',
    VirtualCategory.spreadsheets => chinese ? '表格' : 'Spreadsheet',
    VirtualCategory.presentations => chinese ? '演示文稿' : 'Presentation',
    VirtualCategory.pdf ||
    VirtualCategory.academicPapers => chinese ? '便携式文档' : 'PDF document',
    VirtualCategory.images ||
    VirtualCategory.screenshots => chinese ? '图片' : 'Image',
    VirtualCategory.videos => chinese ? '视频' : 'Video',
    VirtualCategory.audio => chinese ? '音频' : 'Audio',
    VirtualCategory.archives => chinese ? '压缩包' : 'Archive',
    VirtualCategory.installers => chinese ? '安装程序' : 'Installer',
    VirtualCategory.code => chinese ? '代码' : 'Code',
    _ => chinese ? '文件' : 'File',
  };
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
