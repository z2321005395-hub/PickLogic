import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

import 'src/incremental_index_queue.dart';
import 'src/mobile_localizations.dart';
import 'src/mobile_repository.dart';
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

  final _filesKey = GlobalKey<_FilesPageState>();

  @override
  Widget build(BuildContext context) {
    final strings = PickLogicLocalizations.of(context);
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
            active: _index == 0,
            onChooseTree: _chooseDocumentTree,
            onSearch: _startSearch,
          ),
          _ScreenshotsPage(
            repository: widget.repository,
            active: _index == 1,
            canReadMedia: canReadMedia,
            onRequestAccess: _requestMediaAccess,
            onChooseTree: _chooseDocumentTree,
          ),
          _PhotosPage(
            repository: widget.repository,
            active: _index == 2,
            canReadMedia: canReadMedia,
            onRequestAccess: _requestMediaAccess,
            onChooseTree: _chooseDocumentTree,
          ),
          _StoragePage(
            bootstrap: bootstrap,
            repository: widget.repository,
            active: _index == 3,
          ),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.languageCode == 'zh' ? '拾理' : 'PickLogic'),
            actions: [
              Tooltip(
                message: mobileStrings.text('switchLanguage'),
                child: TextButton.icon(
                  key: const Key('language-switch'),
                  onPressed: widget.onToggleLanguage,
                  icon: const Icon(Icons.translate),
                  label: Text(widget.languageCode == 'zh' ? 'EN' : '中'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.text('search'),
                icon: const Icon(Icons.search),
                onPressed: _startSearch,
              ),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(32),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SafeModeBanner(),
              ),
            ),
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
                icon: const Icon(Icons.folder_outlined, key: Key('nav-files')),
                label: strings.text('files'),
              ),
              NavigationDestination(
                icon: const Icon(
                  Icons.screenshot_outlined,
                  key: Key('nav-screenshots'),
                ),
                label: strings.text('screenshots'),
              ),
              NavigationDestination(
                icon: const Icon(
                  Icons.photo_library_outlined,
                  key: Key('nav-photos'),
                ),
                label: strings.text('photos'),
              ),
              NavigationDestination(
                icon: const Icon(
                  Icons.storage_outlined,
                  key: Key('nav-storage'),
                ),
                label: strings.text('storage'),
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

final class _FilesPage extends StatefulWidget {
  const _FilesPage({
    super.key,
    required this.repository,
    required this.active,
    required this.onChooseTree,
    required this.onSearch,
  });

  final MobileRepository repository;
  final bool active;
  final VoidCallback onChooseTree;
  final VoidCallback onSearch;

  @override
  State<_FilesPage> createState() => _FilesPageState();
}

final class _FilesPageState extends State<_FilesPage> {
  AndroidMediaKind _kind = AndroidMediaKind.documents;
  bool _collectionOpen = false;
  final ScrollController _scrollController = ScrollController();
  PagedMediaController<FileRecord>? _pager;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _pager = null;
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

  @override
  Widget build(BuildContext context) {
    final strings = MobileLocalizations.of(context);
    final pager = _pager;
    final records = pager?.items ?? const <FileRecord>[];
    final sources = _sourceFacets(records);
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
        _MobileSectionTitle(strings.text('fileTypes')),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 6,
          mainAxisSpacing: 6,
          crossAxisSpacing: 4,
          childAspectRatio: 0.78,
          children: [
            _TypeShortcut(
              key: const Key('files-recent-media'),
              icon: Icons.image_outlined,
              label: strings.text('images'),
              selected: _kind == AndroidMediaKind.images,
              onTap: () => selectCollection(AndroidMediaKind.images),
            ),
            _TypeShortcut(
              icon: Icons.audio_file_outlined,
              label: strings.text('audio'),
              selected: _kind == AndroidMediaKind.audio,
              onTap: () => selectCollection(AndroidMediaKind.audio),
            ),
            _TypeShortcut(
              icon: Icons.video_file_outlined,
              label: strings.text('videos'),
              selected: _kind == AndroidMediaKind.videos,
              onTap: () => selectCollection(AndroidMediaKind.videos),
            ),
            _TypeShortcut(
              icon: Icons.apps_outlined,
              label: strings.text('apps'),
              selected: false,
              onTap: () => _showComingNext(context, strings),
            ),
            _TypeShortcut(
              icon: Icons.archive_outlined,
              label: strings.text('archives'),
              selected: false,
              onTap: () => selectCollection(AndroidMediaKind.documents),
            ),
            _TypeShortcut(
              key: const Key('files-documents'),
              icon: Icons.description_outlined,
              label: strings.text('documents'),
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
              onTap: () => selectCollection(AndroidMediaKind.screenshots),
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
              onTap: () => selectCollection(AndroidMediaKind.images),
            ),
            _SmartCollectionChip(
              icon: Icons.file_copy_outlined,
              label: strings.text('duplicates'),
              onTap: () => _showComingNext(context, strings),
            ),
            _SmartCollectionChip(
              icon: Icons.data_usage_outlined,
              label: strings.text('largeFiles'),
              onTap: () => _showComingNext(context, strings),
            ),
            _SmartCollectionChip(
              icon: Icons.favorite_border,
              label: strings.text('favorites'),
              onTap: () => _showComingNext(context, strings),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _MobileSectionTitle(strings.text('appsSources')),
        const SizedBox(height: 6),
        if (sources.isEmpty)
          Text(strings.text('sourcesEmpty'))
        else
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sources.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final source = sources[index];
                return ActionChip(
                  avatar: const Icon(Icons.source_outlined, size: 18),
                  label: Text('${source.label} · ${source.count}'),
                  onPressed: () => _showSourceSheet(
                    context,
                    strings,
                    source,
                    records,
                    widget.repository,
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('phone-storage-entry'),
          leading: const Icon(Icons.phone_android_outlined),
          title: Text(strings.text('phoneStorage')),
          subtitle: Text(strings.text('phoneStorageDetail')),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onChooseTree,
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
  });

  final MobileLocalizations strings;
  final AndroidMediaKind kind;
  final PagedMediaController<FileRecord>? pager;
  final List<FileRecord> records;
  final ScrollController controller;
  final MobileRepository repository;
  final VoidCallback onBack;
  final VoidCallback? onLoadMore;

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
            leading: Icon(_iconFor(record.category)),
            title: Text(record.displayName),
            subtitle: Text(
              '${_categoryLabel(strings, record.category)} · '
              '${_formatBytes(record.sizeBytes)} · '
              '${_formatDateTime(record.createdAt ?? record.modifiedAt)}',
            ),
            onTap: () => _showMediaItem(context, record, repository),
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
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
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
          DecoratedBox(
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(PickLogicTokens.radiusMedium),
            ),
            child: SizedBox.square(
              dimension: 46,
              child: Icon(
                icon,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );
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
  if (raw.contains('wechat') || raw.contains('micromsg')) return '微信';
  if (raw.contains('tencent/qq') || raw.contains('mobileqq')) return 'QQ';
  if (raw.contains('browser') ||
      raw.contains('chrome') ||
      raw.contains('edge')) {
    return 'Browser';
  }
  if (raw.contains('camera') || raw.contains('dcim')) return 'Camera';
  if (raw.contains('screenshot')) return 'Screenshots';
  if (raw.contains('download')) return 'Downloads';
  if (raw.contains('bluetooth')) return 'Bluetooth';
  if (raw.contains('cuuca') || raw.contains('nubia')) return '互传';
  return hint;
}

String? _recordLocation(FileRecord record) {
  final path = record.tags
      .where((tag) => tag.startsWith('relative-path:'))
      .map((tag) => tag.substring('relative-path:'.length))
      .where((value) => value.isNotEmpty)
      .firstOrNull;
  return path ?? _sourceLabelForRecord(record);
}

void _showComingNext(BuildContext context, MobileLocalizations strings) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(strings.text('comingNext'))));
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
            title: Text(source.label),
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
                  leading: Icon(_iconFor(record.category)),
                  title: Text(record.displayName),
                  subtitle: Text(
                    '${_categoryLabel(strings, record.category)} · ${_formatBytes(record.sizeBytes)}',
                  ),
                  onTap: () => _showMediaItem(context, record, repository),
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _ScreenshotsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.canReadMedia && widget.canReadMedia) ||
        oldWidget.repository != widget.repository) {
      _pager = null;
    }
    _ensureLoaded();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (widget.active && widget.canReadMedia && _pager == null) {
      final pager = PagedMediaController<MobileScreenshotCandidate>(
        loader: (offset, limit) => widget.repository.loadScreenshotCandidates(
          offset: offset,
          limit: limit,
        ),
        counter: () =>
            widget.repository.countMedia(AndroidMediaKind.screenshots),
        idOf: (candidate) => candidate.record.id,
        dateOf: (candidate) => candidate.capturedAt,
      );
      _pager = pager;
      unawaited(_loadNext(pager));
    }
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
                    child: GridView.builder(
                      key: const Key('screenshot-thumbnail-grid'),
                      controller: _scrollController,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
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
                                    color: Theme.of(context).colorScheme.surface
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _PhotosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.canReadMedia && widget.canReadMedia) ||
        oldWidget.repository != widget.repository) {
      _pager = null;
    }
    _ensureLoaded();
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
            'camera' => source == 'Camera',
            'saved' => source != 'Camera',
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
                : GridView.builder(
                    key: const Key('photos-thumbnail-grid'),
                    controller: _scrollController,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _showMediaItem(
                            context,
                            record,
                            widget.repository,
                          ),
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
      (label: strings.text('archives'), kind: AndroidMediaKind.documents),
      (label: 'APK', kind: AndroidMediaKind.documents),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          strings.text('storageTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
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
          title: const Text('Camera / Screenshots'),
          subtitle: Text(strings.text('inferred')),
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Downloads'),
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
        const SizedBox(height: 12),
        _InsightDetail(
          label: strings.text('type'),
          value: _categoryLabel(strings, record.category),
        ),
        _InsightDetail(
          label: strings.text('risk'),
          value: strings.text('reviewRisk'),
        ),
        _InsightDetail(label: strings.text('confidence'), value: '80%'),
        _InsightDetail(
          label: strings.text('bytes'),
          value: '${record.sizeBytes}',
        ),
        _InsightDetail(
          label: strings.text('captured'),
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
        _InsightDetail(
          label: strings.text('screenshotFlag'),
          value: strings.text(
            record.category == VirtualCategory.screenshots ? 'yes' : 'no',
          ),
        ),
        _InsightDetail(
          label: strings.text('duplicateState'),
          value: record.hashState == HashState.complete
              ? strings.text('reviewRisk')
              : strings.text('notCalculated'),
        ),
        const SizedBox(height: 8),
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
};

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

void _showMediaItem(
  BuildContext context,
  FileRecord record,
  MobileRepository repository,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final strings = MobileLocalizations.of(sheetContext);
      return FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          children: [
            ListTile(
              key: const Key('media-item-details'),
              leading: Icon(_iconFor(record.category)),
              title: Text(record.displayName),
              subtitle: Text(
                '${record.mimeType} · ${_formatBytes(record.sizeBytes)}\n'
                '${_formatDateTime(record.createdAt ?? record.modifiedAt)} · '
                '${_sourceKindLabel(strings, record.sourceKind)}',
              ),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            Expanded(child: _MobileInsightPanel(record: record)),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final opened = await repository.open(record);
                    if (!sheetContext.mounted) return;
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          strings.text(opened ? 'opened' : 'noViewer'),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(strings.text('open')),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

void _showScreenshotItem(
  BuildContext context,
  FileRecord record,
  MobileScreenshotGroup group,
  ScreenshotReviewState state,
  MobileRepository repository,
  void Function(FileRecord, ScreenshotReviewState) onMark,
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
              child: _OnDemandThumbnail(
                repository: repository,
                record: record,
                maxWidth: 320,
                maxHeight: 240,
                fallbackIcon: Icons.screenshot_monitor_outlined,
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
                    TextButton.icon(
                      onPressed: () async {
                        final opened = await repository.open(record);
                        if (!sheetContext.mounted) return;
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              strings.text(opened ? 'opened' : 'noViewer'),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.open_in_new),
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
