import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

import 'mobile_localizations.dart';
import 'mobile_repository.dart';
import 'mobile_trash_controller.dart';

final Set<String> _viewerFavoriteIds = <String>{};
final Set<String> _viewerReviewIds = <String>{};

enum MobileInternalViewerKind {
  image,
  video,
  audio,
  pdf,
  text,
  archive,
  apk,
  office,
  unsupported,
}

MobileInternalViewerKind mobileViewerKind(FileRecord record) {
  final extension = record.extension.toLowerCase();
  final mime = record.mimeType.toLowerCase();
  if (mime.startsWith('image/') || _images.contains(extension)) {
    return MobileInternalViewerKind.image;
  }
  if (mime.startsWith('video/') || _videos.contains(extension)) {
    return MobileInternalViewerKind.video;
  }
  if (mime.startsWith('audio/') || _audio.contains(extension)) {
    return MobileInternalViewerKind.audio;
  }
  if (mime == 'application/pdf' || extension == 'pdf') {
    return MobileInternalViewerKind.pdf;
  }
  if (mime.startsWith('text/') || _text.contains(extension)) {
    return MobileInternalViewerKind.text;
  }
  if (extension == 'zip' || mime == 'application/zip') {
    return MobileInternalViewerKind.archive;
  }
  if (extension == 'apk' || mime == 'application/vnd.android.package-archive') {
    return MobileInternalViewerKind.apk;
  }
  if (_office.contains(extension)) return MobileInternalViewerKind.office;
  return MobileInternalViewerKind.unsupported;
}

bool supportsMobileInternalViewer(FileRecord record) =>
    mobileViewerKind(record) != MobileInternalViewerKind.unsupported;

Future<bool> confirmMobileSystemTrash(
  BuildContext context, {
  required FileRecord record,
  required MobileRepository repository,
}) async {
  const controller = MobileTrashController();
  final strings = MobileLocalizations.of(context);
  final chinese = strings.locale.languageCode == 'zh';
  if (!controller.canMoveToSystemTrash(record)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          chinese
              ? '此项目是受保护、未知或只读来源，不能从 PickLogic 直接移到回收站。'
              : 'This item is protected, unknown, or from a read-only source and cannot be trashed by PickLogic.',
        ),
      ),
    );
    return false;
  }

  final preview = controller.preview(record);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('mobile-trash-operation-preview'),
      title: Text(strings.text('systemTrash')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            record.displayName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text('${_viewerBytes(record.sizeBytes)} · ${record.mimeType}'),
          const SizedBox(height: 12),
          Text(strings.text('systemTrashConfirmDetail')),
          const SizedBox(height: 8),
          Text(
            chinese
                ? '该操作不会永久删除；可在 Android 系统回收站保留期内恢复。'
                : 'This is not a permanent delete; the item can be restored while Android retains it in system trash.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(strings.text('cancel')),
        ),
        FilledButton.icon(
          key: const Key('confirm-mobile-system-trash'),
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.delete_outline),
          label: Text(strings.text('continueAction')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final result = await controller.execute(
    confirmedPlan: preview.transitionTo(OperationStatus.confirmed),
    requester: (_) => repository.requestSystemTrash(<FileRecord>[record]),
  );
  if (!context.mounted) return result.success;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        strings.text(
          result.success ? 'systemTrashDone' : 'systemTrashCancelled',
        ),
      ),
    ),
  );
  return result.success;
}

/// First-class file opener used by collections and the SAF folder browser.
///
/// The content occupies the page; metadata and Insight are secondary actions
/// rather than a mandatory intermediate screen. Adjacent items can be swiped
/// without returning to the file list.
final class MobileViewerPage extends StatefulWidget {
  const MobileViewerPage({
    super.key,
    required this.records,
    required this.initialRecord,
    required this.repository,
  });

  final List<FileRecord> records;
  final FileRecord initialRecord;
  final MobileRepository repository;

  @override
  State<MobileViewerPage> createState() => _MobileViewerPageState();
}

final class _MobileViewerPageState extends State<MobileViewerPage> {
  late final List<FileRecord> _records = widget.records.isEmpty
      ? <FileRecord>[widget.initialRecord]
      : List<FileRecord>.unmodifiable(widget.records);
  late int _index = _records.indexWhere(
    (record) => record.id == widget.initialRecord.id,
  );
  late final PageController _pages = PageController(
    initialPage: _index < 0 ? 0 : _index,
  );
  bool _chromeVisible = true;

