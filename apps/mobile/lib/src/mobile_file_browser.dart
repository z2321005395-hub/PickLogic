import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_classification_rules/picklogic_classification_rules.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

import 'mobile_internal_viewer.dart';
import 'mobile_folder_insight.dart';
import 'mobile_repository.dart';

enum _BrowserSort { name, modified, size }

/// Hierarchical, read-only SAF browser for user-selected Android folders.
final class MobileFileBrowserPage extends StatefulWidget {
  const MobileFileBrowserPage({
    super.key,
    required this.repository,
    this.initialRoot,
  });

  final MobileRepository repository;
  final AndroidBrowseRoot? initialRoot;

  @override
  State<MobileFileBrowserPage> createState() => _MobileFileBrowserPageState();
}

final class _MobileFileBrowserPageState extends State<MobileFileBrowserPage> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Location> _trail = <_Location>[];
  final List<AndroidBrowseEntry> _items = <AndroidBrowseEntry>[];
  late Future<List<AndroidBrowseRoot>> _roots;
  AndroidBrowseRoot? _root;
  AndroidBrowsePage? _page;
  bool _loading = false;
  Object? _error;
  bool _grid = false;
  _BrowserSort _sort = _BrowserSort.name;

  bool get _chinese => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    _roots = widget.repository.loadBrowseRoots();
    _scroll.addListener(_onScroll);
    if (widget.initialRoot case final root?) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRoot(root));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 500 && (_page?.hasMore ?? false)) {
      unawaited(_loadDirectory(loadMore: true));
    }
  }

  Future<void> _addRoot() async {
    final selected = await widget.repository.chooseDocumentTree();
    if (!mounted || selected == null) return;
    setState(() => _roots = widget.repository.loadBrowseRoots());
    final roots = await _roots;
    if (!mounted) return;
    final root = roots.where((item) => item.treeUri == selected).firstOrNull;
    if (root != null) await _openRoot(root);
  }

  Future<void> _openRoot(AndroidBrowseRoot root) async {
    _root = root;
    _trail
      ..clear()
      ..add(_Location(name: root.displayName, documentUri: root.documentUri));
    await _loadDirectory();
  }

  Future<void> _openDirectory(AndroidBrowseEntry entry) async {
    _trail.add(
      _Location(name: entry.displayName, documentUri: entry.documentUri),
    );
    await _loadDirectory();
  }

  Future<void> _goToTrail(int index) async {
    if (index < 0 || index >= _trail.length) return;
    _trail.removeRange(index + 1, _trail.length);
    await _loadDirectory();
  }

  Future<void> _loadDirectory({bool loadMore = false}) async {
    final root = _root;
    if (root == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!loadMore) {
        _items.clear();
        _page = null;
      }
    });
    try {
      final next = await widget.repository.loadBrowseDirectory(
        treeUri: root.treeUri,
        directoryUri: _trail.last.documentUri,
        offset: loadMore ? _items.length : 0,
      );
      if (!mounted) return;
      setState(() {
        if (next != null) {
          _page = next;
          final known = _items.map((item) => item.documentUri).toSet();
          _items.addAll(
            next.items.where((item) => known.add(item.documentUri)),
          );
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openFile(AndroidBrowseEntry entry) {
    final visible = _visibleItems
        .where((item) => !item.directory)
        .map(_recordFor)
        .toList(growable: false);
    final record = _recordFor(entry);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MobileViewerPage(
          records: visible,
          initialRecord: record,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _showRootInsight(AndroidBrowseRoot root) =>
      showAndroidFolderInsightSheet(
        context: context,
        repository: widget.repository,
        root: root,
        directoryUri: root.documentUri,
        displayName: root.displayName,
        pathSegments: <String>[root.displayName],
      );

  Future<void> _showDirectoryInsight(AndroidBrowseEntry entry) {
    final root = _root;
    if (root == null) return Future<void>.value();
    return showAndroidFolderInsightSheet(
      context: context,
      repository: widget.repository,
      root: root,
      directoryUri: entry.documentUri,
      displayName: entry.displayName,
      pathSegments: <String>[
        ..._trail.map((location) => location.name),
        entry.displayName,
      ],
    );
  }

  List<AndroidBrowseEntry> get _visibleItems {
    final query = _search.text.trim().toLowerCase();
    final visible = _items
        .where(
          (item) =>
              query.isEmpty || item.displayName.toLowerCase().contains(query),
        )
        .toList(growable: false);
    visible.sort((a, b) {
      final folderOrder = b.directory.toString().compareTo(
        a.directory.toString(),
      );
      if (folderOrder != 0) return folderOrder;
      return switch (_sort) {
        _BrowserSort.name => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ),
        _BrowserSort.modified => b.modifiedAt.compareTo(a.modifiedAt),
        _BrowserSort.size => b.sizeBytes.compareTo(a.sizeBytes),
      };
    });
    return visible;
  }

  FileRecord _recordFor(AndroidBrowseEntry entry) {
    final extension = _extension(entry.displayName);
    final locator = FileLocator(
      value: entry.documentUri,
      sourceKind: SourceKind.storageAccessFramework,
      platform: PickLogicPlatform.android,
    );
    final parent = FileLocator(
      value: entry.parentUri,
      sourceKind: SourceKind.storageAccessFramework,
      platform: PickLogicPlatform.android,
    );
    return RuleClassificationEngine().classify(
      FileRecord(
        id: 'saf:${entry.documentUri}',
        locator: locator,
        displayName: entry.displayName,
        extension: extension,
        mimeType: entry.mimeType,
        sizeBytes: entry.sizeBytes,
        createdAt: null,
        modifiedAt: entry.modifiedAt,
        parentLocator: parent,
        sourceKind: SourceKind.storageAccessFramework,
        platform: PickLogicPlatform.android,
        isHidden: entry.displayName.startsWith('.'),
        isSystem: false,
        isAccessible: true,
        isProtected: false,
        category: VirtualCategory.unknown,
        hashState: HashState.notRequested,
        ocrState: OcrState.notRequested,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('mobile-saf-file-browser'),
    appBar: AppBar(
      title: Text(_chinese ? '文件夹浏览' : 'Folder browser'),
      actions: [
        IconButton(
          key: const Key('mobile-browser-add-root'),
          tooltip: _chinese ? '添加文件夹' : 'Add folder',
          onPressed: _addRoot,
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
        IconButton(
          tooltip: _grid
              ? (_chinese ? '列表视图' : 'List view')
              : (_chinese ? '网格视图' : 'Grid view'),
          onPressed: () => setState(() => _grid = !_grid),
          icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view),
        ),
      ],
    ),
    body: _root == null ? _buildRoots() : _buildDirectory(),
  );

  Widget _buildRoots() => FutureBuilder<List<AndroidBrowseRoot>>(
    future: _roots,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final roots = snapshot.data ?? const <AndroidBrowseRoot>[];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _chinese
                ? '选择已授权文件夹，像普通文件管理器一样逐层浏览。PickLogic 只读取内容，不会修改真实文件。'
                : 'Open an authorized folder and browse it hierarchically. PickLogic reads content without modifying real files.',
          ),
          const SizedBox(height: 12),
          for (final root in roots)
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(root.displayName),
                subtitle: Text(
                  _chinese ? '已授权 · 只读' : 'Authorized · read-only',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _chinese ? '解释此文件夹' : 'Explain folder',
                      onPressed: () => _showRootInsight(root),
                      icon: const Icon(Icons.info_outline),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _openRoot(root),
              ),
            ),
          if (roots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(_chinese ? '尚未添加文件夹' : 'No folders added yet'),
              ),
            ),
          FilledButton.icon(
            onPressed: _addRoot,
            icon: const Icon(Icons.add),
            label: Text(_chinese ? '添加文件夹' : 'Add folder'),
          ),
        ],
      );
    },
  );

  Widget _buildDirectory() {
    final visible = _visibleItems;
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: _chinese ? '返回授权目录' : 'Back to roots',
                onPressed: () => setState(() {
                  _root = null;
                  _trail.clear();
                  _items.clear();
                }),
                icon: const Icon(Icons.storage_outlined),
              ),
              for (var index = 0; index < _trail.length; index++) ...[
                if (index > 0) const Icon(Icons.chevron_right, size: 18),
                TextButton(
                  onPressed: () => _goToTrail(index),
                  child: Text(_trail[index].name),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('mobile-browser-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: _chinese ? '在当前文件夹搜索' : 'Search this folder',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_BrowserSort>(
                tooltip: _chinese ? '排序' : 'Sort',
                initialValue: _sort,
                onSelected: (value) => setState(() => _sort = value),
                icon: const Icon(Icons.sort),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _BrowserSort.name,
                    child: Text(_chinese ? '名称' : 'Name'),
                  ),
                  PopupMenuItem(
                    value: _BrowserSort.modified,
                    child: Text(_chinese ? '修改时间' : 'Modified'),
                  ),
                  PopupMenuItem(
                    value: _BrowserSort.size,
                    child: Text(_chinese ? '大小' : 'Size'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_loading && _items.isEmpty) const LinearProgressIndicator(),
        if (_error != null)
          MaterialBanner(
            content: Text(
              _chinese ? '无法读取此文件夹。' : 'This folder could not be read.',
            ),
            actions: [
              TextButton(
                onPressed: _loadDirectory,
                child: Text(_chinese ? '重试' : 'Retry'),
              ),
            ],
          ),
        Expanded(
          child: visible.isEmpty && !_loading
              ? Center(
                  child: Text(_chinese ? '此文件夹为空' : 'This folder is empty'),
                )
              : _grid
              ? GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 150,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final entry = visible[index];
                    return _GridEntry(
                      entry: entry,
                      record: entry.directory ? null : _recordFor(entry),
                      repository: widget.repository,
                      onTap: () => entry.directory
                          ? _openDirectory(entry)
                          : _openFile(entry),
                      onInsight: entry.directory
                          ? () => _showDirectoryInsight(entry)
                          : null,
                    );
                  },
                )
              : ListView.builder(
                  controller: _scroll,
                  itemCount: visible.length + (_loading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == visible.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final entry = visible[index];
                    return ListTile(
                      leading: SizedBox.square(
                        dimension: 48,
                        child: entry.directory
                            ? Icon(_iconFor(entry))
                            : _BrowserThumbnail(
                                entry: entry,
                                record: _recordFor(entry),
                                repository: widget.repository,
                              ),
                      ),
                      title: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.directory
                            ? (_chinese ? '文件夹' : 'Folder')
                            : '${_browserBytes(entry.sizeBytes)} · ${_shortDate(entry.modifiedAt)}',
                      ),
                      trailing: entry.directory
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: ValueKey<String>(
                                    'folder-insight-${entry.documentUri}',
                                  ),
                                  tooltip: _chinese
                                      ? '解释此文件夹'
                                      : 'Explain folder',
                                  onPressed: () => _showDirectoryInsight(entry),
                                  icon: const Icon(Icons.info_outline),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            )
                          : null,
                      onTap: () => entry.directory
                          ? _openDirectory(entry)
                          : _openFile(entry),
                    );
                  },
                ),
        ),
        if (_page?.hasMore == true && !_loading)
          TextButton(
            onPressed: () => _loadDirectory(loadMore: true),
            child: Text(_chinese ? '加载更多' : 'Load more'),
          ),
      ],
    );
  }
}

