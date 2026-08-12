import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_insight_engine/picklogic_insight_engine.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

import 'src/incremental_index_queue.dart';
import 'src/mobile_repository.dart';
import 'src/screenshot_grouping.dart';

void main() =>
    runApp(PickLogicMobileApp(repository: AndroidMobileRepository()));

final class PickLogicMobileApp extends StatelessWidget {
  const PickLogicMobileApp({
    super.key,
    this.repository = const SyntheticMobileRepository(),
  });

  final MobileRepository repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PickLogic Mobile',
    theme: PickLogicTokens.lightTheme(),
    darkTheme: PickLogicTokens.darkTheme(),
    locale: const Locale('zh'),
    supportedLocales: PickLogicLocalizations.supportedLocales,
    localizationsDelegates: const [
      PickLogicLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MobileShell(repository: repository),
  );
}

final class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.repository});

  final MobileRepository repository;

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
        const SnackBar(content: Text('媒体权限检查未完成；PickLogic 未读取任何媒体或文件。')),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('目录只读授权已保存；未移动或修改任何文件。')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未获得目录只读授权。')));
    }
  }

  Future<void> _startSearch() async {
    final record = await showSearch<FileRecord?>(
      context: context,
      delegate: _MobileSearchDelegate(widget.repository),
    );
    if (record != null && mounted) {
      _showInsight(context, record, widget.repository);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = PickLogicLocalizations.of(context);
    return FutureBuilder<MobileBootstrapState>(
      future: _bootstrap,
      builder: (context, snapshot) {
        final bootstrap = snapshot.data;
        final canReadMedia = bootstrap?.permissions.canReadImages ?? false;
        final pages = <Widget>[
          _FilesPage(
            repository: widget.repository,
            active: _index == 0,
            canReadMedia: canReadMedia,
            onRequestAccess: _requestMediaAccess,
            onChooseTree: _chooseDocumentTree,
          ),
          _ScreenshotsPage(
            repository: widget.repository,
            active: _index == 1,
            canReadMedia: canReadMedia,
          ),
          _PhotosPage(
            repository: widget.repository,
            active: _index == 2,
            canReadMedia: canReadMedia,
          ),
          _StoragePage(
            bootstrap: bootstrap,
            repository: widget.repository,
            active: _index == 3,
          ),
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('PickLogic · 拾理'),
            actions: [
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
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.folder_outlined),
                label: strings.text('files'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.screenshot_outlined),
                label: strings.text('screenshots'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.photo_library_outlined),
                label: strings.text('photos'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.storage_outlined),
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
  Widget build(BuildContext context) => Center(
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
              '本地平台能力暂时不可用',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'PickLogic 未读取任何媒体或文件。请重试；若仍失败，请重新启动应用。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('mobile-bootstrap-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试本地初始化'),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _FilesPage extends StatefulWidget {
  const _FilesPage({
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
  State<_FilesPage> createState() => _FilesPageState();
}

final class _FilesPageState extends State<_FilesPage> {
  Future<List<FileRecord>>? _records;

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _FilesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.canReadMedia && widget.canReadMedia) _records = null;
    _ensureLoaded();
  }

  void _ensureLoaded() {
    if (widget.active && widget.canReadMedia && _records == null) {
      _records = widget.repository.loadMedia(AndroidMediaKind.documents);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('最近 · Recent', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('元数据按页读取；不会在首屏加载完整文件。'),
      const SizedBox(height: 12),
      if (!widget.canReadMedia)
        _AccessRequired(
          onRequestAccess: widget.onRequestAccess,
          onChooseTree: widget.onChooseTree,
        )
      else
        _RecordList(future: _records, repository: widget.repository),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: widget.onChooseTree,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('选择可访问目录（SAF，只读）'),
      ),
    ],
  );
}

final class _RecordList extends StatelessWidget {
  const _RecordList({required this.future, required this.repository});

  final Future<List<FileRecord>>? future;
  final MobileRepository repository;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FileRecord>>(
    future: future,
    builder: (context, snapshot) {
      if (future == null) return const Text('进入页面后按需加载。');
      if (snapshot.hasError) {
        return const Text('此集合当前不可访问；可改用 SAF 选择共享目录。');
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      if (snapshot.data!.isEmpty) return const Text('当前页没有可访问项目。');
      return Column(
        children: [
          for (final record in snapshot.data!)
            Card(
              child: ListTile(
                leading: Icon(_iconFor(record.category)),
                title: Text(record.displayName),
                subtitle: Text(
                  '${record.category.name} · ${_formatBytes(record.sizeBytes)}',
                ),
                onTap: () => _showInsight(context, record, repository),
              ),
            ),
        ],
      );
    },
  );
}

final class _ScreenshotsPage extends StatefulWidget {
  const _ScreenshotsPage({
    required this.repository,
    required this.active,
    required this.canReadMedia,
  });

  final MobileRepository repository;
  final bool active;
  final bool canReadMedia;

  @override
  State<_ScreenshotsPage> createState() => _ScreenshotsPageState();
}

final class _ScreenshotsPageState extends State<_ScreenshotsPage> {
  final PageController _controller = PageController();
  final Map<String, ScreenshotReviewState> _review = {};
  Future<List<MobileScreenshotGroup>>? _groups;

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _ScreenshotsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.canReadMedia && widget.canReadMedia) _groups = null;
    _ensureLoaded();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (widget.active && widget.canReadMedia && _groups == null) {
      _groups = widget.repository.loadScreenshotGroups();
    }
  }

  void _mark(FileRecord record, ScreenshotReviewState state) {
    setState(() => _review[record.id] = state);
    final label = switch (state) {
      ScreenshotReviewState.keep => '保留',
      ScreenshotReviewState.deleteReview => '加入删除审查',
      ScreenshotReviewState.later => '稍后',
      ScreenshotReviewState.protected => '已保护',
      ScreenshotReviewState.unreviewed => '尚未判断',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
    _controller.nextPage(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canReadMedia) {
      return const Center(child: Text('授予媒体只读权限后显示截图；不会自动 OCR。'));
    }
    if (_groups == null) {
      return const Center(child: Text('进入截图页后按需加载。'));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('截图时间线', style: Theme.of(context).textTheme.titleLarge),
          const Text('按时间与来源线索连续分组；来源线索不是应用归属结论。'),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<MobileScreenshotGroup>>(
              future: _groups,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('当前无法读取截图集合。');
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final groups = snapshot.data!;
                if (groups.isEmpty) {
                  return const Center(child: Text('没有可访问截图。'));
                }
                final entries = <_ScreenshotPageEntry>[
                  for (final group in groups)
                    for (final record in group.records)
                      _ScreenshotPageEntry(group: group, record: record),
                ];
                return PageView.builder(
                  controller: _controller,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final record = entry.record;
                    final group = entry.group.summary;
                    final state =
                        _review[record.id] ?? ScreenshotReviewState.unreviewed;
                    return GestureDetector(
                      onVerticalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) < -250) {
                          _mark(record, ScreenshotReviewState.later);
                        }
                      },
                      child: Dismissible(
                        key: ValueKey(record.id),
                        direction: DismissDirection.horizontal,
                        confirmDismiss: (direction) async {
                          _mark(
                            record,
                            direction == DismissDirection.startToEnd
                                ? ScreenshotReviewState.keep
                                : ScreenshotReviewState.deleteReview,
                          );
                          return false;
                        },
                        child: Card(
                          child: InkWell(
                            onTap: () => _showInsight(
                              context,
                              record,
                              widget.repository,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _OnDemandThumbnail(
                                      repository: widget.repository,
                                      record: record,
                                      maxWidth: 320,
                                      maxHeight: 240,
                                      fallbackIcon:
                                          Icons.screenshot_monitor_outlined,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    record.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '来源线索：${group.sourceHint}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${_formatDateTime(record.createdAt ?? record.modifiedAt)} · '
                                    '${group.memberIds.length > 1 ? '连续 ${group.memberIds.length} 张' : '单张'}',
                                  ),
                                  Text(
                                    state == ScreenshotReviewState.unreviewed
                                        ? '尚未判断 · 未运行 OCR'
                                        : state.name,
                                  ),
                                  IconButton(
                                    tooltip: '保护/保留',
                                    onPressed: () => _mark(
                                      record,
                                      ScreenshotReviewState.protected,
                                    ),
                                    icon: const Icon(Icons.shield_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('← 加入删除审查'), Text('↑ 稍后'), Text('保留 →')],
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
  });

  final MobileRepository repository;
  final bool active;
  final bool canReadMedia;

  @override
  State<_PhotosPage> createState() => _PhotosPageState();
}

final class _PhotosPageState extends State<_PhotosPage> {
  Future<List<FileRecord>>? _records;

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _PhotosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.canReadMedia && widget.canReadMedia) _records = null;
    _ensureLoaded();
  }

  void _ensureLoaded() {
    if (widget.active && widget.canReadMedia && _records == null) {
      _records = widget.repository.loadMedia(AndroidMediaKind.photos);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canReadMedia) {
      return const Center(child: Text('媒体权限未开启；PickLogic 不会读取照片。'));
    }
    if (_records == null) {
      return const Center(child: Text('进入照片页后按需加载。'));
    }
    return FutureBuilder<List<FileRecord>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('当前无法读取照片集合。'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final record = snapshot.data![index];
            return Card(
              child: InkWell(
                onTap: () => _showInsight(context, record, widget.repository),
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
        );
      },
    );
  }
}

final class _ScreenshotPageEntry {
  const _ScreenshotPageEntry({required this.group, required this.record});

  final MobileScreenshotGroup group;
  final FileRecord record;
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
    final storage = widget.bootstrap?.storage;
    if (storage == null) {
      return const Center(child: Text('正在读取系统存储摘要…'));
    }
    final used = storage.totalBytes - storage.availableBytes;
    final fraction = storage.totalBytes == 0 ? 0.0 : used / storage.totalBytes;
    final queue = widget.repository.indexQueueSnapshot;
    final visualAccess = widget.bootstrap!.permissions.partialVisualAccess
        ? '仅限用户选择的照片和视频'
        : storage.canInspectSharedMedia
        ? '仅限已授权的 MediaStore 集合'
        : '尚未授权，无法检查';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Storage Insight', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _StorageTile(
          '设备数据卷已用空间（系统聚合）',
          fraction.clamp(0, 1),
          true,
          '${_formatBytes(used)} / ${_formatBytes(storage.totalBytes)}；'
              '不可据此归因到文件或应用',
        ),
        _StorageTile(
          '共享媒体可见范围',
          storage.canInspectSharedMedia ? 1 : 0,
          storage.canInspectSharedMedia,
          visualAccess,
        ),
        _StorageTile(
          '下载、安装包与压缩包',
          0,
          storage.canInspectDownloads,
          storage.canInspectDownloads
              ? '仅统计 MediaStore/SAF 可见项'
              : '需要用户通过 SAF 选择目录',
        ),
        _StorageTile(
          '后台增量元数据队列',
          queue.isRunning ? null : 0,
          true,
          queue.persistsAcrossRestarts
              ? '已索引 ${queue.indexedItems} 项；完成 ${queue.completedBatches} 批；'
                    '失败 ${queue.failedBatches} 批；SQLite 检查点可恢复；不调度 OCR'
              : '已索引 ${queue.indexedItems} 项；完成 ${queue.completedBatches} 批；'
                    '当前会话状态；不调度 OCR',
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
                  ? '暂停索引'
                  : queue.isPaused
                  ? '继续索引'
                  : '检查新增内容',
            ),
          ),
        ),
        const _StorageTile('其他应用私有数据', 0, false, '平台限制'),
        const SizedBox(height: 16),
        Text('明确限制', style: Theme.of(context).textTheme.titleMedium),
        Text('• ${storage.systemRestriction}'),
        const Text('• 系统聚合值包含 PickLogic 无法枚举或归因的数据。'),
        const Text('• 不读取其他应用私有目录，不估算其内容，不提供清理按钮。'),
        const Text('• 仅处理按页返回的元数据；缩略图在可见时按需读取。'),
        for (final limitation in storage.limitations) Text('• $limitation'),
        const SizedBox(height: 8),
        const Text('可使用 SAF 查看用户明确选择的共享目录；任何媒体操作仍需另行预览与确认。'),
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
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail),
        LinearProgressIndicator(value: value),
      ],
    ),
    trailing: Icon(
      inspectable ? Icons.visibility_outlined : Icons.lock_outline,
    ),
  );
}

final class _AccessRequired extends StatelessWidget {
  const _AccessRequired({
    required this.onRequestAccess,
    required this.onChooseTree,
  });

  final VoidCallback onRequestAccess;
  final VoidCallback onChooseTree;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('尚未获得媒体只读权限。'),
          const Text('首屏保持可用；不会在后台绕过 Android scoped storage。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: onRequestAccess,
                child: const Text('选择媒体权限'),
              ),
              OutlinedButton(
                onPressed: onChooseTree,
                child: const Text('选择共享目录'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

final class _MobileSearchDelegate extends SearchDelegate<FileRecord?> {
  _MobileSearchDelegate(this.repository);

  final MobileRepository repository;

  @override
  String get searchFieldLabel => '按名称、类型或分类搜索';

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
      ? const Center(child: Text('输入至少两个字符；仅搜索本地元数据。'))
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
      if (snapshot.hasError) return const Center(child: Text('当前索引不可访问。'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.data!.isEmpty) return const Center(child: Text('没有匹配结果。'));
      return ListView.builder(
        itemCount: snapshot.data!.length,
        itemBuilder: (context, index) {
          final record = snapshot.data![index];
          return ListTile(
            leading: Icon(_iconFor(record.category)),
            title: Text(record.displayName),
            subtitle: Text(record.category.name),
            onTap: () => onSelected(record),
          );
        },
      );
    },
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

void _showInsight(
  BuildContext context,
  FileRecord record,
  MobileRepository repository,
) {
  final insight = const BasicInsightEngine().explainFile(record);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.72,
      child: Column(
        children: [
          Expanded(child: InsightPanel(insight: insight)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () async {
                  final opened = await repository.open(record);
                  if (!sheetContext.mounted) return;
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(content: Text(opened ? '已交给系统打开' : '没有可用的打开方式')),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