  FileRecord get _record => _records[_index < 0 ? 0 : _index];
  bool get _favorite => _viewerFavoriteIds.contains(_record.id);
  bool get _inReview => _viewerReviewIds.contains(_record.id);

  @override
  void initState() {
    super.initState();
    if (_index < 0) _index = 0;
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _openWithOtherApp() async {
    final strings = MobileLocalizations.of(context);
    final opened = await widget.repository.open(_record);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.text(opened ? 'opened' : 'noViewer'))),
    );
  }

  Future<void> _moveToSystemTrash() async {
    final record = _record;
    final moved = await confirmMobileSystemTrash(
      context,
      record: record,
      repository: widget.repository,
    );
    if (!mounted || !moved) return;
    _viewerFavoriteIds.remove(record.id);
    _viewerReviewIds.remove(record.id);
    if (Navigator.of(context).canPop()) Navigator.pop(context, true);
  }

  void _toggleFavorite() {
    setState(() {
      if (!_viewerFavoriteIds.add(_record.id)) {
        _viewerFavoriteIds.remove(_record.id);
      }
    });
  }

  void _toggleReview() {
    setState(() {
      if (!_viewerReviewIds.add(_record.id)) {
        _viewerReviewIds.remove(_record.id);
      }
    });
    final chinese = MobileLocalizations.of(context).locale.languageCode == 'zh';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _inReview
              ? (chinese
                    ? '已加入应用内删除审查；真实文件未修改。'
                    : 'Added to the in-app deletion review; the real file was not changed.')
              : (chinese
                    ? '已从删除审查移除；真实文件未修改。'
                    : 'Removed from deletion review; the real file was not changed.'),
        ),
      ),
    );
  }

  Future<void> _showInformation() async {
    final strings = MobileLocalizations.of(context);
    final record = _record;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              record.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh' ? '类型' : 'Type',
              value: record.mimeType,
            ),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh' ? '大小' : 'Size',
              value: _viewerBytes(record.sizeBytes),
            ),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh' ? '修改时间' : 'Modified',
              value: record.modifiedAt.toLocal().toString().split('.').first,
            ),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh' ? '位置' : 'Location',
              value: record.parentLocator?.value ?? record.locator.value,
            ),
            const Divider(height: 24),
            Text(
              strings.locale.languageCode == 'zh' ? '知件 · 解释' : 'Insight',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh' ? '分类' : 'Category',
              value: record.category.name,
            ),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh' ? '来源' : 'Source',
              value: record.sourceKind.name,
            ),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh'
                  ? '保护状态'
                  : 'Protection',
              value: record.isProtected
                  ? (strings.locale.languageCode == 'zh' ? '受保护' : 'Protected')
                  : (strings.locale.languageCode == 'zh'
                        ? '只读查看'
                        : 'Read-only view'),
            ),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh'
                  ? '本地标记'
                  : 'Local marks',
              value: <String>[
                if (_favorite)
                  strings.locale.languageCode == 'zh' ? '已收藏' : 'Favorite',
                if (_inReview)
                  strings.locale.languageCode == 'zh'
                      ? '删除审查'
                      : 'Deletion review',
                if (!_favorite && !_inReview)
                  strings.locale.languageCode == 'zh' ? '无' : 'None',
              ].join(' · '),
            ),
            _ViewerFact(
              label: strings.locale.languageCode == 'zh' ? '重复状态' : 'Duplicate',
              value: switch (record.hashState) {
                HashState.complete when record.sha256 != null =>
                  strings.locale.languageCode == 'zh' ? '已计算' : 'Calculated',
                HashState.hashing =>
                  strings.locale.languageCode == 'zh' ? '计算中' : 'Calculating',
                _ =>
                  strings.locale.languageCode == 'zh' ? '尚未判断' : 'Not checked',
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                strings.locale.languageCode == 'zh'
                    ? '事实来自平台元数据和本地规则；当前不会修改此文件。'
                    : 'Facts come from platform metadata and local rules; this file will not be modified.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _openWithOtherApp,
              icon: const Icon(Icons.open_in_new),
              label: Text(strings.text('openWithOtherApp')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMedia = switch (mobileViewerKind(_record)) {
      MobileInternalViewerKind.image || MobileInternalViewerKind.video => true,
      _ => false,
    };
    return Scaffold(
      key: const Key('mobile-first-class-viewer'),
      backgroundColor: isMedia ? Colors.black : null,
      appBar: _chromeVisible
          ? AppBar(
              backgroundColor: isMedia ? Colors.black87 : null,
              foregroundColor: isMedia ? Colors.white : null,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _record.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_records.length > 1)
                    Text(
                      '${_index + 1} / ${_records.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isMedia ? Colors.white70 : null,
                      ),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  key: const Key('mobile-viewer-favorite'),
                  tooltip:
                      MobileLocalizations.of(context).locale.languageCode ==
                          'zh'
                      ? (_favorite ? '取消收藏' : '收藏')
                      : (_favorite ? 'Remove favorite' : 'Favorite'),
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _favorite ? Icons.favorite : Icons.favorite_border,
                  ),
                ),
                IconButton(
                  key: const Key('mobile-viewer-review'),
                  tooltip:
                      MobileLocalizations.of(context).locale.languageCode ==
                          'zh'
                      ? (_inReview ? '移出删除审查' : '加入删除审查')
                      : (_inReview
                            ? 'Remove from deletion review'
                            : 'Add to deletion review'),
                  onPressed: _toggleReview,
                  icon: Icon(
                    _inReview ? Icons.rule_folder : Icons.rule_folder_outlined,
                  ),
                ),
                IconButton(
                  key: const Key('mobile-viewer-trash'),
                  tooltip:
                      const MobileTrashController().canMoveToSystemTrash(
                        _record,
                      )
                      ? MobileLocalizations.of(context).text('systemTrash')
                      : (MobileLocalizations.of(context).locale.languageCode ==
                                'zh'
                            ? '受保护、未知或只读来源不可删除'
                            : 'Protected, unknown, or read-only source'),
                  onPressed:
                      const MobileTrashController().canMoveToSystemTrash(
                        _record,
                      )
                      ? _moveToSystemTrash
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  key: const Key('mobile-viewer-information'),
                  tooltip:
                      MobileLocalizations.of(context).locale.languageCode ==
                          'zh'
                      ? '文件信息'
                      : 'File information',
                  onPressed: _showInformation,
                  icon: const Icon(Icons.info_outline),
                ),
                IconButton(
                  key: const Key('mobile-viewer-open-with'),
                  tooltip: MobileLocalizations.of(
                    context,
                  ).text('openWithOtherApp'),
                  onPressed: _openWithOtherApp,
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        child: PageView.builder(
          controller: _pages,
          itemCount: _records.length,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) => MobileInternalViewer(
            key: ValueKey('mobile-viewer-${_records[index].id}'),
            record: _records[index],
            repository: widget.repository,
          ),
        ),
      ),
    );
  }
}

