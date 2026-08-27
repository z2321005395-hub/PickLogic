import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_insight_engine/picklogic_insight_engine.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

import 'src/incremental_index_queue.dart';
import 'src/mobile_file_browser.dart';
import 'src/mobile_folder_insight.dart';
import 'src/mobile_internal_viewer.dart';
import 'src/mobile_localizations.dart';
import 'src/mobile_repository.dart';
import 'src/mobile_test_workspace.dart';
import 'src/paged_media.dart';
import 'src/screenshot_grouping.dart';

void main() =>
    runApp(PickLogicMobileApp(repository: AndroidMobileRepository()));

final class PickLogicMobileApp extends StatefulWidget {
  const PickLogicMobileApp({
    super.key,
    this.repository = const SyntheticMobileRepository(),
  });

  final MobileRepository repository;

  @override
  State<PickLogicMobileApp> createState() => _PickLogicMobileAppState();
}

final class _PickLogicMobileAppState extends State<PickLogicMobileApp> {
  Locale _locale = const Locale('zh');

  void _toggleLanguage() {
    setState(() {
      _locale = Locale(_locale.languageCode == 'zh' ? 'en' : 'zh');
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PickLogic Mobile',
    theme: PickLogicTokens.lightTheme(),
    darkTheme: PickLogicTokens.darkTheme(),
    locale: _locale,
    supportedLocales: PickLogicLocalizations.supportedLocales,
    localizationsDelegates: const [
      PickLogicLocalizations.delegate,
      MobileLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MobileShell(
      repository: widget.repository,
      onToggleLanguage: _toggleLanguage,
      languageCode: _locale.languageCode,
    ),
  );
}

final class MobileShell extends StatefulWidget {
  const MobileShell({
    super.key,
    required this.repository,
    required this.onToggleLanguage,
    required this.languageCode,
  });

  final MobileRepository repository;
  final VoidCallback onToggleLanguage;
  final String languageCode;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

final class _MobileShellState extends State<MobileShell> {
  int _index = 0;
  late Future<MobileBootstrapState> _bootstrap;
  final _filesKey = GlobalKey<_FilesPageState>();
  final _recentKey = GlobalKey<_RecentPageState>();
  final _organizeKey = GlobalKey<_OrganizePageState>();

  @override
  void initState() {
    super.initState();
    _bootstrap = widget.repository.loadBootstrap();
  }

  @override
  void didUpdateWidget(covariant MobileShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      unawaited(oldWidget.repository.close());
      _bootstrap = widget.repository.loadBootstrap();
    }
  }

  @override
  void dispose() {
    unawaited(widget.repository.close());
    super.dispose();
  }

  void _retryBootstrap() {
    setState(() {
      _bootstrap = widget.repository.loadBootstrap();
    });
  }

  void _refreshVisible() {
    setState(() => _bootstrap = widget.repository.loadBootstrap());
    switch (_index) {
      case 0:
        _filesKey.currentState?.refresh();
        return;
      case 1:
        _recentKey.currentState?.refresh();
        return;
      case 2:
        _organizeKey.currentState?.refresh();
        return;
    }
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final strings = MobileLocalizations.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.text('settings'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: Text(strings.text('language')),
                  subtitle: Text(
                    widget.languageCode == 'zh' ? '简体中文' : 'English',
                  ),
                  trailing: Text(widget.languageCode == 'zh' ? 'EN' : '中'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onToggleLanguage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(strings.text('safeModeTitle')),
                  subtitle: Text(strings.text('safeModeDetail')),
                ),
                ListTile(
                  key: const Key('mobile-test-workspace-entry'),
                  leading: const Icon(Icons.folder_special_outlined),
                  title: Text(strings.text('testWorkspace')),
                  subtitle: Text(strings.text('testWorkspaceDetail')),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(this.context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) => MobileTestWorkspacePage(
                          repository: widget.repository,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _requestMediaAccess() async {
    final next = widget.repository.requestMediaAccess();
    setState(() {
      _bootstrap = next;
    });
    try {
      await next;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            MobileLocalizations.of(context).text('permissionError'),
          ),
        ),
      );
      setState(() {
        _bootstrap = widget.repository.loadBootstrap();
      });
    }
  }

  Future<void> _chooseDocumentTree() async {
    try {
      final tree = await widget.repository.chooseDocumentTree();
      if (!mounted || tree == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MobileLocalizations.of(context).text('safSaved')),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MobileLocalizations.of(context).text('safDenied')),
        ),
      );
    }
  }

  Future<void> _startSearch() async {
    final record = await showSearch<FileRecord?>(
      context: context,
      delegate: _MobileSearchDelegate(
        widget.repository,
        MobileLocalizations.of(context),
      ),
    );
    if (record != null && mounted) {
      _showMediaItem(context, record, widget.repository);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobileStrings = MobileLocalizations.of(context);
    return FutureBuilder<MobileBootstrapState>(
      future: _bootstrap,
      builder: (context, snapshot) {
        final bootstrap = snapshot.data;
        final canReadMedia = bootstrap?.permissions.canReadImages ?? false;
        final pages = <Widget>[
          _FilesPage(
            key: _filesKey,
            repository: widget.repository,
            active: true,
            onChooseTree: _chooseDocumentTree,
            onSearch: _startSearch,
            bootstrap: bootstrap,
            onOpenScreenshots: () {
              setState(() => _index = 2);
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _organizeKey.currentState?.openScreenshots(),
              );
            },
            onOpenStorage: () {
              setState(() => _index = 2);
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _organizeKey.currentState?.openStorage(),
              );
            },
            onOpenRecent: () => setState(() => _index = 1),
          ),
          _RecentPage(
            key: _recentKey,
            repository: widget.repository,
            active: _index == 1,
          ),
          _OrganizePage(
            key: _organizeKey,
            bootstrap: bootstrap,
            repository: widget.repository,
            active: _index == 2,
            canReadMedia: canReadMedia,
            onRequestAccess: _requestMediaAccess,
            onChooseTree: _chooseDocumentTree,
          ),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.languageCode == 'zh' ? '拾理' : 'PickLogic'),
            actions: [
              IconButton(
                key: const Key('mobile-refresh'),
                tooltip: mobileStrings.text('refresh'),
                icon: const Icon(Icons.refresh),
                onPressed: _refreshVisible,
              ),
              IconButton(
                key: const Key('mobile-settings'),
                tooltip: mobileStrings.text('settings'),
                icon: const Icon(Icons.settings_outlined),
                onPressed: _showSettings,
              ),
            ],
          ),
          body: snapshot.hasError
              ? _BootstrapFailure(onRetry: _retryBootstrap)
              : IndexedStack(index: _index, children: pages),
          bottomNavigationBar: NavigationBar(
            key: const Key('mobile-primary-navigation'),
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: [
              NavigationDestination(
                icon: const Icon(
                  Icons.category_outlined,
                  key: Key('nav-files'),
                ),
                label: mobileStrings.text('categoryHome'),
              ),
              NavigationDestination(
                icon: const Icon(
                  Icons.schedule_outlined,
                  key: Key('nav-recent'),
                ),
                label: mobileStrings.text('recent'),
              ),
              NavigationDestination(
                icon: const Icon(
                  Icons.auto_awesome_mosaic_outlined,
                  key: Key('nav-organize'),
                ),
                label: mobileStrings.text('organize'),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _BootstrapFailure extends StatelessWidget {
  const _BootstrapFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('mobile-bootstrap-failure'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.phonelink_erase_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                strings.text('bootstrapTitle'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(strings.text('bootstrapBody'), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('mobile-bootstrap-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(strings.text('retryBootstrap')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _RecentPage extends StatefulWidget {
  const _RecentPage({
    super.key,
    required this.repository,
    required this.active,
  });

  final MobileRepository repository;
  final bool active;

  @override
  State<_RecentPage> createState() => _RecentPageState();
}

final class _RecentPageState extends State<_RecentPage> {
  Future<List<FileRecord>>? _records;

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _RecentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _records = null;
    _ensureLoaded();
  }

  void _ensureLoaded() {
    if (widget.active && _records == null) refresh();
  }

  void refresh() {
    setState(() {
      _records =
          Future.wait(<Future<List<FileRecord>>>[
            for (final kind in const <AndroidMediaKind>[
              AndroidMediaKind.images,
              AndroidMediaKind.videos,
              AndroidMediaKind.audio,
              AndroidMediaKind.downloads,
              AndroidMediaKind.documents,
              AndroidMediaKind.applications,
              AndroidMediaKind.archives,
            ])
              widget.repository.loadMedia(kind, limit: 40),
          ]).then((pages) {
            final byId = <String, FileRecord>{};
            for (final record in pages.expand((page) => page)) {
              byId[record.id] = record;
            }
            final records = byId.values.toList(growable: false)
              ..sort((left, right) {
                final leftDate = left.createdAt ?? left.modifiedAt;
                final rightDate = right.createdAt ?? right.modifiedAt;
                return rightDate.compareTo(leftDate);
              });
            return records.take(160).toList(growable: false);
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    return FutureBuilder<List<FileRecord>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(strings.text('collectionUnavailable')));
        }
        final records = snapshot.data ?? const <FileRecord>[];
        return ListView.builder(
          key: const Key('recent-file-list'),
          padding: const EdgeInsets.all(12),
          itemCount: records.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  strings.text('recent'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              );
            }
            final record = records[index - 1];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              leading: SizedBox.square(
                dimension: 58,
                child: _OnDemandThumbnail(
                  repository: widget.repository,
                  record: record,
                  maxWidth: 144,
                  maxHeight: 144,
                  fallbackIcon: _iconFor(record.category),
                ),
              ),
              title: Text(record.displayName),
              subtitle: Text(
                '${_categoryLabel(strings, record.category)} · '
                '${_formatBytes(record.sizeBytes)} · '
                '${_formatDateTime(record.createdAt ?? record.modifiedAt)}'
                '${_durationLabel(record)}',
              ),
              onTap: () => _showMediaItem(
                context,
                record,
                widget.repository,
                records: records,
              ),
            );
          },
        );
      },
    );
  }
}

enum _OrganizeSection { menu, screenshots, photos, storage }

final class _OrganizePage extends StatefulWidget {
  const _OrganizePage({
    super.key,
    required this.bootstrap,
    required this.repository,
    required this.active,
    required this.canReadMedia,
    required this.onRequestAccess,
    required this.onChooseTree,
  });

  final MobileBootstrapState? bootstrap;
  final MobileRepository repository;
  final bool active;
  final bool canReadMedia;
  final VoidCallback onRequestAccess;
  final VoidCallback onChooseTree;

  @override
  State<_OrganizePage> createState() => _OrganizePageState();
}

final class _OrganizePageState extends State<_OrganizePage> {
  _OrganizeSection _section = _OrganizeSection.menu;
  final _screenshotsKey = GlobalKey<_ScreenshotsPageState>();

  void openScreenshots() =>
      setState(() => _section = _OrganizeSection.screenshots);
  void openStorage() => setState(() => _section = _OrganizeSection.storage);

  void refresh() {
    if (_section == _OrganizeSection.screenshots) {
      _screenshotsKey.currentState?.refresh();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    Widget withBack(Widget child) => Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => setState(() => _section = _OrganizeSection.menu),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        Expanded(child: child),
      ],
    );

    return switch (_section) {
      _OrganizeSection.screenshots => withBack(
        _ScreenshotsPage(
          key: _screenshotsKey,
          repository: widget.repository,
          active: widget.active,
          canReadMedia: widget.canReadMedia,
          onRequestAccess: widget.onRequestAccess,
          onChooseTree: widget.onChooseTree,
        ),
      ),
      _OrganizeSection.photos => withBack(
        _PhotosPage(
          repository: widget.repository,
          active: widget.active,
          canReadMedia: widget.canReadMedia,
          onRequestAccess: widget.onRequestAccess,
          onChooseTree: widget.onChooseTree,
        ),
      ),
      _OrganizeSection.storage => withBack(
        _StoragePage(
          bootstrap: widget.bootstrap,
          repository: widget.repository,
          active: widget.active,
        ),
      ),
      _OrganizeSection.menu => ListView(
        key: const Key('organize-home'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            strings.text('organize'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          _OrganizeCard(
            key: const Key('organize-screenshots'),
            icon: PickLogicVisualIcon.screenshot,
            title: strings.text('screenshotsTitle'),
            subtitle: strings.text('reviewSafety'),
            onTap: openScreenshots,
          ),
          const SizedBox(height: 10),
          _OrganizeCard(
            key: const Key('organize-photos'),
            icon: PickLogicVisualIcon.image,
            title: strings.text('photosTitle'),
            subtitle: strings.text('photosDescription'),
            onTap: () => setState(() => _section = _OrganizeSection.photos),
          ),
          const SizedBox(height: 10),
          _OrganizeCard(
            key: const Key('organize-storage'),
            icon: PickLogicVisualIcon.storage,
            title: strings.text('storageTitle'),
            subtitle: strings.text('limitPlatform'),
            onTap: openStorage,
          ),
        ],
      ),
    };
  }
}

final class _OrganizeCard extends StatelessWidget {
  const _OrganizeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final PickLogicVisualIcon icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListTile(
      contentPadding: const EdgeInsets.all(12),
      leading: PickLogicIcon(icon, size: 54, semanticLabel: title),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

final class _FilesPage extends StatefulWidget {
  const _FilesPage({
    super.key,
    required this.repository,
    required this.active,
    required this.onChooseTree,
    required this.onSearch,
    required this.bootstrap,
    required this.onOpenScreenshots,
    required this.onOpenStorage,
    required this.onOpenRecent,
  });

  final MobileRepository repository;
  final bool active;
  final VoidCallback onChooseTree;
  final VoidCallback onSearch;
  final MobileBootstrapState? bootstrap;
  final VoidCallback onOpenScreenshots;
  final VoidCallback onOpenStorage;
  final VoidCallback onOpenRecent;

  @override
  State<_FilesPage> createState() => _FilesPageState();
}

final class _FilesPageState extends State<_FilesPage> {
  AndroidMediaKind _kind = AndroidMediaKind.documents;
  bool _collectionOpen = false;
  final ScrollController _scrollController = ScrollController();
  PagedMediaController<FileRecord>? _pager;
  late Map<AndroidMediaKind, Future<int>> _counts;
  Future<List<FileRecord>>? _sourceRecords;
  late Future<List<AndroidBrowseRoot>> _browseRoots;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHomeData();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _pager = null;
      _loadHomeData();
    }
    _ensureLoaded();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (widget.active && _pager == null) _resetPager(_kind);
  }

  void _loadHomeData() {
    _browseRoots = widget.repository.loadBrowseRoots();
    _counts = <AndroidMediaKind, Future<int>>{
      for (final kind in const <AndroidMediaKind>[
        AndroidMediaKind.images,
        AndroidMediaKind.audio,
        AndroidMediaKind.videos,
        AndroidMediaKind.applications,
        AndroidMediaKind.archives,
        AndroidMediaKind.documents,
      ])
        kind: widget.repository.countMedia(kind),
    };
    _sourceRecords =
        Future.wait(<Future<List<FileRecord>>>[
          widget.repository.loadMedia(AndroidMediaKind.images, limit: 120),
          widget.repository.loadMedia(AndroidMediaKind.screenshots, limit: 120),
          widget.repository.loadMedia(AndroidMediaKind.downloads, limit: 120),
          widget.repository.loadMedia(AndroidMediaKind.documents, limit: 120),
        ]).then((pages) {
          final byId = <String, FileRecord>{};
          for (final record in pages.expand((page) => page)) {
            byId[record.id] = record;
          }
          return byId.values.toList(growable: false);
        });
  }

  void refresh() {
    _loadHomeData();
    if (_collectionOpen) _resetPager(_kind);
    setState(() {});
  }

  PagedMediaController<FileRecord> _createPager(AndroidMediaKind kind) =>
      PagedMediaController<FileRecord>(
        loader: (offset, limit) =>
            widget.repository.loadMedia(kind, offset: offset, limit: limit),
        counter: () => widget.repository.countMedia(kind),
        idOf: (record) => record.id,
        dateOf: (record) => record.createdAt ?? record.modifiedAt,
      );

  void _resetPager(AndroidMediaKind kind) {
    final pager = _createPager(kind);
    setState(() => _pager = pager);
    unawaited(_loadNext(pager));
  }

  Future<void> _loadNext(PagedMediaController<FileRecord> pager) async {
    if (pager.isLoading || !pager.hasMore) return;
    setState(() {});
    try {
      await pager.loadNext();
    } catch (_) {
      // The localized retry footer remains available.
    }
    if (mounted && identical(_pager, pager)) setState(() {});
  }

  void _onScroll() {
    final pager = _pager;
    if (pager != null && _scrollController.position.extentAfter < 600) {
      unawaited(_loadNext(pager));
    }
  }

  void selectCollection(AndroidMediaKind kind) {
    setState(() {
      _kind = kind;
      _collectionOpen = true;
    });
    _resetPager(kind);
  }

  Future<void> _addBrowseRoot() async {
    final selected = await widget.repository.chooseDocumentTree();
    if (!mounted || selected == null) return;
    setState(() => _browseRoots = widget.repository.loadBrowseRoots());
    final roots = await _browseRoots;
    if (!mounted) return;
    final root = roots.where((item) => item.treeUri == selected).firstOrNull;
    _openFolderBrowser(root);
  }

  void _openFolderBrowser([AndroidBrowseRoot? root]) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MobileFileBrowserPage(
          repository: widget.repository,
          initialRoot: root,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    final pager = _pager;
    final records = pager?.items ?? const <FileRecord>[];
    if (_collectionOpen) {
      return _MobileCollectionView(
        strings: strings,
        kind: _kind,
        pager: pager,
        records: records,
        controller: _scrollController,
        repository: widget.repository,
        onBack: () => setState(() => _collectionOpen = false),
        onLoadMore: pager == null ? null : () => _loadNext(pager),
        onTrashed: (id) {
          if (pager?.removeById(id) ?? false) {
            _loadHomeData();
            setState(() {});
          }
        },
      );
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const Key('mobile-home-search'),
          readOnly: true,
          onTap: widget.onSearch,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: strings.text('homeSearchHint'),
            border: InputBorder.none,
            filled: true,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          key: const Key('mobile-folder-browser-entry'),
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  key: const Key('mobile-folder-browser-open'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_copy_outlined, size: 42),
                  title: Text(
                    strings.locale.languageCode == 'zh'
                        ? '文件夹浏览'
                        : 'Folder browser',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    strings.locale.languageCode == 'zh'
                        ? '逐层打开已授权文件夹，照片、视频和文档可直接在 PickLogic 中打开。'
                        : 'Browse authorized folders hierarchically and open photos, videos, and documents directly in PickLogic.',
                  ),
                  trailing: IconButton.filled(
                    tooltip: strings.locale.languageCode == 'zh'
                        ? '添加文件夹'
                        : 'Add folder',
                    onPressed: _addBrowseRoot,
                    icon: const Icon(Icons.add),
                  ),
                  onTap: _openFolderBrowser,
                ),
                FutureBuilder<List<AndroidBrowseRoot>>(
                  future: _browseRoots,
                  builder: (context, snapshot) {
                    final roots = snapshot.data ?? const <AndroidBrowseRoot>[];
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LinearProgressIndicator();
                    }
                    if (roots.isEmpty) {
                      return Text(
                        strings.locale.languageCode == 'zh'
                            ? '点击＋添加 Downloads、Documents 或任意允许访问的文件夹。'
                            : 'Tap + to add Downloads, Documents, or another accessible folder.',
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final root in roots)
                          ActionChip(
                            avatar: const Icon(Icons.folder_outlined, size: 18),
                            label: Text(root.displayName),
                            onPressed: () => _openFolderBrowser(root),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _MobileSectionTitle(strings.text('fileTypes')),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.08,
          children: [
            _TypeShortcut(
              key: const Key('files-recent-media'),
              icon: PickLogicVisualIcon.image,
              label: strings.text('images'),
              count: _counts[AndroidMediaKind.images],
              selected: _kind == AndroidMediaKind.images,
              onTap: () => selectCollection(AndroidMediaKind.images),
            ),
            _TypeShortcut(
              icon: PickLogicVisualIcon.audio,
              label: strings.text('audio'),
              count: _counts[AndroidMediaKind.audio],
              selected: _kind == AndroidMediaKind.audio,
              onTap: () => selectCollection(AndroidMediaKind.audio),
            ),
            _TypeShortcut(
              icon: PickLogicVisualIcon.video,
              label: strings.text('videos'),
              count: _counts[AndroidMediaKind.videos],
              selected: _kind == AndroidMediaKind.videos,
              onTap: () => selectCollection(AndroidMediaKind.videos),
            ),
            _TypeShortcut(
              icon: PickLogicVisualIcon.application,
              label: strings.text('apps'),
              count: _counts[AndroidMediaKind.applications],
              selected: _kind == AndroidMediaKind.applications,
              onTap: () => selectCollection(AndroidMediaKind.applications),
            ),
            _TypeShortcut(
              icon: PickLogicVisualIcon.archive,
              label: strings.text('archives'),
              count: _counts[AndroidMediaKind.archives],
              selected: _kind == AndroidMediaKind.archives,
              onTap: () => selectCollection(AndroidMediaKind.archives),
            ),
            _TypeShortcut(
              key: const Key('files-documents'),
              icon: PickLogicVisualIcon.document,
              label: strings.text('documents'),
              count: _counts[AndroidMediaKind.documents],
              selected: _kind == AndroidMediaKind.documents,
              onTap: () => selectCollection(AndroidMediaKind.documents),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _MobileSectionTitle(strings.text('smartCollections')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SmartCollectionChip(
              icon: Icons.screenshot_outlined,
              label: strings.text('screenshotsTitle'),
              onTap: widget.onOpenScreenshots,
            ),
            _SmartCollectionChip(
              key: const Key('files-downloads'),
              icon: Icons.download_outlined,
              label: strings.text('downloads'),
              onTap: () => selectCollection(AndroidMediaKind.downloads),
            ),
            _SmartCollectionChip(
              icon: Icons.schedule_outlined,
              label: strings.text('recent'),
              onTap: widget.onOpenRecent,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _MobileSectionTitle(strings.text('appsSources')),
        const SizedBox(height: 6),
        FutureBuilder<List<FileRecord>>(
          future: _sourceRecords,
          builder: (context, snapshot) {
            final sourceRecords = snapshot.data ?? const <FileRecord>[];
            final sources = _sourceFacets(sourceRecords);
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (sources.isEmpty) return Text(strings.text('sourcesEmpty'));
            return SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sources.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  return ActionChip(
                    avatar: const Icon(Icons.source_outlined, size: 18),
                    label: Text(
                      '${_sourceDisplayName(strings, source.label)} · ${source.count}',
                    ),
                    onPressed: () => _showSourceSheet(
                      context,
                      strings,
                      source,
                      sourceRecords,
                      widget.repository,
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        _PhoneStorageCard(
          key: const Key('phone-storage-entry'),
          strings: strings,
          bootstrap: widget.bootstrap,
          onTap: widget.onOpenStorage,
        ),
        TextButton.icon(
          onPressed: widget.onChooseTree,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: Text(strings.text('chooseSafReadOnly')),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

final class _MobileCollectionView extends StatelessWidget {
  const _MobileCollectionView({
    required this.strings,
    required this.kind,
    required this.pager,
    required this.records,
    required this.controller,
    required this.repository,
    required this.onBack,
    required this.onLoadMore,
    required this.onTrashed,
  });

  final MobileLocalizations strings;
  final AndroidMediaKind kind;
  final PagedMediaController<FileRecord>? pager;
  final List<FileRecord> records;
  final ScrollController controller;
  final MobileRepository repository;
  final VoidCallback onBack;
  final VoidCallback? onLoadMore;
  final ValueChanged<String> onTrashed;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('mobile-collection-view'),
    controller: controller,
    padding: const EdgeInsets.all(12),
    children: [
      Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
          const SizedBox(width: 4),
          Text(
            _kindLabel(strings, kind),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
      if (pager == null || (pager!.isLoading && records.isEmpty))
        const LinearProgressIndicator()
      else if (pager!.error != null && records.isEmpty)
        Text(strings.text('collectionUnavailable'))
      else if (records.isEmpty)
        Text(strings.text('emptyCollection'))
      else ...[
        _PagedProgress(pager: pager!),
        for (final record in records)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            leading: SizedBox.square(
              dimension: 58,
              child: _OnDemandThumbnail(
                repository: repository,
                record: record,
                maxWidth: 144,
                maxHeight: 144,
                fallbackIcon: _iconFor(record.category),
              ),
            ),
            title: Text(record.displayName),
            subtitle: Text(
              '${_categoryLabel(strings, record.category)} · '
              '${_formatBytes(record.sizeBytes)} · '
              '${_formatDateTime(record.createdAt ?? record.modifiedAt)}'
              '${_durationLabel(record)}',
            ),
            onTap: () async {
              final moved = await _showMediaItem(
                context,
                record,
                repository,
                records: records,
              );
              if (moved) onTrashed(record.id);
            },
          ),
        _LoadMoreFooter(pager: pager!, onLoadMore: onLoadMore!),
      ],
    ],
  );
}

String _kindLabel(MobileLocalizations strings, AndroidMediaKind kind) =>
    switch (kind) {
      AndroidMediaKind.images ||
      AndroidMediaKind.photos => strings.text('images'),
      AndroidMediaKind.videos => strings.text('videos'),
      AndroidMediaKind.audio => strings.text('audio'),
      AndroidMediaKind.screenshots => strings.text('screenshotsTitle'),
      AndroidMediaKind.downloads => strings.text('downloads'),
      AndroidMediaKind.documents => strings.text('documents'),
      AndroidMediaKind.applications => strings.text('apps'),
      AndroidMediaKind.archives => strings.text('archives'),
    };

final class _MobileSectionTitle extends StatelessWidget {
  const _MobileSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
  );
}

final class _TypeShortcut extends StatelessWidget {
  const _TypeShortcut({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final PickLogicVisualIcon icon;
  final String label;
  final Future<int>? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(PickLogicTokens.radiusSmall),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PickLogicIcon(icon, size: 52, semanticLabel: label),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          FutureBuilder<int>(
            future: count,
            builder: (context, snapshot) => Text(
              snapshot.data?.toString() ?? '—',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _PhoneStorageCard extends StatelessWidget {
  const _PhoneStorageCard({
    super.key,
    required this.strings,
    required this.bootstrap,
    required this.onTap,
  });

  final MobileLocalizations strings;
  final MobileBootstrapState? bootstrap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final storage = bootstrap?.storage;
    final used = storage == null
        ? 0
        : storage.totalBytes - storage.availableBytes;
    final fraction = storage == null || storage.totalBytes == 0
        ? 0.0
        : (used / storage.totalBytes).clamp(0.0, 1.0);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(PickLogicTokens.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              PickLogicIcon(
                PickLogicVisualIcon.storage,
                size: 54,
                semanticLabel: strings.text('phoneStorage'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('phoneStorage'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: fraction),
                    const SizedBox(height: 4),
                    Text(
                      storage == null
                          ? strings.text('storageLoading')
                          : strings.format('volumeDetail', <String, Object>{
                              'used': _formatBytes(used),
                              'total': _formatBytes(storage.totalBytes),
                            }),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SmartCollectionChip extends StatelessWidget {
  const _SmartCollectionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onPressed: onTap,
  );
}

final class _SourceFacet {
  const _SourceFacet({required this.label, required this.count});

  final String label;
  final int count;
}

List<_SourceFacet> _sourceFacets(List<FileRecord> records) {
  final counts = <String, int>{};
  for (final record in records) {
    final source = _sourceLabelForRecord(record);
    if (source == null) continue;
    counts.update(source, (value) => value + 1, ifAbsent: () => 1);
  }
  final facets =
      counts.entries
          .map((entry) => _SourceFacet(label: entry.key, count: entry.value))
          .toList(growable: false)
        ..sort((left, right) => right.count.compareTo(left.count));
  return facets;
}

String? _sourceLabelForRecord(FileRecord record) {
  final hint = record.tags
      .where((tag) => tag.startsWith('source-hint:'))
      .map((tag) => tag.substring('source-hint:'.length).trim())
      .where((value) => value.isNotEmpty)
      .firstOrNull;
  final path = record.tags
      .where((tag) => tag.startsWith('relative-path:'))
      .map((tag) => tag.substring('relative-path:'.length))
      .firstOrNull;
  final raw = '${hint ?? ''} ${path ?? ''}'.toLowerCase();
  if (raw.contains('wechat') || raw.contains('micromsg')) return 'wechat';
  if (raw.contains('tencent/qq') || raw.contains('mobileqq')) return 'qq';
  if (raw.contains('browser') ||
      raw.contains('chrome') ||
      raw.contains('edge')) {
    return 'browser';
  }
  if (raw.contains('camera') || raw.contains('dcim')) return 'camera';
  if (raw.contains('screenshot')) return 'screenshots';
  if (raw.contains('download')) return 'downloads';
  if (raw.contains('bluetooth')) return 'bluetooth';
  if (raw.contains('cuuca') || raw.contains('nubia')) return 'transfer';
  return hint;
}

String _sourceDisplayName(MobileLocalizations strings, String source) =>
    switch (source) {
      'wechat' => strings.text('sourceWechat'),
      'qq' => 'QQ',
      'browser' => strings.text('sourceBrowser'),
      'camera' => strings.text('sourceCamera'),
      'screenshots' => strings.text('screenshotsTitle'),
      'downloads' => strings.text('downloads'),
      'bluetooth' => strings.text('sourceBluetooth'),
      'transfer' => strings.text('sourceTransfer'),
      _ => source,
    };

String? _recordLocation(FileRecord record) {
  final path = record.tags
      .where((tag) => tag.startsWith('relative-path:'))
      .map((tag) => tag.substring('relative-path:'.length))
      .where((value) => value.isNotEmpty)
      .firstOrNull;
  return path ?? _sourceLabelForRecord(record);
}

void _showSourceSheet(
  BuildContext context,
  MobileLocalizations strings,
  _SourceFacet source,
  List<FileRecord> records,
  MobileRepository repository,
) {
  final visible = records
      .where((record) => _sourceLabelForRecord(record) == source.label)
      .toList(growable: false);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.75,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.source_outlined),
            title: Text(_sourceDisplayName(strings, source.label)),
            subtitle: Text(
              '${strings.text('sourceInferred')} · '
              '${strings.format('itemCount', {'count': source.count})}',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final record = visible[index];
                return ListTile(
                  leading: SizedBox.square(
                    dimension: 48,
                    child: _OnDemandThumbnail(
                      repository: repository,
                      record: record,
                      maxWidth: 112,
                      maxHeight: 112,
                      fallbackIcon: _iconFor(record.category),
                    ),
                  ),
                  title: Text(record.displayName),
                  subtitle: Text(
                    '${_categoryLabel(strings, record.category)} · ${_formatBytes(record.sizeBytes)}',
                  ),
                  onTap: () => _showMediaItem(
                    context,
                    record,
                    repository,
                    records: records,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

final class _ScreenshotsPage extends StatefulWidget {
  const _ScreenshotsPage({
    super.key,
    required this.repository,
    required this.active,
    required this.canReadMedia,
    required this.onRequestAccess,
    required this.onChooseTree,
  });

  final MobileRepository repository;
  final bool active;
  final bool canReadMedia;
  final VoidCallback onRequestAccess;
  final VoidCallback onChooseTree;

  @override
  State<_ScreenshotsPage> createState() => _ScreenshotsPageState();
}

final class _ScreenshotsPageState extends State<_ScreenshotsPage> {
  final Map<String, ScreenshotReviewState> _review = {};
  final ScrollController _scrollController = ScrollController();
  PagedMediaController<MobileScreenshotCandidate>? _pager;
  String? _month;
  int _gridColumns = 3;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_restoreGridColumns());
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _ScreenshotsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.canReadMedia && widget.canReadMedia) ||
        oldWidget.repository != widget.repository) {
      _pager = null;
      unawaited(_restoreGridColumns());
    }
    _ensureLoaded();
  }

  Future<void> _restoreGridColumns() async {
    final value = await widget.repository.loadGridColumns(
      'screenshotGridColumns',
    );
    if (mounted) setState(() => _gridColumns = value);
  }

  void _setGridColumns(int value) {
    final bounded = value.clamp(2, 6);
    if (bounded == _gridColumns) return;
    setState(() => _gridColumns = bounded);
    unawaited(
      widget.repository.saveGridColumns('screenshotGridColumns', bounded),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (widget.active && widget.canReadMedia && _pager == null) {
      refresh();
    }
  }

  void refresh() {
    if (!widget.canReadMedia) return;
    final pager = PagedMediaController<MobileScreenshotCandidate>(
      loader: (offset, limit) => widget.repository.loadScreenshotCandidates(
        offset: offset,
        limit: limit,
      ),
      counter: () => widget.repository.countMedia(AndroidMediaKind.screenshots),
      idOf: (candidate) => candidate.record.id,
      dateOf: (candidate) => candidate.capturedAt,
    );
    setState(() => _pager = pager);
    unawaited(_loadNext(pager));
  }

  Future<void> _loadNext(
    PagedMediaController<MobileScreenshotCandidate> pager,
  ) async {
    if (pager.isLoading || !pager.hasMore) return;
    setState(() {});
    try {
      await pager.loadNext();
    } catch (_) {
      // The localized retry footer remains available.
    }
    if (mounted && identical(_pager, pager)) setState(() {});
  }

  void _onScroll() {
    final pager = _pager;
    if (pager != null && _scrollController.position.extentAfter < 600) {
      unawaited(_loadNext(pager));
    }
  }

  void _selectMonth(String? month) {
    setState(() => _month = month);
    final pager = _pager;
    if (pager != null && pager.hasMore) unawaited(_loadNext(pager));
  }

  void _mark(FileRecord record, ScreenshotReviewState state) {
    setState(() => _review[record.id] = state);
    final strings = MobileLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strings.format('markerSaved', <String, Object>{
            'state': _reviewLabel(strings, state),
          }),
        ),
      ),
    );
  }

  void _removeTrashed(FileRecord record) {
    _review.remove(record.id);
    _pager?.removeById(record.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    if (!widget.canReadMedia) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            strings.text('screenshotsTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _AccessRequired(
            onRequestAccess: widget.onRequestAccess,
            onChooseTree: widget.onChooseTree,
          ),
          Text(strings.text('screenshotPermissionDetail')),
        ],
      );
    }
    final pager = _pager;
    if (pager == null) {
      return Center(child: Text(strings.text('screenshotLazy')));
    }
    if (pager.isLoading && pager.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pager.error != null && pager.items.isEmpty) {
      return Center(child: Text(strings.text('screenshotError')));
    }
    final groups = buildScreenshotGroups(pager.items);
    final entries = <_ScreenshotPageEntry>[
      for (final group in groups)
        for (final record in group.records)
          _ScreenshotPageEntry(group: group, record: record),
    ];
    final months = <String>{
      for (final entry in entries)
        _monthKey(entry.record.createdAt ?? entry.record.modifiedAt),
    }.toList(growable: false);
    final now = DateTime.now();
    final visible = entries
        .where(
          (entry) => switch (_month) {
            null => true,
            'current' => () {
              final date = (entry.record.createdAt ?? entry.record.modifiedAt)
                  .toLocal();
              return date.year == now.year && date.month == now.month;
            }(),
            'consecutive' => entry.group.records.length > 1,
            'review' =>
              (_review[entry.record.id] ?? ScreenshotReviewState.unreviewed) ==
                  ScreenshotReviewState.deleteReview,
            final month =>
              _monthKey(entry.record.createdAt ?? entry.record.modifiedAt) ==
                  month,
          },
        )
        .toList(growable: false);
    final keepCount = _review.values
        .where((state) => state == ScreenshotReviewState.keep)
        .length;
    final laterCount = _review.values
        .where((state) => state == ScreenshotReviewState.later)
        .length;
    final deleteCount = _review.values
        .where((state) => state == ScreenshotReviewState.deleteReview)
        .length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entries.isEmpty)
            Expanded(
              child: Center(child: Text(strings.text('screenshotEmpty'))),
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('screenshotsTitle'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    strings.format('screenshotCount', <String, Object>{
                      'total': pager.totalCount ?? pager.loadedCount,
                      'visible': entries.length,
                    }),
                    key: const Key('screenshot-real-count'),
                  ),
                  Text(strings.text('groupNote')),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          key: const Key('screenshot-month-all'),
                          label: Text(strings.text('allMonths')),
                          selected: _month == null,
                          onSelected: (_) => _selectMonth(null),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          key: const Key('screenshot-filter-month'),
                          label: Text(strings.text('currentMonth')),
                          selected: _month == 'current',
                          onSelected: (_) => _selectMonth(
                            _month == 'current' ? null : 'current',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          key: const Key('screenshot-filter-consecutive'),
                          label: Text(strings.text('consecutiveOnly')),
                          selected: _month == 'consecutive',
                          onSelected: (_) => _selectMonth(
                            _month == 'consecutive' ? null : 'consecutive',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          key: const Key('screenshot-filter-review'),
                          label: Text(strings.text('reviewPending')),
                          selected: _month == 'review',
                          onSelected: (_) => _selectMonth(
                            _month == 'review' ? null : 'review',
                          ),
                        ),
                        for (final month in months) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            key: Key('screenshot-month-$month'),
                            label: Text(month),
                            selected: _month == month,
                            onSelected: (_) => _selectMonth(month),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.format('reviewSummary', <String, Object>{
                      'keep': keepCount,
                      'later': laterCount,
                      'delete': deleteCount,
                    }),
                    key: const Key('screenshot-review-summary'),
                  ),
                  Text(strings.text('reviewSafety')),
                  if (pager.hasMore)
                    Text(
                      strings.format('monthProgress', <String, Object>{
                        'loaded': pager.loadedCount,
                        'total': pager.totalCount ?? '—',
                      }),
                      key: const Key('screenshot-month-progress'),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _PinchColumnGrid(
                      columns: _gridColumns,
                      onColumnsChanged: _setGridColumns,
                      child: GridView.builder(
                        key: const Key('screenshot-thumbnail-grid'),
                        controller: _scrollController,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _gridColumns,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final entry = visible[index];
                          final record = entry.record;
                          final group = entry.group.summary;
                          final state =
                              _review[record.id] ??
                              ScreenshotReviewState.unreviewed;
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: Key('screenshot-item-${record.id}'),
                              onTap: () => _showScreenshotItem(
                                context,
                                record,
                                entry.group,
                                state,
                                widget.repository,
                                _mark,
                                _removeTrashed,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _OnDemandThumbnail(
                                    repository: widget.repository,
                                    record: record,
                                    maxWidth: 192,
                                    maxHeight: 192,
                                    fallbackIcon:
                                        Icons.screenshot_monitor_outlined,
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      width: double.infinity,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withValues(alpha: 0.90),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        _formatDateTime(
                                          record.createdAt ?? record.modifiedAt,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ),
                                  ),
                                  if (group.memberIds.length > 1)
                                    _GridBadge(
                                      alignment: Alignment.topLeft,
                                      label: strings.format(
                                        'consecutive',
                                        <String, Object>{
                                          'count': group.memberIds.length,
                                        },
                                      ),
                                    ),
                                  if (state != ScreenshotReviewState.unreviewed)
                                    _GridBadge(
                                      alignment: Alignment.topRight,
                                      label: _reviewLabel(strings, state),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  _LoadMoreFooter(
                    pager: pager,
                    onLoadMore: () => _loadNext(pager),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

final class _PhotosPage extends StatefulWidget {
  const _PhotosPage({
    required this.repository,
    required this.active,
    required this.canReadMedia,
    required this.onRequestAccess,
    required this.onChooseTree,
  });

  final MobileRepository repository;
  final bool active;
  final bool canReadMedia;
  final VoidCallback onRequestAccess;
  final VoidCallback onChooseTree;

  @override
  State<_PhotosPage> createState() => _PhotosPageState();
}

final class _PhotosPageState extends State<_PhotosPage> {
  final ScrollController _scrollController = ScrollController();
  PagedMediaController<FileRecord>? _pager;
  String _query = '';
  String _filter = 'all';
  int _gridColumns = 3;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_restoreGridColumns());
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _PhotosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.canReadMedia && widget.canReadMedia) ||
        oldWidget.repository != widget.repository) {
      _pager = null;
      unawaited(_restoreGridColumns());
    }
    _ensureLoaded();
  }

  Future<void> _restoreGridColumns() async {
    final value = await widget.repository.loadGridColumns('photoGridColumns');
    if (mounted) setState(() => _gridColumns = value);
  }

  void _setGridColumns(int value) {
    final bounded = value.clamp(2, 6);
    if (bounded == _gridColumns) return;
    setState(() => _gridColumns = bounded);
    unawaited(widget.repository.saveGridColumns('photoGridColumns', bounded));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (widget.active && widget.canReadMedia && _pager == null) {
      final pager = PagedMediaController<FileRecord>(
        loader: (offset, limit) => widget.repository.loadMedia(
          AndroidMediaKind.photos,
          offset: offset,
          limit: limit,
        ),
        counter: () => widget.repository.countMedia(AndroidMediaKind.photos),
        idOf: (record) => record.id,
        dateOf: (record) => record.createdAt ?? record.modifiedAt,
      );
      _pager = pager;
      unawaited(_loadNext(pager));
    }
  }

  Future<void> _loadNext(PagedMediaController<FileRecord> pager) async {
    if (pager.isLoading || !pager.hasMore) return;
    setState(() {});
    try {
      await pager.loadNext();
    } catch (_) {
      // The localized retry footer remains available.
    }
    if (mounted && identical(_pager, pager)) setState(() {});
  }

  void _onScroll() {
    final pager = _pager;
    if (pager != null && _scrollController.position.extentAfter < 600) {
      unawaited(_loadNext(pager));
    }
  }

  void _setQuery(String value) {
    setState(() => _query = value.trim().toLowerCase());
    final pager = _pager;
    if (_query.isNotEmpty && pager != null && pager.hasMore) {
      unawaited(_loadNext(pager));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    if (!widget.canReadMedia) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            strings.text('photosTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _AccessRequired(
            onRequestAccess: widget.onRequestAccess,
            onChooseTree: widget.onChooseTree,
          ),
          Text(strings.text('photosNoAccess')),
        ],
      );
    }
    final pager = _pager;
    if (pager == null) {
      return Center(child: Text(strings.text('photosLazy')));
    }
    if (pager.isLoading && pager.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pager.error != null && pager.items.isEmpty) {
      return Center(child: Text(strings.text('photosError')));
    }
    final records = pager.items
        .where((record) {
          final source = _sourceLabelForRecord(record);
          final matchesFilter = switch (_filter) {
            'camera' => source == 'camera',
            'saved' => source != 'camera',
            _ => true,
          };
          return matchesFilter &&
              (_query.isEmpty ||
                  record.displayName.toLowerCase().contains(_query) ||
                  record.mimeType.toLowerCase().contains(_query));
        })
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text('photosTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(strings.text('photosDescription')),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'all',
                label: Text(strings.text('allPhotos')),
              ),
              ButtonSegment(
                value: 'camera',
                label: Text(strings.text('cameraPhotos')),
              ),
              ButtonSegment(
                value: 'saved',
                label: Text(strings.text('savedPhotos')),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('photos-search-field'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: strings.text('photosSearchHint'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _setQuery,
          ),
          const SizedBox(height: 8),
          _PagedProgress(pager: pager),
          Expanded(
            child: records.isEmpty
                ? Center(child: Text(strings.text('photosNoMatches')))
                : _PinchColumnGrid(
                    columns: _gridColumns,
                    onColumnsChanged: _setGridColumns,
                    child: GridView.builder(
                      key: const Key('photos-thumbnail-grid'),
                      controller: _scrollController,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _gridColumns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () async {
                              final moved = await _showMediaItem(
                                context,
                                record,
                                widget.repository,
                                records: records,
                              );
                              if (moved && mounted) {
                                pager.removeById(record.id);
                                setState(() {});
                              }
                            },
                            child: Semantics(
                              label: record.displayName,
                              child: _OnDemandThumbnail(
                                repository: widget.repository,
                                record: record,
                                maxWidth: 160,
                                maxHeight: 160,
                                fallbackIcon: Icons.image_outlined,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          _LoadMoreFooter(pager: pager, onLoadMore: () => _loadNext(pager)),
        ],
      ),
    );
  }
}

final class _ScreenshotPageEntry {
  const _ScreenshotPageEntry({required this.group, required this.record});

  final MobileScreenshotGroup group;
  final FileRecord record;
}

final class _PagedProgress<T> extends StatelessWidget {
  const _PagedProgress({required this.pager});

  final PagedMediaController<T> pager;

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    final total = pager.totalCount;
    return Text(
      strings.format('loadedProgress', <String, Object>{
        'loaded': pager.loadedCount,
        'total': total ?? '—',
      }),
      key: const Key('paged-media-progress'),
    );
  }
}

final class _LoadMoreFooter<T> extends StatelessWidget {
  const _LoadMoreFooter({required this.pager, required this.onLoadMore});

  final PagedMediaController<T> pager;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    if (pager.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(strings.text('loadingMore')),
          ],
        ),
      );
    }
    if (!pager.hasMore) return const SizedBox.shrink();
    return TextButton.icon(
      key: const Key('paged-media-load-more'),
      onPressed: onLoadMore,
      icon: Icon(
        pager.error == null ? Icons.expand_more : Icons.refresh_outlined,
      ),
      label: Text(
        pager.error == null
            ? strings.text('loadMore')
            : strings.text('loadMoreError'),
      ),
    );
  }
}

final class _GridBadge extends StatelessWidget {
  const _GridBadge({required this.alignment, required this.label});

  final Alignment alignment;
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.inverseSurface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onInverseSurface,
        ),
      ),
    ),
  );
}

final class _OnDemandThumbnail extends StatefulWidget {
  const _OnDemandThumbnail({
    required this.repository,
    required this.record,
    required this.maxWidth,
    required this.maxHeight,
    required this.fallbackIcon,
  });

  final MobileRepository repository;
  final FileRecord record;
  final int maxWidth;
  final int maxHeight;
  final IconData fallbackIcon;

  @override
  State<_OnDemandThumbnail> createState() => _OnDemandThumbnailState();
}

final class _OnDemandThumbnailState extends State<_OnDemandThumbnail> {
  late Future<Uint8List?> _thumbnail;

  @override
  void initState() {
    super.initState();
    _thumbnail = _load();
  }

  @override
  void didUpdateWidget(covariant _OnDemandThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.record.id != widget.record.id ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.maxHeight != widget.maxHeight) {
      _thumbnail = _load();
    }
  }

  Future<Uint8List?> _load() => widget.repository.loadThumbnail(
    widget.record,
    maxWidth: widget.maxWidth,
    maxHeight: widget.maxHeight,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _thumbnail,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes == null) {
        return Center(
          child: snapshot.connectionState == ConnectionState.waiting
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Icon(widget.fallbackIcon, size: 56),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              Center(child: Icon(widget.fallbackIcon, size: 56)),
        ),
      );
    },
  );
}

final class _StoragePage extends StatefulWidget {
  const _StoragePage({
    required this.bootstrap,
    required this.repository,
    required this.active,
  });

  final MobileBootstrapState? bootstrap;
  final MobileRepository repository;
  final bool active;

  @override
  State<_StoragePage> createState() => _StoragePageState();
}

final class _StoragePageState extends State<_StoragePage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _syncRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant _StoragePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.repository != widget.repository) {
      _syncRefreshTimer();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _syncRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!widget.active) return;
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  void _toggleIndexing(MobileIndexQueueSnapshot queue) {
    if (queue.isRunning || queue.pendingBatches > 0) {
      widget.repository.cancelIncrementalIndexing();
    } else {
      widget.repository.scheduleIncrementalIndexing();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    final storage = widget.bootstrap?.storage;
    if (storage == null) {
      return Center(child: Text(strings.text('storageLoading')));
    }
    final used = storage.totalBytes - storage.availableBytes;
    final fraction = storage.totalBytes == 0 ? 0.0 : used / storage.totalBytes;
    final queue = widget.repository.indexQueueSnapshot;
    final visualAccess = widget.bootstrap!.permissions.partialVisualAccess
        ? strings.text('selectedVisualOnly')
        : storage.canInspectSharedMedia
        ? strings.text('authorizedCollections')
        : strings.text('notAuthorized');
    final typeRows = <({String label, AndroidMediaKind kind})>[
      (label: strings.text('images'), kind: AndroidMediaKind.images),
      (label: strings.text('videos'), kind: AndroidMediaKind.videos),
      (label: strings.text('audio'), kind: AndroidMediaKind.audio),
      (label: strings.text('documents'), kind: AndroidMediaKind.documents),
      (label: strings.text('archives'), kind: AndroidMediaKind.archives),
      (label: strings.text('apps'), kind: AndroidMediaKind.applications),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          strings.text('storageTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        AccessibleFolderInsightSection(repository: widget.repository),
        const SizedBox(height: 20),
        _MobileSectionTitle(strings.text('byType')),
        const SizedBox(height: 4),
        for (final row in typeRows)
          FutureBuilder<int>(
            future: widget.repository.countMedia(row.kind),
            builder: (context, snapshot) => ListTile(
              dense: true,
              leading: Icon(_kindIcon(row.kind)),
              title: Text(row.label),
              trailing: Text(snapshot.data?.toString() ?? '—'),
              subtitle: Text(strings.text('observedDirectly')),
            ),
          ),
        const SizedBox(height: 12),
        _MobileSectionTitle(strings.text('bySource')),
        ListTile(
          leading: const Icon(Icons.camera_alt_outlined),
          title: Text(strings.text('cameraAndScreenshots')),
          subtitle: Text(strings.text('inferred')),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(strings.text('downloads')),
          subtitle: Text(strings.text('observedDirectly')),
        ),
        const SizedBox(height: 12),
        _MobileSectionTitle(strings.text('byApp')),
        ListTile(
          leading: const Icon(Icons.apps_outlined),
          title: Text(strings.text('systemReported')),
          subtitle: Text(strings.text('limitPrivate')),
        ),
        const SizedBox(height: 12),
        _MobileSectionTitle(strings.text('otherUnexplained')),
        _StorageTile(
          strings.text('volumeUsed'),
          fraction.clamp(0, 1),
          true,
          strings.format('volumeDetail', <String, Object>{
            'used': _formatBytes(used),
            'total': _formatBytes(storage.totalBytes),
          }),
        ),
        _StorageTile(
          strings.text('sharedMedia'),
          storage.canInspectSharedMedia ? 1 : 0,
          storage.canInspectSharedMedia,
          visualAccess,
        ),
        _StorageTile(
          strings.text('downloadStorage'),
          0,
          storage.canInspectDownloads,
          storage.canInspectDownloads
              ? strings.text('mediaStoreSafOnly')
              : strings.text('safRequired'),
        ),
        _StorageTile(
          strings.text('metadataQueue'),
          queue.isRunning ? null : 0,
          true,
          strings.format(
            queue.persistsAcrossRestarts ? 'queuePersistent' : 'queueSession',
            <String, Object>{
              'items': queue.indexedItems,
              'done': queue.completedBatches,
              'failed': queue.failedBatches,
            },
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: storage.canInspectSharedMedia
                ? () => _toggleIndexing(queue)
                : null,
            icon: Icon(
              queue.isRunning || queue.pendingBatches > 0
                  ? Icons.pause_outlined
                  : Icons.play_arrow_outlined,
            ),
            label: Text(
              queue.isRunning || queue.pendingBatches > 0
                  ? strings.text('pauseIndex')
                  : queue.isPaused
                  ? strings.text('resumeIndex')
                  : strings.text('checkNew'),
            ),
          ),
        ),
        _StorageTile(
          strings.text('privateData'),
          0,
          false,
          strings.text('platformRestriction'),
        ),
        const SizedBox(height: 16),
        Text(
          strings.text('explicitLimits'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text('• ${strings.text('limitPlatform')}'),
        Text('• ${strings.text('limitAggregate')}'),
        Text('• ${strings.text('limitPrivate')}'),
        Text('• ${strings.text('limitBounded')}'),
        Text('• ${strings.text('limitDownloads')}'),
        const SizedBox(height: 8),
        Text(strings.text('safStorageNote')),
      ],
    );
  }
}

final class _StorageTile extends StatelessWidget {
  const _StorageTile(this.label, this.value, this.inspectable, this.detail);

  final String label;
  final double? value;
  final bool inspectable;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${strings.text(inspectable ? 'accessible' : 'restricted')} · $detail',
          ),
          LinearProgressIndicator(value: value),
        ],
      ),
      trailing: Icon(
        inspectable ? Icons.visibility_outlined : Icons.lock_outline,
      ),
    );
  }
}

final class _AccessRequired extends StatelessWidget {
  const _AccessRequired({
    required this.onRequestAccess,
    required this.onChooseTree,
  });

  final VoidCallback onRequestAccess;
  final VoidCallback onChooseTree;

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.text('permissionMissing')),
            Text(strings.text('permissionSafety')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: onRequestAccess,
                  child: Text(strings.text('selectMedia')),
                ),
                OutlinedButton(
                  onPressed: onChooseTree,
                  child: Text(strings.text('selectFolder')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _MobileSearchDelegate extends SearchDelegate<FileRecord?> {
  _MobileSearchDelegate(this.repository, this.strings);

  final MobileRepository repository;
  final MobileLocalizations strings;

  @override
  String get searchFieldLabel => strings.text('searchField');

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => _SearchResults(
    future: repository.search(query),
    onSelected: (record) => close(context, record),
  );

  @override
  Widget buildSuggestions(BuildContext context) => query.trim().length < 2
      ? Center(child: Text(strings.text('searchMinimum')))
      : buildResults(context);
}

final class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.future, required this.onSelected});

  final Future<List<FileRecord>> future;
  final ValueChanged<FileRecord> onSelected;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FileRecord>>(
    future: future,
    builder: (context, snapshot) {
      final strings = MobileLocalizations.of(context);
      if (snapshot.hasError) {
        return Center(child: Text(strings.text('indexUnavailable')));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.data!.isEmpty) {
        return Center(child: Text(strings.text('noSearchResults')));
      }
      return ListView.builder(
        itemCount: snapshot.data!.length,
        itemBuilder: (context, index) {
          final record = snapshot.data![index];
          return ListTile(
            leading: Icon(_iconFor(record.category)),
            title: Text(record.displayName),
            subtitle: Text(_categoryLabel(strings, record.category)),
            onTap: () => onSelected(record),
          );
        },
      );
    },
  );
}

final class _MobileInsightPanel extends StatelessWidget {
  const _MobileInsightPanel({required this.record});

  final FileRecord record;

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    final insight = const BasicInsightEngine().explainFile(record);
    return ListView(
      key: const Key('mobile-insight-panel'),
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          strings.text('insightTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          strings.format('insightSummary', <String, Object>{
            'type': _categoryLabel(strings, record.category),
          }),
        ),
        const SizedBox(height: 16),
        Text(
          strings.text('verifiedFacts'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _InsightDetail(
          label: strings.text('type'),
          value: _categoryLabel(strings, record.category),
        ),
        _InsightDetail(
          label: strings.text('size'),
          value: _formatBytes(record.sizeBytes),
        ),
        _InsightDetail(
          label: strings.text('modified'),
          value: _formatDateTime(record.createdAt ?? record.modifiedAt),
        ),
        _InsightDetail(
          label: strings.text('source'),
          value: _sourceKindLabel(strings, record.sourceKind),
        ),
        _InsightDetail(
          label: strings.text('location'),
          value: _recordLocation(record) ?? strings.text('unknownSource'),
        ),
        const SizedBox(height: 12),
        Text(
          strings.text('ruleInferenceSection'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _InsightDetail(
          label: strings.text('classificationBasis'),
          value: strings.format('classificationBasisValue', <String, Object>{
            'extension': record.extension.isEmpty ? '—' : record.extension,
            'mime': record.mimeType.isEmpty ? '—' : record.mimeType,
          }),
        ),
        _InsightDetail(
          label: strings.text('screenshotFlag'),
          value: strings.text(
            record.category == VirtualCategory.screenshots ? 'yes' : 'no',
          ),
        ),
        _InsightDetail(
          label: strings.text('duplicateState'),
          value: record.hashState == HashState.complete
              ? strings.text('duplicateFingerprintAvailable')
              : strings.text('duplicateNotChecked'),
        ),
        const SizedBox(height: 12),
        Text(
          strings.text('assessment'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _InsightDetail(
          label: strings.text('risk'),
          value: _localizedRisk(strings, insight.riskLevel),
        ),
        _InsightDetail(
          label: strings.text('confidence'),
          value: '${(insight.confidence * 100).round()}%',
        ),
        const SizedBox(height: 12),
        Text(
          strings.text('limitationsTitle'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          strings.text(
            record.category == VirtualCategory.unknown
                ? 'unknownInsightLimitation'
                : 'fileInsightLimitation',
          ),
        ),
        const SizedBox(height: 6),
        Text(strings.text('metadataEvidence')),
      ],
    );
  }
}

final class _InsightDetail extends StatelessWidget {
  const _InsightDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 88, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _localizedRisk(MobileLocalizations strings, RiskLevel risk) =>
    strings.text(switch (risk) {
      RiskLevel.safe => 'safeRisk',
      RiskLevel.review => 'reviewRisk',
      RiskLevel.protected => 'protectedRisk',
      RiskLevel.unknown => 'unknownRisk',
    });

IconData _iconFor(VirtualCategory category) => switch (category) {
  VirtualCategory.pdf ||
  VirtualCategory.academicPapers => Icons.picture_as_pdf_outlined,
  VirtualCategory.images || VirtualCategory.screenshots => Icons.image_outlined,
  VirtualCategory.videos => Icons.video_file_outlined,
  VirtualCategory.audio => Icons.audio_file_outlined,
  VirtualCategory.archives => Icons.archive_outlined,
  _ => Icons.description_outlined,
};

IconData _kindIcon(AndroidMediaKind kind) => switch (kind) {
  AndroidMediaKind.images || AndroidMediaKind.photos => Icons.image_outlined,
  AndroidMediaKind.screenshots => Icons.screenshot_outlined,
  AndroidMediaKind.videos => Icons.video_file_outlined,
  AndroidMediaKind.audio => Icons.audio_file_outlined,
  AndroidMediaKind.downloads => Icons.download_outlined,
  AndroidMediaKind.documents => Icons.description_outlined,
  AndroidMediaKind.applications => Icons.android_outlined,
  AndroidMediaKind.archives => Icons.archive_outlined,
};

String _durationLabel(FileRecord record) {
  final raw = record.tags
      .where((tag) => tag.startsWith('duration-ms:'))
      .map((tag) => int.tryParse(tag.substring('duration-ms:'.length)))
      .whereType<int>()
      .firstOrNull;
  if (raw == null || raw <= 0) return '';
  final totalSeconds = raw ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return ' · $minutes:$seconds';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String _monthKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}';
}

String _reviewLabel(MobileLocalizations strings, ScreenshotReviewState state) =>
    switch (state) {
      ScreenshotReviewState.keep => strings.text('keep'),
      ScreenshotReviewState.later => strings.text('later'),
      ScreenshotReviewState.deleteReview => strings.text('deleteReview'),
      ScreenshotReviewState.protected => strings.text('protected'),
      ScreenshotReviewState.unreviewed => strings.text('unreviewed'),
    };

String _categoryLabel(MobileLocalizations strings, VirtualCategory category) =>
    switch (category) {
      VirtualCategory.documents => strings.text('categoryDocuments'),
      VirtualCategory.spreadsheets => strings.text('categorySpreadsheets'),
      VirtualCategory.presentations => strings.text('categoryPresentations'),
      VirtualCategory.pdf => strings.text('categoryPdf'),
      VirtualCategory.images => strings.text('categoryImages'),
      VirtualCategory.videos => strings.text('categoryVideos'),
      VirtualCategory.audio => strings.text('categoryAudio'),
      VirtualCategory.archives => strings.text('categoryArchives'),
      VirtualCategory.installers => strings.text('categoryInstallers'),
      VirtualCategory.code => strings.text('categoryCode'),
      VirtualCategory.academicPapers => strings.text('categoryAcademicPapers'),
      VirtualCategory.screenshots => strings.text('categoryScreenshots'),
      VirtualCategory.downloads => strings.text('categoryDownloads'),
      VirtualCategory.duplicates => strings.text('categoryDuplicates'),
      VirtualCategory.largeFiles => strings.text('categoryLargeFiles'),
      VirtualCategory.unknown => strings.text('categoryUnknown'),
    };

String _sourceKindLabel(MobileLocalizations strings, SourceKind source) =>
    switch (source) {
      SourceKind.fileSystem => strings.text('sourceFileSystem'),
      SourceKind.mediaStore => strings.text('sourceMediaStore'),
      SourceKind.storageAccessFramework => strings.text(
        'sourceStorageAccessFramework',
      ),
      SourceKind.downloads => strings.text('sourceDownloads'),
      SourceKind.appOwned => strings.text('sourceAppOwned'),
      SourceKind.synthetic => strings.text('sourceSynthetic'),
      SourceKind.unknown => strings.text('sourceUnknownKind'),
    };

String _localizedSourceHint(MobileLocalizations strings, String sourceHint) {
  if (sourceHint == 'unknown') return strings.text('unknownSource');
  if (sourceHint.startsWith('folder:')) {
    return strings.format('folderSource', <String, Object>{
      'name': sourceHint.substring('folder:'.length),
    });
  }
  return sourceHint;
}

Future<bool> _showMediaItem(
  BuildContext context,
  FileRecord record,
  MobileRepository repository, {
  List<FileRecord>? records,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => MobileViewerPage(
          records: records ?? <FileRecord>[record],
          initialRecord: record,
          repository: repository,
        ),
      ),
    ) ??
    false;

/// Observes two-pointer distance without claiming the scroll gesture arena.
/// This keeps one-finger grid scrolling native while pinch changes 2–6 columns.
final class _PinchColumnGrid extends StatefulWidget {
  const _PinchColumnGrid({
    required this.columns,
    required this.onColumnsChanged,
    required this.child,
  });

  final int columns;
  final ValueChanged<int> onColumnsChanged;
  final Widget child;

  @override
  State<_PinchColumnGrid> createState() => _PinchColumnGridState();
}

final class _PinchColumnGridState extends State<_PinchColumnGrid> {
  final Map<int, Offset> _pointers = <int, Offset>{};
  double? _baseline;

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) _baseline = _distance();
  }

  void _move(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length != 2) return;
    final distance = _distance();
    final baseline = _baseline ?? distance;
    if (distance > baseline * 1.18 && widget.columns > 2) {
      widget.onColumnsChanged(widget.columns - 1);
      _baseline = distance;
    } else if (distance < baseline * 0.82 && widget.columns < 6) {
      widget.onColumnsChanged(widget.columns + 1);
      _baseline = distance;
    }
  }

  double _distance() {
    final values = _pointers.values.take(2).toList(growable: false);
    return (values[0] - values[1]).distance;
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _baseline = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    key: const Key('mobile-grid-pinch-listener'),
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

void _showScreenshotItem(
  BuildContext context,
  FileRecord record,
  MobileScreenshotGroup group,
  ScreenshotReviewState state,
  MobileRepository repository,
  void Function(FileRecord, ScreenshotReviewState) onMark,
  void Function(FileRecord) onTrashed,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final strings = MobileLocalizations.of(sheetContext);
      return FractionallySizedBox(
        heightFactor: 0.92,
        child: Column(
          children: [
            SizedBox(
              height: 160,
              width: double.infinity,
              child: InkWell(
                key: const Key('screenshot-open-viewer-thumbnail'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final moved = await _showMediaItem(
                    context,
                    record,
                    repository,
                    records: group.records,
                  );
                  if (moved) onTrashed(record);
                },
                child: _OnDemandThumbnail(
                  repository: repository,
                  record: record,
                  maxWidth: 320,
                  maxHeight: 240,
                  fallbackIcon: Icons.screenshot_monitor_outlined,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Column(
                key: const Key('screenshot-item-details'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  Text(
                    '${record.mimeType} · ${_formatBytes(record.sizeBytes)} · '
                    '${_formatDateTime(record.createdAt ?? record.modifiedAt)}',
                  ),
                  Text(
                    '${strings.format('sourceClue', <String, Object>{'source': _localizedSourceHint(strings, group.summary.sourceHint)})} · '
                    '${group.records.length > 1 ? strings.format('consecutive', <String, Object>{'count': group.records.length}) : strings.text('single')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    strings.format('localMarker', <String, Object>{
                      'state': _reviewLabel(strings, state),
                    }),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _MobileInsightPanel(record: record)),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('screenshot-mark-keep'),
                      onPressed: () {
                        onMark(record, ScreenshotReviewState.keep);
                        Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.bookmark_added_outlined),
                      label: Text(strings.text('keep')),
                    ),
                    OutlinedButton.icon(
                      key: const Key('screenshot-mark-later'),
                      onPressed: () {
                        onMark(record, ScreenshotReviewState.later);
                        Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text(strings.text('later')),
                    ),
                    OutlinedButton.icon(
                      key: const Key('screenshot-mark-delete-review'),
                      onPressed: () {
                        onMark(record, ScreenshotReviewState.deleteReview);
                        Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.rule_folder_outlined),
                      label: Text(strings.text('deleteReview')),
                    ),
                    if (state == ScreenshotReviewState.deleteReview)
                      FilledButton.icon(
                        key: const Key('screenshot-system-trash'),
                        onPressed: () async {
                          final moved = await confirmMobileSystemTrash(
                            sheetContext,
                            record: record,
                            repository: repository,
                          );
                          if (!sheetContext.mounted || !moved) return;
                          Navigator.pop(sheetContext);
                          onTrashed(record);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(strings.text('systemTrash')),
                      ),
                    TextButton.icon(
                      key: const Key('screenshot-open-internal-viewer'),
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        final moved = await _showMediaItem(
                          context,
                          record,
                          repository,
                          records: group.records,
                        );
                        if (moved) onTrashed(record);
                      },
                      icon: const Icon(Icons.fullscreen),
                      label: Text(strings.text('open')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
