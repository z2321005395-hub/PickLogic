import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

import 'desktop_repository.dart';
import 'shell_thumbnail.dart';

bool supportsDesktopInternalViewer(BrowseEntry entry) {
  if (entry.isDirectory) return false;
  final extension = _extension(entry.name);
  return _imageExtensions.contains(extension) ||
      _videoExtensions.contains(extension) ||
      _audioExtensions.contains(extension) ||
      extension == 'pdf' ||
      _textExtensions.contains(extension) ||
      extension == 'zip' ||
      _officeExtensions.contains(extension);
}

final class DesktopInternalViewerPage extends StatefulWidget {
  const DesktopInternalViewerPage({
    super.key,
    required this.entries,
    required this.initialEntry,
    required this.chinese,
    required this.onOpenWith,
  });

  final List<BrowseEntry> entries;
  final BrowseEntry initialEntry;
  final bool chinese;
  final ValueChanged<BrowseEntry> onOpenWith;

  @override
  State<DesktopInternalViewerPage> createState() =>
      _DesktopInternalViewerPageState();
}

final class _DesktopInternalViewerPageState
    extends State<DesktopInternalViewerPage> {
  late int _index = widget.entries.indexWhere(
    (entry) => entry.id == widget.initialEntry.id,
  );

  BrowseEntry get _entry =>
      widget.entries[_index < 0
          ? 0
          : _index.clamp(0, widget.entries.length - 1)];

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('desktop-internal-viewer'),
    appBar: AppBar(
      title: Text(_entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: widget.chinese ? '上一个文件' : 'Previous file',
          onPressed: _index > 0 ? () => setState(() => _index--) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: widget.chinese ? '下一个文件' : 'Next file',
          onPressed: _index >= 0 && _index < widget.entries.length - 1
              ? () => setState(() => _index++)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        PopupMenuButton<String>(
          tooltip: widget.chinese ? '更多' : 'More',
          onSelected: (_) => widget.onOpenWith(_entry),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'open-with',
              child: ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(
                  widget.chinese ? '用其他应用打开' : 'Open with another app',
                ),
              ),
            ),
          ],
        ),
      ],
    ),
    body: DesktopFilePreview(
      key: ValueKey('internal-viewer-${_entry.id}'),
      entry: _entry,
      chinese: widget.chinese,
    ),
  );
}

final class DesktopFilePreview extends StatelessWidget {
  const DesktopFilePreview({
    super.key,
    required this.entry,
    required this.chinese,
  });

  final BrowseEntry entry;
  final bool chinese;

  @override
  Widget build(BuildContext context) {
    if (entry.isDirectory) {
      return _FolderPreview(entry: entry, chinese: chinese);
    }
    final extension = _extension(entry.name);
    if (_imageExtensions.contains(extension)) {
      return _ImagePreview(entry: entry, chinese: chinese);
    }
    if (_videoExtensions.contains(extension)) {
      return _MediaPreview(entry: entry, chinese: chinese, audioOnly: false);
    }
    if (_audioExtensions.contains(extension)) {
      return _MediaPreview(entry: entry, chinese: chinese, audioOnly: true);
    }
    if (extension == 'pdf') {
      return _PdfPreview(entry: entry, chinese: chinese);
    }
    if (_textExtensions.contains(extension)) {
      return _TextPreview(entry: entry, chinese: chinese);
    }
    if (_archiveExtensions.contains(extension)) {
      if (extension == 'zip') {
        return _ZipPreview(entry: entry, chinese: chinese);
      }
      return _UnsupportedPreview(
        icon: Icons.archive_outlined,
        title: chinese ? '压缩包目录预览' : 'Archive contents',
        body: chinese
            ? '当前只支持 ZIP 的只读目录列表；不会解压或修改此压缩包。'
            : 'Only ZIP has a read-only directory listing; this archive is not extracted or modified.',
      );
    }
    if (_officeExtensions.contains(extension)) {
      return _OfficePreview(entry: entry, chinese: chinese);
    }
    return _UnsupportedPreview(
      icon: Icons.insert_drive_file_outlined,
      title: chinese ? '暂无内容预览' : 'No content preview',
      body: chinese
          ? '此类型当前只显示本地元数据，不会读取整文件。'
          : 'This type currently exposes local metadata only; the full file is not read.',
    );
  }
}