final class _ViewerFact extends StatelessWidget {
  const _ViewerFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

String _viewerBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

final class MobileInternalViewer extends StatelessWidget {
  const MobileInternalViewer({
    super.key,
    required this.record,
    required this.repository,
  });

  final FileRecord record;
  final MobileRepository repository;

  @override
  Widget build(BuildContext context) {
    final chinese = MobileLocalizations.of(context).locale.languageCode == 'zh';
    return switch (mobileViewerKind(record)) {
      MobileInternalViewerKind.image => _ImageViewer(
        record: record,
        repository: repository,
      ),
      MobileInternalViewerKind.video => PickLogicMediaPlayer(
        source: PickLogicMediaSource.contentUri(record.locator.value),
        title: record.displayName,
        chinese: chinese,
      ),
      MobileInternalViewerKind.audio => PickLogicMediaPlayer(
        source: PickLogicMediaSource.contentUri(record.locator.value),
        title: record.displayName,
        chinese: chinese,
        audioOnly: true,
      ),
      MobileInternalViewerKind.pdf => _PdfViewer(
        record: record,
        repository: repository,
      ),
      MobileInternalViewerKind.text => _TextViewer(
        record: record,
        repository: repository,
      ),
      MobileInternalViewerKind.archive => _ArchiveViewer(
        record: record,
        repository: repository,
      ),
      MobileInternalViewerKind.apk => _ApkViewer(
        record: record,
        repository: repository,
      ),
      MobileInternalViewerKind.office => _OfficeViewer(
        record: record,
        repository: repository,
      ),
      MobileInternalViewerKind.unsupported => Center(
        key: const Key('mobile-viewer-unsupported'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            chinese
                ? 'PickLogic 暂无此格式的内部预览。可从“更多”使用其他应用打开。'
                : 'PickLogic does not yet have an internal viewer for this format. Use More to open it with another app.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    };
  }
}

final class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.record, required this.repository});