final class _GridEntry extends StatelessWidget {
  const _GridEntry({
    required this.entry,
    required this.record,
    required this.repository,
    required this.onTap,
    this.onInsight,
  });

  final AndroidBrowseEntry entry;
  final FileRecord? record;
  final MobileRepository repository;
  final VoidCallback onTap;
  final VoidCallback? onInsight;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    onLongPress: onInsight,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 64,
            child: entry.directory || record == null
                ? Icon(_iconFor(entry), size: 48)
                : _BrowserThumbnail(
                    entry: entry,
                    record: record!,
                    repository: repository,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            entry.displayName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

final class _BrowserThumbnail extends StatelessWidget {
  const _BrowserThumbnail({
    required this.entry,
    required this.record,
    required this.repository,
  });

  final AndroidBrowseEntry entry;
  final FileRecord record;
  final MobileRepository repository;

  bool get _supportsThumbnail =>
      entry.mimeType.startsWith('image/') ||
      entry.mimeType.startsWith('video/');

  @override
  Widget build(BuildContext context) {
    if (!_supportsThumbnail) return Icon(_iconFor(entry));
    return FutureBuilder<Uint8List?>(
      future: repository.loadThumbnail(record, maxWidth: 160, maxHeight: 160),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return Icon(_iconFor(entry));
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Icon(_iconFor(entry)),
          ),
        );
      },
    );
  }
}

final class _Location {
  const _Location({required this.name, required this.documentUri});

  final String name;
  final String documentUri;
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 || dot == name.length - 1
      ? ''
      : name.substring(dot + 1).toLowerCase();
}

IconData _iconFor(AndroidBrowseEntry entry) {
  if (entry.directory) return Icons.folder_outlined;
  final mime = entry.mimeType;
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.video_file_outlined;
  if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime.contains('zip') || mime.contains('archive')) {
    return Icons.archive_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _browserBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