final class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.entry,
    required this.chinese,
    required this.audioOnly,
  });

  final BrowseEntry entry;
  final bool chinese;
  final bool audioOnly;

  @override
  Widget build(BuildContext context) => PickLogicMediaPlayer(
    source: PickLogicMediaSource.file(entry.path),
    title: entry.name,
    chinese: chinese,
    audioOnly: audioOnly,
  );
}

final class _ImagePreview extends StatefulWidget {
  const _ImagePreview({required this.entry, required this.chinese});

  final BrowseEntry entry;
  final bool chinese;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

final class _ImagePreviewState extends State<_ImagePreview> {
  final TransformationController _transform = TransformationController();
  int _quarterTurns = 0;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final matrix = _transform.value.clone()
      ..scaleByDouble(factor, factor, 1, 1);
    _transform.value = matrix;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: widget.chinese ? '缩小' : 'Zoom out',
              onPressed: () => _zoom(0.8),
              icon: const Icon(Icons.zoom_out),
            ),
            IconButton(
              tooltip: widget.chinese ? '重置缩放' : 'Reset zoom',
              onPressed: () => _transform.value = Matrix4.identity(),
              icon: const Icon(Icons.fit_screen),
            ),
            IconButton(
              tooltip: widget.chinese ? '放大' : 'Zoom in',
              onPressed: () => _zoom(1.25),
              icon: const Icon(Icons.zoom_in),
            ),
            IconButton(
              tooltip: widget.chinese ? '向右旋转预览' : 'Rotate preview right',
              onPressed: () => setState(() => _quarterTurns++),
              icon: const Icon(Icons.rotate_right),
            ),
          ],
        ),
      ),
      Expanded(
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent &&
                HardwareKeyboard.instance.isControlPressed) {
              _zoom(event.scrollDelta.dy < 0 ? 1.12 : 0.89);
            }
          },
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 0.5,
              maxScale: 8,
              child: Center(
                child: RotatedBox(
                  quarterTurns: _quarterTurns,
                  child: Image.file(
                    File(widget.entry.path),
                    fit: BoxFit.contain,
                    cacheWidth: 2400,
                    errorBuilder: (_, _, _) => _PreviewError(
                      message: widget.chinese
                          ? '无法读取这张图片。'
                          : 'This image could not be read.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

final class _PdfPreview extends StatefulWidget {
  const _PdfPreview({required this.entry, required this.chinese});

  final BrowseEntry entry;
  final bool chinese;

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

final class _PdfPreviewState extends State<_PdfPreview> {
  final _controller = PdfViewerController();
  int _page = 1;
  int? _pages;
  double? _zoom;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    super.dispose();
  }

  void _onTransform() {
    if (!mounted || !_controller.isReady) return;
    final zoom = _controller.currentZoom;
    if (zoom != _zoom) setState(() => _zoom = zoom);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: widget.chinese ? '上一页' : 'Previous page',
                onPressed: _page <= 1
                    ? null
                    : () => _controller.goToPage(pageNumber: _page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_page / ${_pages ?? '—'}'),
              IconButton(
                tooltip: widget.chinese ? '下一页' : 'Next page',
                onPressed: _pages == null || _page >= _pages!
                    ? null
                    : () => _controller.goToPage(pageNumber: _page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
              const Spacer(),
              IconButton(
                tooltip: widget.chinese ? '缩小' : 'Zoom out',
                onPressed: () => _controller.zoomDown(),
                icon: const Icon(Icons.remove),
              ),
              Text(_zoom == null ? '—' : '${(_zoom! * 100).round()}%'),
              IconButton(
                tooltip: widget.chinese ? '放大' : 'Zoom in',
                onPressed: () => _controller.zoomUp(),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: PdfViewer.file(
          widget.entry.path,
          controller: _controller,
          params: PdfViewerParams(
            limitRenderingCache: true,
            maxImageBytesCachedOnMemory: 16 * 1024 * 1024,
            horizontalCacheExtent: 0.4,
            verticalCacheExtent: 0.5,
            onViewerReady: (document, _) {
              if (mounted) setState(() => _pages = document.pages.length);
            },
            onPageChanged: (page) {
              if (page != null && mounted) setState(() => _page = page);
            },
            errorBannerBuilder: (_, _, _, _) => _PreviewError(
              message: widget.chinese
                  ? 'PDFium 无法预览此 PDF。'
                  : 'PDFium could not preview this PDF.',
            ),
          ),
        ),
      ),
    ],
  );
}

final class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.entry, required this.chinese});

  final BrowseEntry entry;
  final bool chinese;

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

final class _ZipPreview extends StatefulWidget {
  const _ZipPreview({required this.entry, required this.chinese});

  final BrowseEntry entry;
  final bool chinese;

  @override
  State<_ZipPreview> createState() => _ZipPreviewState();
}

final class _ZipPreviewState extends State<_ZipPreview> {
  static const _maxEntries = 500;
  static const _maxExtractItems = 24;
  static const _maxExtractBytes = 512 * 1024 * 1024;
  late final Future<({List<ArchiveFile> files, int total})> _contents = _read();
  final Set<String> _selected = <String>{};
  bool _extracting = false;
  String? _extractStatus;

  Future<({List<ArchiveFile> files, int total})> _read() async {
    final input = InputFileStream(widget.entry.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return (
        files: archive.files.take(_maxEntries).toList(growable: false),
        total: archive.length,
      );
    } finally {
      input.closeSync();
    }
  }

  Future<void> _extractSelected() async {
    if (_selected.isEmpty || _extracting) return;
    final profile = Platform.environment['USERPROFILE'];
    if (profile == null || profile.trim().isEmpty) return;
    setState(() {
      _extracting = true;
      _extractStatus = null;
    });
    var extracted = 0;
    var skipped = 0;
    var totalBytes = 0;
    final archiveName = widget.entry.name.replaceFirst(
      RegExp(r'\.zip$', caseSensitive: false),
      '',
    );
    final root = Directory(
      '$profile${Platform.pathSeparator}PickLogic-TestWorkspace'
      '${Platform.pathSeparator}Archives${Platform.pathSeparator}$archiveName',
    );
    try {
      await root.create(recursive: true);
      final rootPath = root.absolute.path.replaceAll('\\', '/');
      final input = InputFileStream(widget.entry.path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        for (final file in archive.files) {
          if (!_selected.contains(file.name) || !file.isFile) continue;
          if (extracted + skipped >= _maxExtractItems) {
            skipped++;
            continue;
          }
          totalBytes += file.size;
          if (totalBytes > _maxExtractBytes || file.isSymbolicLink) {
            skipped++;
            continue;
          }
          final relative = file.name.replaceAll('\\', '/');
          final segments = relative.split('/');
          if (relative.startsWith('/') ||
              RegExp(r'^[A-Za-z]:').hasMatch(relative) ||
              segments.any((segment) => segment == '..' || segment.isEmpty)) {
            skipped++;
            continue;
          }
          final destination = File(
            '${root.path}${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}',
          );
          final destinationPath = destination.absolute.path.replaceAll(
            '\\',
            '/',
          );
          if (!destinationPath.startsWith('$rootPath/') ||
              await destination.exists()) {
            skipped++;
            continue;
          }
          await destination.parent.create(recursive: true);
          final output = OutputFileStream(destination.path);
          try {
            file.writeContent(output);
          } finally {
            output.closeSync();
          }
          extracted++;
        }
      } finally {
        input.closeSync();
      }
      if (!mounted) return;
      setState(() {
        _extractStatus = widget.chinese
            ? '已提取 $extracted 项到测试工作区；跳过 $skipped 项。'
            : 'Extracted $extracted item(s) to Test Workspace; skipped $skipped.';
      });
    } on Object {
      if (mounted) {
        setState(() {
          _extractStatus = widget.chinese
              ? '提取失败；源 ZIP 未修改。'
              : 'Extraction failed; the source ZIP was not modified.';
        });
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<({List<ArchiveFile> files, int total})>(
    future: _contents,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _PreviewError(
          message: widget.chinese
              ? '无法读取 ZIP 目录；文件可能已损坏或受密码保护。'
              : 'The ZIP directory is unavailable; it may be damaged or password-protected.',
        );
      }
      final value = snapshot.data;
      if (value == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        children: [
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(
              widget.chinese
                  ? '${value.total} 个内部项目（只读）'
                  : '${value.total} internal items (read-only)',
            ),
            subtitle: Text(
              widget.chinese
                  ? '不解压、不执行、不修改；最多显示前 $_maxEntries 项。'
                  : 'Nothing is extracted, executed, or changed; at most $_maxEntries entries are shown.',
            ),
            trailing: FilledButton.tonalIcon(
              key: const Key('extract-selected-archive-items'),
              onPressed: _selected.isEmpty || _extracting
                  ? null
                  : _extractSelected,
              icon: _extracting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.unarchive_outlined),
              label: Text(
                widget.chinese
                    ? '提取所选副本 (${_selected.length})'
                    : 'Extract selected copies (${_selected.length})',
              ),
            ),
          ),
          if (_extractStatus != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(_extractStatus!),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: value.files.length,
              itemBuilder: (context, index) {
                final file = value.files[index];
                return ListTile(
                  dense: true,
                  selected: _selected.contains(file.name),
                  leading: Icon(
                    file.isFile
                        ? Icons.insert_drive_file_outlined
                        : Icons.folder_outlined,
                  ),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: file.isFile
                      ? Text(
                          '${formatFileSize(file.rawContent?.length ?? file.size)} → '
                          '${formatFileSize(file.size)}',
                        )
                      : null,
                  trailing: file.isFile
                      ? Checkbox(
                          value: _selected.contains(file.name),
                          onChanged: (value) => setState(() {
                            if (value == true &&
                                _selected.length < _maxExtractItems) {
                              _selected.add(file.name);
                            } else {
                              _selected.remove(file.name);
                            }
                          }),
                        )
                      : null,
                  onTap: file.isFile
                      ? () => setState(() {
                          if (!_selected.add(file.name)) {
                            _selected.remove(file.name);
                          } else if (_selected.length > _maxExtractItems) {
                            _selected.remove(file.name);
                          }
                        })
                      : null,
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

final class _TextPreviewState extends State<_TextPreview> {
  static const _limit = 256 * 1024;
  late final Future<({String text, bool truncated})> _text = _read();
  final TextEditingController _searchController = TextEditingController();
  bool _wrap = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<({String text, bool truncated})> _read() async {
    final file = File(widget.entry.path);
    final reader = file
        .openRead(0, _limit + 1)
        .transform(const SystemEncoding().decoder);
    final buffer = StringBuffer();
    var count = 0;
    await for (final chunk in reader) {
      final remaining = _limit - count;
      if (remaining <= 0) {
        break;
      }
      final accepted = chunk.length <= remaining
          ? chunk
          : chunk.substring(0, remaining);
      buffer.write(accepted);
      count += accepted.length;
    }
    return (text: buffer.toString(), truncated: await file.length() > _limit);
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<({String text, bool truncated})>(
    future: _text,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _PreviewError(
          message: widget.chinese
              ? '无法读取文本预览。'
              : 'Text preview could not be read.',
        );
      }
      final value = snapshot.data;
      if (value == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final query = _searchController.text.trim().toLowerCase();
      final matchCount = query.isEmpty
          ? 0
          : RegExp(
              RegExp.escape(query),
              caseSensitive: false,
            ).allMatches(value.text).length;
      final numbered = value.text
          .split('\n')
          .indexed
          .map((line) => '${(line.$1 + 1).toString().padLeft(5)}  ${line.$2}')
          .join('\n');
      return Column(
        children: [
          if (value.truncated)
            MaterialBanner(
              content: Text(
                widget.chinese
                    ? '大文件仅显示前 256 KB。'
                    : 'Large file: showing the first 256 KB only.',
              ),
              actions: const [SizedBox.shrink()],
            ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('text-preview-search'),
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: widget.chinese
                            ? '在已加载文本中搜索'
                            : 'Search loaded text',
                        suffixText: query.isEmpty ? null : '$matchCount',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(widget.chinese ? '换行' : 'Wrap'),
                  Switch(
                    key: const Key('text-preview-wrap'),
                    value: _wrap,
                    onChanged: (value) => setState(() => _wrap = value),
                  ),
                  IconButton(
                    tooltip: widget.chinese ? '复制已加载文本' : 'Copy loaded text',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: value.text)),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: MediaQuery.sizeOf(context).width * 0.25,
                      maxWidth: _wrap
                          ? MediaQuery.sizeOf(context).width * 0.75
                          : double.infinity,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        numbered,
                        softWrap: _wrap,
                        style: const TextStyle(fontFamily: 'Consolas'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

final class _OfficePreview extends StatefulWidget {
  const _OfficePreview({required this.entry, required this.chinese});

  final BrowseEntry entry;
  final bool chinese;

  @override
  State<_OfficePreview> createState() => _OfficePreviewState();
}

final class _OfficePreviewState extends State<_OfficePreview> {
  late final Future<_OfficeSummary> _summary = _read();

  Future<_OfficeSummary> _read() async {
    final extension = _extension(widget.entry.name);
    if (!{'docx', 'xlsx', 'pptx'}.contains(extension)) {
      return _OfficeSummary(
        title: widget.entry.name,
        facts: const <String>[],
        excerpt: widget.chinese
            ? '旧版二进制 Office 格式需要系统 Office/WPS 预览处理器；PickLogic 不引入大型 Office Runtime。'
            : 'Legacy binary Office files require a system Office/WPS preview handler; PickLogic does not bundle a large Office runtime.',
      );
    }
    final input = InputFileStream(widget.entry.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return switch (extension) {
        'docx' => _readDocx(archive),
        'xlsx' => _readXlsx(archive),
        _ => _readPptx(archive),
      };
    } finally {
      input.closeSync();
    }
  }

  _OfficeSummary _readDocx(Archive archive) {
    final document = _archiveText(archive, 'word/document.xml');
    final paragraphs = RegExp(r'<w:p(?:\s|>)').allMatches(document).length;
    final images = archive.files
        .where((file) => file.isFile && file.name.startsWith('word/media/'))
        .length;
    return _OfficeSummary(
      title: widget.entry.name,
      facts: [
        widget.chinese
            ? '$paragraphs 个段落（有界估算）'
            : '$paragraphs paragraphs (bounded estimate)',
        widget.chinese ? '$images 张内嵌图片' : '$images embedded images',
      ],
      excerpt: _plainXmlText(document),
    );
  }

  _OfficeSummary _readXlsx(Archive archive) {
    final workbook = _archiveText(archive, 'xl/workbook.xml');
    final sheets = RegExp(r'<sheet\b[^>]*\bname="([^"]+)"')
        .allMatches(workbook)
        .map((match) => _xmlDecode(match.group(1)!))
        .take(24)
        .toList(growable: false);
    final shared = _plainXmlText(_archiveText(archive, 'xl/sharedStrings.xml'));
    final firstSheet = _archiveText(archive, 'xl/worksheets/sheet1.xml');
    final values = RegExp(r'<v>(.*?)</v>', dotAll: true)
        .allMatches(firstSheet)
        .map((match) => _xmlDecode(match.group(1)!))
        .take(80)
        .join('  |  ');
    return _OfficeSummary(
      title: widget.entry.name,
      facts: [
        widget.chinese
            ? '工作表：${sheets.isEmpty ? '无法确认' : sheets.join('、')}'
            : 'Sheets: ${sheets.isEmpty ? 'Unknown' : sheets.join(', ')}',
      ],
      excerpt: [
        shared,
        values,
      ].where((value) => value.trim().isNotEmpty).join('\n\n'),
    );
  }

  _OfficeSummary _readPptx(Archive archive) {
    final slides =
        archive.files
            .where(
              (file) =>
                  file.isFile &&
                  RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(file.name),
            )
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
    final excerpt = slides
        .take(12)
        .map((slide) => _plainXmlText(_archiveFileText(slide)))
        .where((text) => text.isNotEmpty)
        .join('\n\n');
    return _OfficeSummary(
      title: widget.entry.name,
      facts: [
        widget.chinese ? '${slides.length} 张幻灯片' : '${slides.length} slides',
      ],
      excerpt: excerpt,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_OfficeSummary>(
    future: _summary,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _PreviewError(
          message: widget.chinese
              ? '无法读取此 Office 文件的轻量结构预览。'
              : 'The lightweight Office structure preview is unavailable.',
        );
      }
      final summary = snapshot.data;
      if (summary == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return ListView(
        key: const Key('office-structure-preview'),
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 180,
            child: DesktopShellThumbnail(
              entry: widget.entry,
              size: 160,
              fallback: _officeIcon(_extension(widget.entry.name)),
            ),
          ),
          const SizedBox(height: 10),
          Text(summary.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final fact in summary.facts) Text('• $fact'),
          const SizedBox(height: 12),
          Text(
            widget.chinese ? '结构化文本摘要' : 'Structured text summary',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          SelectionArea(
            child: Text(
              summary.excerpt.trim().isEmpty
                  ? (widget.chinese ? '没有可提取的文本。' : 'No extractable text.')
                  : summary.excerpt,
              maxLines: 120,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.chinese
                ? '这是本地轻量 fallback，不保证 Office 原排版；原文件保持不变。'
                : 'This is a local lightweight fallback, not a full-fidelity Office renderer; the source is unchanged.',
          ),
        ],
      );
    },
  );
}

final class _OfficeSummary {
  const _OfficeSummary({
    required this.title,
    required this.facts,
    required this.excerpt,
  });

  final String title;
  final List<String> facts;
  final String excerpt;
}

final class _FolderPreview extends StatefulWidget {
  const _FolderPreview({required this.entry, required this.chinese});

  final BrowseEntry entry;
  final bool chinese;

  @override
  State<_FolderPreview> createState() => _FolderPreviewState();
}

final class _FolderPreviewState extends State<_FolderPreview> {
  late final Future<
    ({
      int items,
      int files,
      int folders,
      int bytes,
      Map<String, int> types,
      List<({String name, DateTime modified})> recent,
    })
  >
  _summary = _read();

  Future<
    ({
      int items,
      int files,
      int folders,
      int bytes,
      Map<String, int> types,
      List<({String name, DateTime modified})> recent,
    })
  >
  _read() async {
    var files = 0;
    var folders = 0;
    var bytes = 0;
    final types = <String, int>{};
    final recent = <({String name, DateTime modified})>[];
    await for (final child in Directory(
      widget.entry.path,
    ).list(followLinks: false)) {
      if (files + folders >= 1000) {
        break;
      }
      if (child is Directory) {
        folders++;
      } else if (child is File) {
        files++;
        final stat = await child.stat();
        bytes += stat.size;
        final extension = _extension(child.path);
        final type = extension.isEmpty ? '—' : extension.toUpperCase();
        types.update(type, (value) => value + 1, ifAbsent: () => 1);
        recent.add((
          name: child.uri.pathSegments.last,
          modified: stat.modified,
        ));
      }
    }
    recent.sort((left, right) => right.modified.compareTo(left.modified));
    return (
      items: files + folders,
      files: files,
      folders: folders,
      bytes: bytes,
      types: types,
      recent: recent.take(5).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<
        ({
          int items,
          int files,
          int folders,
          int bytes,
          Map<String, int> types,
          List<({String name, DateTime modified})> recent,
        })
      >(
        future: _summary,
        builder: (context, snapshot) {
          final value = snapshot.data;
          if (snapshot.hasError) {
            return _PreviewError(
              message: widget.chinese
                  ? '无法读取文件夹摘要。'
                  : 'Folder summary is unavailable.',
            );
          }
          if (value == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Icon(Icons.folder_outlined, size: 64),
              const SizedBox(height: 12),
              Text(
                widget.entry.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                widget.chinese
                    ? '直接子文件估算大小：${formatFileSize(value.bytes)}'
                    : 'Estimated direct-file size: ${formatFileSize(value.bytes)}',
              ),
              if (value.types.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.chinese ? '类型分布' : 'Type distribution',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final type
                        in (value.types.entries.toList()
                              ..sort((a, b) => b.value.compareTo(a.value)))
                            .take(8))
                      Chip(label: Text('${type.key} · ${type.value}')),
                  ],
                ),
              ],
              if (value.recent.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.chinese ? '最近修改' : 'Recently modified',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final item in value.recent)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(item.modified.toLocal().toString()),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                widget.chinese
                    ? '${value.items} 项 · ${value.folders} 个文件夹 · ${value.files} 个文件'
                    : '${value.items} items · ${value.folders} folders · ${value.files} files',
              ),
              const SizedBox(height: 8),
              Text(
                widget.chinese
                    ? '为保持响应速度，摘要最多检查 1000 个直接子项，不递归读取。'
                    : 'For responsiveness, the summary inspects at most 1,000 direct children and does not recurse.',
              ),
            ],
          );
        },
      );
}

final class _UnsupportedPreview extends StatelessWidget {
  const _UnsupportedPreview({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

final class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

const _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'tif',
  'tiff',
};
const _videoExtensions = {'mp4', 'm4v', 'mov', 'wmv', 'avi', 'mkv', 'webm'};
const _audioExtensions = {'mp3', 'm4a', 'aac', 'wav', 'wma', 'flac', 'ogg'};
const _textExtensions = {
  'txt',
  'md',
  'json',
  'xml',
  'csv',
  'log',
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
  'css',
  'html',
  'yaml',
  'yml',
  'toml',
  'ini',
  'ps1',
  'bat',
  'cmd',
  'sh',
};
const _officeExtensions = {'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'};
const _archiveExtensions = {'zip', '7z', 'rar', 'tar', 'gz'};

String _archiveText(Archive archive, String name) {
  final matches = archive.files.where((file) => file.name == name);
  return matches.isEmpty ? '' : _archiveFileText(matches.first);
}

String _archiveFileText(ArchiveFile file) {
  const maxXmlBytes = 2 * 1024 * 1024;
  if (!file.isFile || file.size <= 0 || file.size > maxXmlBytes) return '';
  final bytes = file.readBytes();
  if (bytes == null || bytes.lengthInBytes > maxXmlBytes) return '';
  return utf8.decode(bytes, allowMalformed: true);
}

String _plainXmlText(String xml) {
  if (xml.isEmpty) return '';
  final withBreaks = xml
      .replaceAll(RegExp(r'</(?:w:p|a:p|row|si)>'), '\n')
      .replaceAll(RegExp(r'<(?:w:tab|br|a:br)\b[^>]*/?>'), ' ');
  final stripped = withBreaks.replaceAll(RegExp(r'<[^>]+>'), ' ');
  return _xmlDecode(stripped)
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), '\n')
      .trim();
}

String _xmlDecode(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

IconData _officeIcon(String extension) => switch (extension) {
  'xls' || 'xlsx' => Icons.table_chart_outlined,
  'ppt' || 'pptx' => Icons.slideshow_outlined,
  _ => Icons.description_outlined,
};