  final FileRecord record;
  final MobileRepository repository;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

final class _ImageViewerState extends State<_ImageViewer> {
  late Future<AndroidPreviewImage?> _preview;
  final TransformationController _transform = TransformationController();
  int _quarterTurns = 0;

  @override
  void initState() {
    super.initState();
    _preview = widget.repository.loadPreviewImage(widget.record);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    key: const Key('mobile-image-viewer'),
    children: [
      Positioned.fill(
        child: FutureBuilder<AndroidPreviewImage?>(
          future: _preview,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final bytes = snapshot.data?.bytes;
            if (bytes == null) {
              return const Center(child: Icon(Icons.broken_image_outlined));
            }
            return InteractiveViewer(
              transformationController: _transform,
              minScale: 0.5,
              maxScale: 8,
              child: Center(
                child: RotatedBox(
                  quarterTurns: _quarterTurns,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            );
          },
        ),
      ),
      Positioned(
        right: 8,
        bottom: 8,
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip:
                  MobileLocalizations.of(context).locale.languageCode == 'zh'
                  ? '重置缩放'
                  : 'Reset zoom',
              onPressed: () => _transform.value = Matrix4.identity(),
              icon: const Icon(Icons.center_focus_strong),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip:
                  MobileLocalizations.of(context).locale.languageCode == 'zh'
                  ? '顺时针旋转预览'
                  : 'Rotate preview clockwise',
              onPressed: () => setState(() => _quarterTurns += 1),
              icon: const Icon(Icons.rotate_right),
            ),
          ],
        ),
      ),
    ],
  );
}

final class _PdfViewer extends StatefulWidget {
  const _PdfViewer({required this.record, required this.repository});

  final FileRecord record;
  final MobileRepository repository;

  @override
  State<_PdfViewer> createState() => _PdfViewerState();
}

final class _PdfViewerState extends State<_PdfViewer> {
  late Future<AndroidPdfInfo?> _info;
  PageController? _pages;
  final Map<int, Future<AndroidPreviewImage?>> _renders = {};
  int _page = 0;
  bool _positionLoaded = false;

  @override
  void initState() {
    super.initState();
    _info = widget.repository.getPdfInfo(widget.record);
    _restorePosition();
  }

  Future<void> _restorePosition() async {
    final page = await widget.repository.loadPdfRecentPage(widget.record);
    if (!mounted) return;
    setState(() {
      _page = page;
      _pages = PageController(initialPage: page);
      _positionLoaded = true;
    });
  }

  @override
  void dispose() {
    widget.repository.savePdfRecentPage(widget.record, _page);
    _pages?.dispose();
    super.dispose();
  }

