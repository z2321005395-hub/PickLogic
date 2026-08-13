import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

typedef LiteratureReadingPositionChanged =
    void Function(int currentPage, int totalPages);

/// Reads one explicitly selected local PDF without modifying it.
final class ProLocalPdfReader extends StatelessWidget {
  const ProLocalPdfReader({
    super.key,
    required this.path,
    required this.fileName,
    required this.initialPageNumber,
    required this.onPositionChanged,
  });

  final String path;
  final String fileName;
  final int initialPageNumber;
  final LiteratureReadingPositionChanged onPositionChanged;

  @override
  Widget build(BuildContext context) => _ProPdfReader(
    filePath: path,
    sourceName: fileName,
    initialPageNumber: initialPageNumber,
    onPositionChanged: onPositionChanged,
  );
}

/// Generated-fixture reader retained for tests and packaged engine smoke.
final class ProSyntheticPdfReader extends StatelessWidget {
  const ProSyntheticPdfReader({super.key});

  @override
  Widget build(BuildContext context) => _ProPdfReader(
    documentBytes: buildSyntheticLiteraturePdf(),
    sourceName: 'picklogic-synthetic-literature-v1.pdf',
    initialPageNumber: 1,
    onPositionChanged: _ignorePosition,
  );

  static void _ignorePosition(int currentPage, int totalPages) {}
}

final class _ProPdfReader extends StatefulWidget {
  const _ProPdfReader({
    this.filePath,
    this.documentBytes,
    required this.sourceName,
    required this.initialPageNumber,
    required this.onPositionChanged,
  }) : assert((filePath == null) != (documentBytes == null));

  final String? filePath;
  final Uint8List? documentBytes;
  final String sourceName;
  final int initialPageNumber;
  final LiteratureReadingPositionChanged onPositionChanged;

  bool get isSynthetic => documentBytes != null;

  @override
  State<_ProPdfReader> createState() => _ProPdfReaderState();
}

final class _ProPdfReaderState extends State<_ProPdfReader> {
  static const _cacheLimitBytes = 24 * 1024 * 1024;

  final PdfViewerController _viewerController = PdfViewerController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageController = TextEditingController();
  PdfTextSearcher? _searcher;
  PdfDocument? _document;
  int _pageNumber = 1;
  double? _zoom;
  bool _loadSucceeded = false;
  bool _positionRestored = false;
  String? _pageJumpError;

  @override
  void initState() {
    super.initState();
    _pageNumber = widget.initialPageNumber < 1 ? 1 : widget.initialPageNumber;
    _pageController.text = '$_pageNumber';
    _viewerController.addListener(_onViewerTransformChanged);
  }

  @override
  void dispose() {
    _viewerController.removeListener(_onViewerTransformChanged);
    _searcher?.dispose();
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    _searcher?.dispose();
    final searcher = PdfTextSearcher(controller)..addListener(_onSearchChanged);
    if (!mounted) {
      searcher.dispose();
      return;
    }
    setState(() {
      _document = document;
      _searcher = searcher;
    });
    unawaited(_restoreReadingPosition(document, controller));
  }

