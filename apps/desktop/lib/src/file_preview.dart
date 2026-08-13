import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'desktop_repository.dart';

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
      return _UnsupportedPreview(
        icon: _officeIcon(extension),
        title: chinese ? '系统预览处理器' : 'System preview handler',
        body: chinese
            ? '当前设备尚未接入可嵌入的 Office/WPS 预览处理器。可使用唯一的“打开”动作交给已安装应用。'
            : 'No embeddable Office/WPS preview handler is connected on this device. Use the single Open action to hand off to an installed app.',
      );
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

final class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.entry, required this.chinese});

  final BrowseEntry entry;
  final bool chinese;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: InteractiveViewer(
      minScale: 0.5,
      maxScale: 5,
      child: Center(
        child: Image.file(
          File(entry.path),
          fit: BoxFit.contain,
          cacheWidth: 1600,
          errorBuilder: (_, _, _) => _PreviewError(
            message: chinese ? '无法读取这张图片。' : 'This image could not be read.',
          ),
        ),
      ),
    ),
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
  late final Future<({List<ArchiveFile> files, int total})> _contents = _read();

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
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: value.files.length,
              itemBuilder: (context, index) {
                final file = value.files[index];
                return ListTile(
                  dense: true,
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
                  trailing: file.isFile ? Text(_compactBytes(file.size)) : null,
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
  Widget build(BuildContext context) =>
      FutureBuilder<({String text, bool truncated})>(
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
              Expanded(
                child: SelectionArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        value.text,
                        style: const TextStyle(fontFamily: 'Consolas'),
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
                    ? '直接子文件估算大小：${_compactBytes(value.bytes)}'
                    : 'Estimated direct-file size: ${_compactBytes(value.bytes)}',
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

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

IconData _officeIcon(String extension) => switch (extension) {
  'xls' || 'xlsx' => Icons.table_chart_outlined,
  'ppt' || 'pptx' => Icons.slideshow_outlined,
  _ => Icons.description_outlined,
};

String _compactBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