  Future<AndroidPreviewImage?> _render(int page) => _renders.putIfAbsent(
    page,
    () => widget.repository.renderPdfPage(
      widget.record,
      pageIndex: page,
      maxWidth: 1600,
      maxHeight: 2000,
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<AndroidPdfInfo?>(
    future: _info,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!_positionLoaded || _pages == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final pageCount = snapshot.data?.pageCount ?? 0;
      if (pageCount == 0) {
        return Center(
          key: const Key('mobile-pdf-error'),
          child: Text(
            MobileLocalizations.of(context).locale.languageCode == 'zh'
                ? '无法读取此 PDF。'
                : 'This PDF could not be read.',
          ),
        );
      }
      if (_page >= pageCount) {
        _page = pageCount - 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pages?.hasClients == true) _pages!.jumpToPage(_page);
          widget.repository.savePdfRecentPage(widget.record, _page);
        });
      }
      return Column(
        key: const Key('mobile-pdf-viewer'),
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages!,
              scrollDirection: Axis.vertical,
              itemCount: pageCount,
              onPageChanged: (value) {
                widget.repository.savePdfRecentPage(widget.record, value);
                setState(() => _page = value);
              },
              itemBuilder: (context, index) =>
                  FutureBuilder<AndroidPreviewImage?>(
                    future: _render(index),
                    builder: (context, page) {
                      final bytes = page.data?.bytes;
                      if (bytes == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return InteractiveViewer(
                        minScale: 0.75,
                        maxScale: 5,
                        child: Center(child: Image.memory(bytes)),
                      );
                    },
                  ),
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _page > 0
                      ? () => _pages!.previousPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                Text('${_page + 1} / $pageCount'),
                IconButton(
                  onPressed: _page + 1 < pageCount
                      ? () => _pages!.nextPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        )
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

final class _TextViewer extends StatefulWidget {
  const _TextViewer({required this.record, required this.repository});

  final FileRecord record;
  final MobileRepository repository;

  @override
  State<_TextViewer> createState() => _TextViewerState();
}

final class _TextViewerState extends State<_TextViewer> {
  late Future<AndroidTextPreview> _preview;
  String _query = '';
  bool _wrap = true;
  bool _lineNumbers = true;

  @override
  void initState() {
    super.initState();
    _preview = widget.repository.loadTextPreview(widget.record);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AndroidTextPreview>(
    future: _preview,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final preview = snapshot.data!;
      final source = preview.text;
      final matchCount = _query.isEmpty
          ? 0
          : RegExp(
              RegExp.escape(_query),
              caseSensitive: false,
            ).allMatches(source).length;
      final displayed = _lineNumbers
          ? source
                .split('\n')
                .indexed
                .map((line) => '${line.$1 + 1}\t${line.$2}')
                .join('\n')
          : source;
      final chinese =
          MobileLocalizations.of(context).locale.languageCode == 'zh';
      return Column(
        key: const Key('mobile-text-viewer'),
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: chinese ? '在文本中查找' : 'Find in text',
                      suffixText: _query.isEmpty ? null : '$matchCount',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                IconButton(
                  tooltip: chinese ? '复制全部' : 'Copy all',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: source)),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                IconButton(
                  tooltip: chinese ? '自动换行' : 'Word wrap',
                  onPressed: () => setState(() => _wrap = !_wrap),
                  icon: Icon(_wrap ? Icons.wrap_text : Icons.short_text),
                ),
                IconButton(
                  tooltip: chinese ? '行号' : 'Line numbers',
                  onPressed: () => setState(() => _lineNumbers = !_lineNumbers),
                  icon: const Icon(Icons.format_list_numbered),
                ),
              ],
            ),
          ),
          if (preview.truncated)
            MaterialBanner(
              content: Text(
                chinese
                    ? '只显示前 256K 字符，原文件未被完整载入内存。'
                    : 'Showing the first 256K characters; the whole file was not loaded into memory.',
              ),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: _wrap ? Axis.vertical : Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                displayed,
                style: const TextStyle(fontFamily: 'monospace', height: 1.45),
              ),
            ),
          ),
        ],
      );
    },
  );
}

final class _ArchiveViewer extends StatelessWidget {
  const _ArchiveViewer({required this.record, required this.repository});

  final FileRecord record;
  final MobileRepository repository;

