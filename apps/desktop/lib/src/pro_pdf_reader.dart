import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

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
    this.viewerBuilder,
    this.translationProvider = const DisabledTranslationProvider(),
    this.onConfigureTranslation,
  });

  final String path;
  final String fileName;
  final int initialPageNumber;
  final LiteratureReadingPositionChanged onPositionChanged;
  final WidgetBuilder? viewerBuilder;
  final TranslationProvider translationProvider;
  final VoidCallback? onConfigureTranslation;

  @override
  Widget build(BuildContext context) => _ProPdfReader(
    filePath: path,
    sourceName: fileName,
    initialPageNumber: initialPageNumber,
    onPositionChanged: onPositionChanged,
    viewerBuilder: viewerBuilder,
    translationProvider: translationProvider,
    onConfigureTranslation: onConfigureTranslation,
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
    translationProvider: const DisabledTranslationProvider(),
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
    this.viewerBuilder,
    required this.translationProvider,
    this.onConfigureTranslation,
  }) : assert((filePath == null) != (documentBytes == null));

  final String? filePath;
  final Uint8List? documentBytes;
  final String sourceName;
  final int initialPageNumber;
  final LiteratureReadingPositionChanged onPositionChanged;
  final WidgetBuilder? viewerBuilder;
  final TranslationProvider translationProvider;
  final VoidCallback? onConfigureTranslation;

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
  bool _pageJumpInvalid = false;
  String _selectedText = '';
  bool _selectionLoading = false;
  bool _translationBusy = false;

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
      setState(() => _pageJumpInvalid = true);
      return;
    }
    setState(() => _pageJumpInvalid = false);
    await _viewerController.goToPage(pageNumber: page);
  }

  void _paintSearchMatches(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  Future<void> _onTextSelectionChanged(PdfTextSelection selection) async {
    if (!selection.hasSelectedText || !selection.isCopyAllowed) {
      if (mounted && _selectedText.isNotEmpty) {
        setState(() => _selectedText = '');
      }
      return;
    }
    if (mounted) setState(() => _selectionLoading = true);
    try {
      final text = (await selection.getSelectedText()).trim();
      if (mounted) setState(() => _selectedText = text);
    } on Object {
      if (mounted) setState(() => _selectedText = '');
    } finally {
      if (mounted) setState(() => _selectionLoading = false);
    }
  }

  Future<void> _copySelection() async {
    if (!_viewerController.isReady) return;
    final copied = await _viewerController.textSelectionDelegate
        .copyTextSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? _PdfReaderStrings.of(context).selectionCopied
              : _PdfReaderStrings.of(context).selectionCopyUnavailable,
        ),
      ),
    );
  }

  Future<void> _translateSelection() async {
    final strings = _PdfReaderStrings.of(context);
    final source = _selectedText.trim();
    if (source.isEmpty || _translationBusy) return;
    final configured = await widget.translationProvider.isConfigured();
    if (!mounted) return;
    if (!configured) {
      widget.onConfigureTranslation?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.translationNeedsConfiguration)),
      );
      return;
    }
    setState(() => _translationBusy = true);
    try {
      final result = await widget.translationProvider.translateSelectedText(
        source,
        targetLanguage: strings.isChinese ? 'Simplified Chinese' : 'English',
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('pdf-translation-result-dialog'),
          title: Text(strings.translationResult),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
            child: SingleChildScrollView(
              child: SelectableText(result.translatedText),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: result.translatedText)),
              icon: const Icon(Icons.copy_outlined),
              label: Text(strings.copyTranslation),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.close),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.translationFailed}: $error')),
      );
    } finally {
      if (mounted) setState(() => _translationBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _PdfReaderStrings.of(context);
    final document = _document;
    final searcher = _searcher;
    final matchLabel = searcher == null
        ? strings.searchPreparing
        : searcher.isSearching
        ? strings.searching(
            searcher.searchingPageNumber ?? 0,
            searcher.totalPageCount ?? 0,
          )
        : searcher.matches.isEmpty
        ? strings.noMatches
        : strings.matches(
            (searcher.currentIndex ?? 0) + 1,
            searcher.matches.length,
          );
    final zoomLabel = _zoom == null
        ? strings.zoomPreparing
        : '${(_zoom! * 100).round()}%';

    return Column(
      key: const Key('pro-pdf-reader'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.isSynthetic
              ? strings.syntheticDescription
              : strings.localDescription,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  strings.localRendering,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (_selectionLoading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_selectedText.isNotEmpty) ...[
                  Chip(
                    key: const Key('pdf-selection-status'),
                    avatar: const Icon(Icons.text_fields, size: 16),
                    label: Text(
                      strings.selectedCharacters(_selectedText.length),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('pdf-copy-selection-action'),
                    onPressed: _copySelection,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(strings.copySelection),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('pdf-translate-selection-action'),
                    onPressed: _translationBusy ? null : _translateSelection,
                    icon: _translationBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.translate),
                    label: Text(strings.translateSelection),
                  ),
                ],
                const SizedBox(width: 4),
                SizedBox(
                  width: 220,
                  child: TextField(
                    key: const Key('pdf-search-field'),
                    controller: _searchController,
                    enabled: searcher != null,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: strings.searchPdfText,
                      hintText: strings.searchHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _startSearch(),
                  ),
                ),
                IconButton(
                  key: const Key('pdf-search-action'),
                  tooltip: strings.search,
                  onPressed: searcher == null ? null : _startSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
                Text(matchLabel, key: const Key('pdf-search-status')),
                IconButton(
                  tooltip: strings.previousMatch,
                  onPressed: searcher?.hasMatches == true
                      ? () => searcher!.goToPrevMatch()
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: strings.nextMatch,
                  onPressed: searcher?.hasMatches == true
                      ? () => searcher!.goToNextMatch()
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('pdf-zoom-out'),
                  tooltip: strings.zoomOut,
                  onPressed: _viewerController.isReady
                      ? () => _viewerController.zoomDown()
                      : null,
                  icon: const Icon(Icons.zoom_out),
                ),
                Text(zoomLabel, key: const Key('pdf-zoom-status')),
                IconButton(
                  key: const Key('pdf-zoom-in'),
                  tooltip: strings.zoomIn,
                  onPressed: _viewerController.isReady
                      ? () => _viewerController.zoomUp()
                      : null,
                  icon: const Icon(Icons.zoom_in),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 86,
                  child: TextField(
                    key: const Key('pdf-page-jump-field'),
                    controller: _pageController,
                    enabled: document != null,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: strings.jumpToPage,
                    ),
                    onSubmitted: (_) => _jumpToPage(),
                  ),
                ),
                IconButton(
                  key: const Key('pdf-page-jump-action'),
                  tooltip: strings.jump,
                  onPressed: document == null ? null : _jumpToPage,
                  icon: const Icon(Icons.arrow_forward),
                ),
                Text(
                  document == null
                      ? (_loadSucceeded
                            ? strings.preparingPages
                            : strings.loadingPdf)
                      : strings.pagePosition(
                          _pageNumber,
                          document.pages.length,
                        ),
                  key: const Key('pdf-page-status'),
                ),
                if (_pageJumpInvalid)
                  Text(
                    strings.pageRange(document?.pages.length ?? 1),
                    key: const Key('pdf-page-jump-error'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 76,
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
                                height: 96,
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
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(color: Colors.white),
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
              const VerticalDivider(width: 10),
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
    final viewerBuilder = widget.viewerBuilder;
    if (viewerBuilder != null) return viewerBuilder(context);
    final strings = _PdfReaderStrings.of(context);
    final params = PdfViewerParams(
      limitRenderingCache: true,
      maxImageBytesCachedOnMemory: _cacheLimitBytes,
      horizontalCacheExtent: 0.5,
      verticalCacheExtent: 0.5,
      textSelectionParams: PdfTextSelectionParams(
        enabled: true,
        showContextMenuAutomatically: true,
        onTextSelectionChange: _onTextSelectionChanged,
      ),
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
            strings.openError,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
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

final class _PdfReaderStrings {
  const _PdfReaderStrings(this.isChinese);

  factory _PdfReaderStrings.of(BuildContext context) => _PdfReaderStrings(
    PickLogicLocalizations.of(context).locale.languageCode == 'zh',
  );

  final bool isChinese;

  String get searchPreparing => isChinese ? '搜索器准备中' : 'Search is preparing';
  String searching(int page, int totalPages) =>
      isChinese ? '正在搜索 $page/$totalPages' : 'Searching $page/$totalPages';
  String get noMatches => isChinese ? '0 个匹配' : '0 matches';
  String matches(int current, int total) =>
      isChinese ? '$current/$total 个匹配' : '$current/$total matches';
  String get zoomPreparing => isChinese ? '缩放准备中' : 'Zoom is preparing';
  String get syntheticPdf => isChinese ? '合成 PDF' : 'SYNTHETIC PDF';
  String get localPdf => isChinese ? '本地 PDF' : 'LOCAL PDF';
  String get localRendering => isChinese ? '本地渲染' : 'Local rendering';
  String get capabilities =>
      isChinese ? '滚动 / 缩放 / 选择 / 复制' : 'Scroll / zoom / select / copy';
  String cacheLimit(int mebibytes) =>
      isChinese ? '缓存上限 $mebibytes MiB' : 'Cache limit $mebibytes MiB';
  String get syntheticDescription => isChinese
      ? '运行时生成的合成 PDF；未读取、上传或修改真实文献。'
      : 'Runtime-generated synthetic PDF; no real literature was read, uploaded, or modified.';
  String get localDescription => isChinese
      ? '只读打开所选本地 PDF；不上传、不改写、不自动重命名。'
      : 'Opens the selected local PDF read-only; no upload, rewrite, or automatic rename.';
  String get searchPdfText => isChinese ? '搜索 PDF 文本' : 'Search PDF text';
  String get searchHint => isChinese ? '输入关键词' : 'Enter keywords';
  String get search => isChinese ? '搜索' : 'Search';
  String get previousMatch => isChinese ? '上一个匹配' : 'Previous match';
  String get nextMatch => isChinese ? '下一个匹配' : 'Next match';
  String get zoomOut => isChinese ? '缩小' : 'Zoom out';
  String get zoomIn => isChinese ? '放大' : 'Zoom in';
  String get jumpToPage => isChinese ? '跳至页' : 'Go to page';
  String get jump => isChinese ? '跳转' : 'Go';
  String get preparingPages => isChinese ? '正在准备页面' : 'Preparing pages';
  String get loadingPdf => isChinese ? '正在加载 PDF' : 'Loading PDF';
  String pagePosition(int currentPage, int totalPages) => isChinese
      ? '第 $currentPage / $totalPages 页'
      : 'Page $currentPage of $totalPages';
  String pageRange(int totalPages) => isChinese
      ? '页码应为 1–$totalPages'
      : 'Page must be between 1 and $totalPages';
  String selectedCharacters(int count) =>
      isChinese ? '已选择 $count 个字符' : '$count characters selected';
  String get copySelection => isChinese ? '复制' : 'Copy';
  String get translateSelection => isChinese ? '翻译' : 'Translate';
  String get selectionCopied =>
      isChinese ? '选中文字已复制。' : 'Selected text copied.';
  String get selectionCopyUnavailable =>
      isChinese ? '此 PDF 不允许复制文字。' : 'This PDF does not allow text copying.';
  String get translationNeedsConfiguration => isChinese
      ? '翻译默认关闭；请先配置 Provider。复制仍可使用。'
      : 'Translation is disabled until a provider is configured. Copy remains available.';
  String get translationResult => isChinese ? '翻译结果' : 'Translation result';
  String get copyTranslation => isChinese ? '复制译文' : 'Copy translation';
  String get translationFailed => isChinese ? '翻译失败' : 'Translation failed';
  String get close => isChinese ? '关闭' : 'Close';
  String get openError => isChinese
      ? '无法只读打开此 PDF。请确认文件仍存在、未损坏且未受不支持的密码保护。'
      : 'This PDF could not be opened read-only. Confirm that it still exists, is not damaged, and is not protected by an unsupported password.';
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