  Future<void> _restoreReadingPosition(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    final target = widget.initialPageNumber.clamp(1, document.pages.length);
    if (target != 1) {
      await controller.goToPage(pageNumber: target, duration: Duration.zero);
    }
    if (!mounted) return;
    setState(() {
      _positionRestored = true;
      _pageNumber = target;
      _pageController.text = '$target';
      _zoom = controller.currentZoom;
    });
    widget.onPositionChanged(target, document.pages.length);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _onViewerTransformChanged() {
    if (!mounted || !_viewerController.isReady) return;
    final zoom = _viewerController.currentZoom;
    if (_zoom == zoom) return;
    setState(() => _zoom = zoom);
  }

  void _startSearch() {
    final searcher = _searcher;
    if (searcher == null) return;
    searcher.startTextSearch(
      _searchController.text.trim(),
      searchImmediately: true,
    );
  }

  Future<void> _jumpToPage() async {
    final document = _document;
    final page = int.tryParse(_pageController.text.trim());
    if (document == null ||
        page == null ||
        page < 1 ||
        page > document.pages.length) {
      setState(() => _pageJumpError = '页码应为 1–${document?.pages.length ?? 1}');
      return;
    }
    setState(() => _pageJumpError = null);
    await _viewerController.goToPage(pageNumber: page);
  }

  void _paintSearchMatches(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final searcher = _searcher;
    final matchLabel = searcher == null
        ? '搜索器准备中'
        : searcher.isSearching
        ? '正在搜索 ${searcher.searchingPageNumber ?? 0}/${searcher.totalPageCount ?? 0}'
        : searcher.matches.isEmpty
        ? '0 matches'
        : '${(searcher.currentIndex ?? 0) + 1}/${searcher.matches.length} matches';
    final zoomLabel = _zoom == null ? '缩放准备中' : '${(_zoom! * 100).round()}%';

    return Column(
      key: const Key('pro-pdf-reader'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              label: Text(widget.isSynthetic ? 'SYNTHETIC PDF' : 'LOCAL PDF'),
            ),
            const Chip(label: Text('本地渲染')),
            const Chip(label: Text('滚动 / 缩放 / 选择 / 复制')),
            Chip(label: Text('缓存上限 ${_cacheLimitBytes ~/ (1024 * 1024)} MiB')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.isSynthetic
              ? '运行时生成的合成 PDF；未读取、上传或修改真实文献。'
              : '只读打开所选本地 PDF；不上传、不改写、不自动重命名。',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('pdf-search-field'),
                controller: _searchController,
                enabled: searcher != null,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '搜索 PDF 文本',
                  hintText: '输入关键词',
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _startSearch(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('pdf-search-action'),
              tooltip: '搜索',
              onPressed: searcher == null ? null : _startSearch,
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: '上一个匹配',
              onPressed: searcher?.hasMatches == true
                  ? () => searcher!.goToPrevMatch()
                  : null,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: '下一个匹配',
              onPressed: searcher?.hasMatches == true
                  ? () => searcher!.goToNextMatch()
                  : null,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(matchLabel, key: const Key('pdf-search-status')),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('pdf-zoom-out'),
              tooltip: '缩小',
              onPressed: _viewerController.isReady
                  ? () => _viewerController.zoomDown()
                  : null,
              icon: const Icon(Icons.zoom_out),
            ),
            Text(zoomLabel, key: const Key('pdf-zoom-status')),
            IconButton(
              key: const Key('pdf-zoom-in'),
              tooltip: '放大',
              onPressed: _viewerController.isReady
                  ? () => _viewerController.zoomUp()
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
            SizedBox(
              width: 92,
              child: TextField(
                key: const Key('pdf-page-jump-field'),
                controller: _pageController,
                enabled: document != null,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '跳至页',
                ),
                onSubmitted: (_) => _jumpToPage(),
              ),
            ),
            IconButton(
              key: const Key('pdf-page-jump-action'),
              tooltip: '跳转',
              onPressed: document == null ? null : _jumpToPage,
              icon: const Icon(Icons.arrow_forward),
            ),
            Text(
              document == null
                  ? (_loadSucceeded ? '正在准备页面' : '正在加载 PDF')
                  : '第 $_pageNumber / ${document.pages.length} 页',
              key: const Key('pdf-page-status'),
            ),
            if (_pageJumpError != null)
              Text(
                _pageJumpError!,
                key: const Key('pdf-page-jump-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 520,
          child: Row(
            children: [
              SizedBox(
                width: 92,
                child: document == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        key: const Key('pdf-thumbnail-list'),
                        itemCount: document.pages.length,
                        itemBuilder: (context, index) {
                          final page = index + 1;
                          final selected = page == _pageNumber;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              key: Key('pdf-thumbnail-$page'),
                              onTap: () =>
                                  _viewerController.goToPage(pageNumber: page),
                              child: Container(
                                height: 112,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).dividerColor,
                                    width: selected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: PdfPageView(
                                        document: document,
                                        pageNumber: page,
                                        maximumDpi: 96,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 2,
                                      bottom: 2,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.65,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          child: Text(
                                            '$page',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildViewer(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViewer() {
    final params = PdfViewerParams(
      limitRenderingCache: true,
      maxImageBytesCachedOnMemory: _cacheLimitBytes,
      horizontalCacheExtent: 0.5,
      verticalCacheExtent: 0.5,
      pagePaintCallbacks: [_paintSearchMatches],
      onDocumentChanged: (value) {
        if (mounted) setState(() => _document = value);
      },
      onViewerReady: _onViewerReady,
      onPageChanged: (value) {
        final document = _document;
        if (!mounted || value == null) return;
        setState(() {
          _pageNumber = value;
          _pageController.text = '$value';
        });
        if (_positionRestored && document != null) {
          widget.onPositionChanged(value, document.pages.length);
        }
      },
      onDocumentLoadFinished: (_, succeeded) {
        if (mounted) setState(() => _loadSucceeded = succeeded);
      },
      errorBannerBuilder: (context, error, stackTrace, documentRef) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '无法只读打开此 PDF。请确认文件仍存在、未损坏且未受不支持的密码保护。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
    final bytes = widget.documentBytes;
    if (bytes != null) {
      return PdfViewer.data(
        bytes,
        sourceName: widget.sourceName,
        controller: _viewerController,
        params: params,
      );
    }
    return PdfViewer.file(
      widget.filePath!,
      controller: _viewerController,
      params: params,
    );
  }
}

/// Builds a deterministic two-page PDF fixture without touching the file system.
Uint8List buildSyntheticLiteraturePdf() {
  const pageOne =
      'BT /F1 22 Tf 72 720 Td (PickLogic synthetic literature sample) Tj '
      '0 -36 Td /F1 12 Tf (Local-first PDF rendering and text selection.) Tj ET';
  const pageTwo =
      'BT /F1 22 Tf 72 720 Td (Insight evidence page) Tj '
      '0 -36 Td /F1 12 Tf (Searchable synthetic text. No real file was read.) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>',
    '<< /Length ${ascii.encode(pageOne).length} >>\nstream\n$pageOne\nendstream',
    '<< /Length ${ascii.encode(pageTwo).length} >>\nstream\n$pageTwo\nendstream',
  ];

  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(ascii.encode(output.toString()).length);
    output
      ..write('${index + 1} 0 obj\n')
      ..write(objects[index])
      ..write('\nendobj\n');
  }
  final xrefOffset = ascii.encode(output.toString()).length;
  output
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(ascii.encode(output.toString()));
}

/// Runs against the packaged native engine and returns a process exit code.
///
/// This path never accepts a locator: it parses the generated fixture, extracts
/// text, and renders one small page image entirely in memory.
Future<int> runSyntheticPdfEngineSmoke() async {
  WidgetsFlutterBinding.ensureInitialized();
  PdfDocument? document;
  PdfImage? image;
  try {
    await pdfrxFlutterInitialize();
    document = await PdfDocument.openData(
      buildSyntheticLiteraturePdf(),
      sourceName: 'picklogic-packaged-engine-smoke-v1.pdf',
    );
    if (document.pages.length != 2) return 2;

    final firstText = await document.pages[0].loadStructuredText();
    final secondText = await document.pages[1].loadStructuredText();
    if (!firstText.fullText.contains('PickLogic') ||
        !secondText.fullText.contains('No real file was read.')) {
      return 3;
    }

    image = await document.pages[0].render(fullWidth: 306, fullHeight: 396);
    if (image == null ||
        image.width != 306 ||
        image.height != 396 ||
        image.pixels.length != 306 * 396 * 4) {
      return 4;
    }
    return 0;
  } on Object {
    return 1;
  } finally {
    image?.dispose();
    await document?.dispose();
  }
}