  @override
  Widget build(BuildContext context) => FutureBuilder<AndroidArchiveListing>(
    future: repository.listArchive(record),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final listing = snapshot.data!;
      return Column(
        key: const Key('mobile-archive-viewer'),
        children: [
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text('${listing.totalEntries} entries'),
            subtitle: listing.truncated
                ? const Text('Showing the first 1000 entries')
                : const Text('Read-only archive listing'),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: listing.entries.length,
              itemBuilder: (context, index) {
                final entry = listing.entries[index];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    entry.directory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                  ),
                  title: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_bytes(entry.sizeBytes)} · compressed ${_bytes(entry.compressedBytes)}',
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

final class _ApkViewer extends StatelessWidget {
  const _ApkViewer({required this.record, required this.repository});

  final FileRecord record;
  final MobileRepository repository;

  @override
  Widget build(BuildContext context) => FutureBuilder<AndroidApkDetails?>(
    future: repository.inspectApk(record),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final details = snapshot.data;
      if (details == null) return const Center(child: Icon(Icons.android));
      final chinese =
          MobileLocalizations.of(context).locale.languageCode == 'zh';
      return ListView(
        key: const Key('mobile-apk-viewer'),
        padding: const EdgeInsets.all(20),
        children: [
          if (details.iconBytes case final Uint8List bytes)
            Center(child: Image.memory(bytes, width: 96, height: 96)),
          const SizedBox(height: 12),
          Text(
            details.applicationName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          _Info(label: 'Package', value: details.packageName),
          _Info(
            label: 'Version',
            value: '${details.versionName} (${details.versionCode})',
          ),
          _Info(
            label: 'Signed',
            value: details.signed ? 'Yes' : 'Unknown / no signature',
          ),
          _Info(label: 'Installed', value: details.installed ? 'Yes' : 'No'),
          _Info(label: 'File size', value: _bytes(record.sizeBytes)),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('mobile-apk-system-install'),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(
                    chinese ? '交给 Android 安装' : 'Install with Android',
                  ),
                  content: Text(
                    chinese
                        ? 'PickLogic 只会把此 APK 交给 Android 系统安装界面。系统会再次确认，PickLogic 不会静默安装。'
                        : 'PickLogic will only hand this APK to Android\'s system installer. Android will ask again; PickLogic cannot install silently.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(chinese ? '取消' : 'Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(chinese ? '继续' : 'Continue'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await repository.open(record);
            },
            icon: const Icon(Icons.install_mobile_outlined),
            label: Text(chinese ? '系统安装…' : 'System install…'),
          ),
        ],
      );
    },
  );
}

final class _OfficeViewer extends StatelessWidget {
  const _OfficeViewer({required this.record, required this.repository});

  final FileRecord record;
  final MobileRepository repository;

  @override
  Widget build(BuildContext context) {
    final chinese = MobileLocalizations.of(context).locale.languageCode == 'zh';
    return FutureBuilder<AndroidOfficePreview?>(
      future: repository.inspectOffice(record),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final preview = snapshot.data;
        if (preview == null) {
          return Center(
            child: Text(
              chinese
                  ? '无法读取此 Office 文件的轻量结构。可从“更多”使用其他应用打开。'
                  : 'The lightweight Office structure could not be read. Use More to open it with another app.',
            ),
          );
        }
        return ListView(
          key: const Key('mobile-office-viewer'),
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined, size: 40),
              title: Text(
                preview.title.isEmpty ? record.displayName : preview.title,
              ),
              subtitle: Text(
                '${preview.kind.toUpperCase()} · ${_bytes(record.sizeBytes)}',
              ),
            ),
            Text(
              preview.kind == 'docx'
                  ? (chinese
                        ? '${preview.itemCount} 个段落 · ${preview.imageCount} 张图片'
                        : '${preview.itemCount} paragraphs · ${preview.imageCount} images')
                  : preview.kind == 'xlsx'
                  ? (chinese
                        ? '${preview.itemCount} 个工作表'
                        : '${preview.itemCount} sheets')
                  : preview.kind == 'pptx'
                  ? (chinese
                        ? '${preview.itemCount} 张幻灯片'
                        : '${preview.itemCount} slides')
                  : (chinese ? '旧版 Office 二进制格式' : 'Legacy Office binary'),
            ),
            const SizedBox(height: 12),
            for (final section in preview.sections.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SelectableText(section),
              ),
            if (preview.gridRows.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    for (
                      var column = 0;
                      column <
                          preview.gridRows
                              .map((row) => row.length)
                              .fold<int>(0, (a, b) => a > b ? a : b);
                      column++
                    )
                      DataColumn(label: Text('${column + 1}')),
                  ],
                  rows: [
                    for (final row in preview.gridRows)
                      DataRow(
                        cells: [
                          for (
                            var column = 0;
                            column <
                                preview.gridRows
                                    .map((item) => item.length)
                                    .fold<int>(0, (a, b) => a > b ? a : b);
                            column++
                          )
                            DataCell(
                              Text(column < row.length ? row[column] : ''),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            if (preview.truncated)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  chinese
                      ? '预览已按体积限制截断；原文件未被完整载入内存。'
                      : 'The preview was bounded by size; the whole file was not loaded into memory.',
                ),
              ),
            const SizedBox(height: 12),
            Text(
              chinese
                  ? '轻量预览不保证 Office 原排版；原文件保持不变。'
                  : 'This lightweight preview does not preserve full Office layout; the source remains unchanged.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

final class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: SelectableText(value),
  );
}

String _bytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

const _images = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'tif',
  'tiff',
};
const _videos = <String>{'mp4', 'm4v', 'mov', 'webm', 'mkv', 'avi'};
const _audio = <String>{'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'};
const _text = <String>{
  'txt',
  'md',
  'json',
  'xml',
  'csv',
  'log',
  'yaml',
  'yml',
  'ini',
  'dart',
  'kt',
  'java',
  'c',
  'cc',
  'cpp',
  'h',
  'hpp',
  'py',
  'js',
  'ts',
  'html',
  'css',
};
const _office = <String>{'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'};
