import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A real, local PDF rendering slice backed only by a generated fixture.
///
/// It deliberately accepts no path or network source while dependency and
/// packaging measurements are under review.
final class ProSyntheticPdfReader extends StatefulWidget {
  const ProSyntheticPdfReader({super.key});

  @override
  State<ProSyntheticPdfReader> createState() => _ProSyntheticPdfReaderState();
}

final class _ProSyntheticPdfReaderState extends State<ProSyntheticPdfReader> {
  static const _cacheLimitBytes = 24 * 1024 * 1024;

  final PdfViewerController _viewerController = PdfViewerController();
  final TextEditingController _searchController = TextEditingController();
  late final Uint8List _documentBytes;
  PdfTextSearcher? _searcher;
  PdfDocument? _document;
  int _pageNumber = 1;
  bool _loadSucceeded = false;

  @override
  void initState() {
    super.initState();
    _documentBytes = buildSyntheticLiteraturePdf();
  }

  @override
  void dispose() {
    _searcher?.dispose();
    _searchController.dispose();
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
      _pageNumber = controller.pageNumber ?? 1;
    });
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _startSearch() {
    final searcher = _searcher;
    if (searcher == null) return;
    searcher.startTextSearch(
      _searchController.text.trim(),
      searchImmediately: true,
    );
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

    return Column(
      key: const Key('pro-pdf-reader'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Chip(label: Text('SYNTHETIC PDF')),
            const Chip(label: Text('本地渲染')),
            const Chip(label: Text('文本选择 / 复制')),
            Chip(label: Text('缓存上限 ${_cacheLimitBytes ~/ (1024 * 1024)} MiB')),
          ],
        ),
        const SizedBox(height: 8),
        const Text('当前只打开运行时生成的两页合成 PDF；未读取、上传或修改真实文献。'),
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
                  hintText: '例如 PickLogic',
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(matchLabel, key: const Key('pdf-search-status')),
            Text(
              document == null
                  ? (_loadSucceeded ? '正在准备页面' : '正在加载 PDF')
                  : '第 $_pageNumber / ${document.pages.length} 页',
              key: const Key('pdf-page-status'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 430,
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
                  child: PdfViewer.data(
                    _documentBytes,
                    sourceName: 'picklogic-synthetic-literature-v1.pdf',
                    controller: _viewerController,
                    params: PdfViewerParams(
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
                        if (mounted && value != null) {
                          setState(() => _pageNumber = value);
                        }
                      },
                      onDocumentLoadFinished: (_, succeeded) {
                        if (mounted) {
                          setState(() => _loadSucceeded = succeeded);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
