import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

import 'pdf_edit_exporter.dart';
import 'pro_pdf_content_editor.dart';
import 'pro_pdf_editor.dart';
import 'pro_translation.dart';

typedef LiteratureReadingPositionChanged =
    void Function(int currentPage, int totalPages);
typedef LiteratureAnnotationSaved =
    Future<void> Function(LiteratureAnnotation annotation);
typedef LiteratureAnnotationDeleted = Future<void> Function(String id);

@visibleForTesting
String normalizePdfSelectionText(String value) {
  var normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  normalized = normalized.replaceAllMapped(
    RegExp(r'([A-Za-z])-\s*\n\s*([a-z])'),
    (match) => '${match.group(1)}${match.group(2)}',
  );
  normalized = normalized.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' ');
  return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Reads and exports edited copies of one explicitly selected local PDF.
final class ProLocalPdfReader extends StatelessWidget {
  const ProLocalPdfReader({
    super.key,
    required this.path,
    required this.fileName,
    required this.initialPageNumber,
    required this.onPositionChanged,
    this.viewerBuilder,
    this.translationProvider = const DisabledTranslationProvider(),
    this.translationEngine,
    this.onTranslationEngineChanged,
    this.translationStore,
    this.onConfigureTranslation,
    this.thumbnailsVisible = true,
    this.onThumbnailsVisibilityChanged,
    this.literatureId = '',
    this.annotations = const <LiteratureAnnotation>[],
    this.onSaveAnnotation,
    this.onDeleteAnnotation,
    @visibleForTesting this.selectionTextForTesting,
  });

  final String path;
  final String fileName;
  final int initialPageNumber;
  final LiteratureReadingPositionChanged onPositionChanged;
  final WidgetBuilder? viewerBuilder;
  final TranslationProvider translationProvider;
  final TranslationEngineChoice? translationEngine;
  final Future<void> Function(TranslationEngineChoice choice)?
  onTranslationEngineChanged;
  final LiteratureTranslationStore? translationStore;
  final AsyncCallback? onConfigureTranslation;
  final bool thumbnailsVisible;
  final ValueChanged<bool>? onThumbnailsVisibilityChanged;
  final String literatureId;
  final List<LiteratureAnnotation> annotations;
  final LiteratureAnnotationSaved? onSaveAnnotation;
  final LiteratureAnnotationDeleted? onDeleteAnnotation;
  final ValueListenable<String>? selectionTextForTesting;

  @override
  Widget build(BuildContext context) => _ProPdfReader(
    filePath: path,
    sourceName: fileName,
    initialPageNumber: initialPageNumber,
    onPositionChanged: onPositionChanged,
    viewerBuilder: viewerBuilder,
    translationProvider: translationProvider,
    translationEngine: translationEngine,
    onTranslationEngineChanged: onTranslationEngineChanged,
    translationStore: translationStore,
    onConfigureTranslation: onConfigureTranslation,
    thumbnailsVisible: thumbnailsVisible,
    onThumbnailsVisibilityChanged: onThumbnailsVisibilityChanged,
    literatureId: literatureId,
    annotations: annotations,
    onSaveAnnotation: onSaveAnnotation,
    onDeleteAnnotation: onDeleteAnnotation,
    selectionTextForTesting: selectionTextForTesting,
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

@visibleForTesting
PdfDocumentRefFile buildProLocalPdfDocumentRef(String filePath) =>
    PdfDocumentRefFile(filePath, useProgressiveLoading: false);

final class _ProPdfReader extends StatefulWidget {
  const _ProPdfReader({
    this.filePath,
    this.documentBytes,
    required this.sourceName,
    required this.initialPageNumber,
    required this.onPositionChanged,
    this.viewerBuilder,
    required this.translationProvider,
    this.translationEngine,
    this.onTranslationEngineChanged,
    this.translationStore,
    this.onConfigureTranslation,
    this.thumbnailsVisible = true,
    this.onThumbnailsVisibilityChanged,
    this.literatureId = '',
    this.annotations = const <LiteratureAnnotation>[],
    this.onSaveAnnotation,
    this.onDeleteAnnotation,
    this.selectionTextForTesting,
  }) : assert((filePath == null) != (documentBytes == null));

  final String? filePath;
  final Uint8List? documentBytes;
  final String sourceName;
  final int initialPageNumber;
  final LiteratureReadingPositionChanged onPositionChanged;
  final WidgetBuilder? viewerBuilder;
  final TranslationProvider translationProvider;
  final TranslationEngineChoice? translationEngine;
  final Future<void> Function(TranslationEngineChoice choice)?
  onTranslationEngineChanged;
  final LiteratureTranslationStore? translationStore;
  final AsyncCallback? onConfigureTranslation;
  final bool thumbnailsVisible;
  final ValueChanged<bool>? onThumbnailsVisibilityChanged;
  final String literatureId;
  final List<LiteratureAnnotation> annotations;
  final LiteratureAnnotationSaved? onSaveAnnotation;
  final LiteratureAnnotationDeleted? onDeleteAnnotation;
  final ValueListenable<String>? selectionTextForTesting;

  bool get isSynthetic => documentBytes != null;

  @override
  State<_ProPdfReader> createState() => _ProPdfReaderState();
}

final class _ProPdfReaderState extends State<_ProPdfReader> {
  static const _cacheLimitBytes = 24 * 1024 * 1024;

  final PdfViewerController _viewerController = PdfViewerController();
  final PdfContentEditorController _contentEditorController =
      PdfContentEditorController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageController = TextEditingController();
  final TextEditingController _selectionSourceController =
      TextEditingController();
  PdfTextSearcher? _searcher;
  PdfDocument? _document;
  int _pageNumber = 1;
  double? _zoom;
  bool _loadSucceeded = false;
  bool _positionRestored = false;
  bool _pageJumpInvalid = false;
  String _selectedText = '';
  List<PdfPageTextRange> _selectedRanges = const <PdfPageTextRange>[];
  bool _selectionLoading = false;
  bool _translationBusy = false;
  bool _selectionTranslationBusy = false;
  bool _selectionTranslationDisabled = false;
  bool _selectionTranslationNeedsConfiguration = false;
  String _selectionTranslationSource = '';
  String? _selectionTranslationText;
  String? _selectionTranslationProviderLabel;
  String? _selectionTranslationError;
  List<TranslationAlternative> _selectionTranslationAlternatives =
      const <TranslationAlternative>[];
  final List<_LockedSelectionTranslation> _lockedSelectionTranslations =
      <_LockedSelectionTranslation>[];
  Timer? _selectionTranslationDebounce;
  Timer? _selectionSourceEditDebounce;
  int _selectionTranslationGeneration = 0;
  bool _selectionSourceEditing = false;
  bool _annotationBusy = false;
  bool _pdfEditBusy = false;
  bool _contentEditing = false;
  double? _contentEditZoom;
  Offset? _contentEditViewportFraction;
  bool _annotationsVisible = false;
  late bool _thumbnailsVisible;
  final Map<int, String> _pageTranslations = <int, String>{};
  final Map<int, String> _pageTranslationSources = <int, String>{};
  List<LiteratureTerminologyEntry> _terminology =
      const <LiteratureTerminologyEntry>[];
  String? _translationMemoryLanguage;
  bool _bilingualVisible = false;
  bool _documentTranslationBusy = false;
  bool _cancelDocumentTranslation = false;
  int _translationProgress = 0;
  int _translationTotal = 0;

  @override
  void initState() {
    super.initState();
    _pageNumber = widget.initialPageNumber < 1 ? 1 : widget.initialPageNumber;
    _thumbnailsVisible = widget.thumbnailsVisible;
    _pageController.text = '$_pageNumber';
    _viewerController.addListener(_onViewerTransformChanged);
    widget.selectionTextForTesting?.addListener(_onTestingSelectionChanged);
    if (widget.selectionTextForTesting?.value.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onTestingSelectionChanged();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ProPdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailsVisible != widget.thumbnailsVisible) {
      _thumbnailsVisible = widget.thumbnailsVisible;
    }
    if (!identical(
      oldWidget.selectionTextForTesting,
      widget.selectionTextForTesting,
    )) {
      oldWidget.selectionTextForTesting?.removeListener(
        _onTestingSelectionChanged,
      );
      widget.selectionTextForTesting?.addListener(_onTestingSelectionChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targetLanguage = _targetLanguage(_PdfReaderStrings.of(context));
    if (_translationMemoryLanguage == targetLanguage) return;
    _translationMemoryLanguage = targetLanguage;
    unawaited(_loadTranslationMemory(targetLanguage));
  }

  @override
  void dispose() {
    _selectionTranslationDebounce?.cancel();
    _selectionSourceEditDebounce?.cancel();
    widget.selectionTextForTesting?.removeListener(_onTestingSelectionChanged);
    _viewerController.removeListener(_onViewerTransformChanged);
    _searcher?.dispose();
    _searchController.dispose();
    _pageController.dispose();
    _selectionSourceController.dispose();
    super.dispose();
  }

  String _targetLanguage(_PdfReaderStrings strings) =>
      strings.isChinese ? 'Simplified Chinese' : 'English';

  String _selectionTargetLanguage(String source) {
    final containsCjk = source.runes.any(
      (rune) =>
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0xF900 && rune <= 0xFAFF),
    );
    return containsCjk ? 'English' : 'Simplified Chinese';
  }

  Map<String, String> get _terminologyMap => <String, String>{
    for (final term in _terminology) term.sourceTerm: term.translatedTerm,
  };

  Future<void> _loadTranslationMemory(String targetLanguage) async {
    final store = widget.translationStore;
    if (store == null || widget.literatureId.isEmpty) return;
    try {
      final pages = await store.loadPages(
        literatureId: widget.literatureId,
        targetLanguage: targetLanguage,
      );
      final terminology = await store.loadTerminology(targetLanguage);
      if (!mounted || _translationMemoryLanguage != targetLanguage) return;
      setState(() {
        _pageTranslations
          ..clear()
          ..addEntries(
            pages.map((item) => MapEntry(item.pageNumber, item.translatedText)),
          );
        _pageTranslationSources
          ..clear()
          ..addEntries(
            pages.map((item) => MapEntry(item.pageNumber, item.sourceText)),
          );
        _terminology = terminology;
      });
    } on Object {
      // Translation memory is optional; PDF reading remains available.
    }
  }

  Future<void> _showTerminologyEditor() async {
    final store = widget.translationStore;
    if (store == null) return;
    final strings = _PdfReaderStrings.of(context);
    final sourceController = TextEditingController();
    final translatedController = TextEditingController();
    final targetLanguage = _targetLanguage(strings);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            key: const Key('pdf-terminology-dialog'),
            title: Text(strings.terminology),
            content: SizedBox(
              width: 620,
              height: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(strings.terminologyNotice),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('pdf-terminology-source-field'),
                          controller: sourceController,
                          decoration: InputDecoration(
                            labelText: strings.sourceTerm,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('pdf-terminology-target-field'),
                          controller: translatedController,
                          decoration: InputDecoration(
                            labelText: strings.preferredTranslation,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        key: const Key('pdf-terminology-add-action'),
                        tooltip: strings.addTerm,
                        onPressed: () async {
                          final source = sourceController.text.trim();
                          final translated = translatedController.text.trim();
                          if (source.isEmpty || translated.isEmpty) return;
                          final now = DateTime.now().toUtc();
                          final term = LiteratureTerminologyEntry(
                            id: 'term-${now.microsecondsSinceEpoch}',
                            sourceTerm: source,
                            translatedTerm: translated,
                            targetLanguage: targetLanguage,
                            updatedAt: now,
                          );
                          await store.upsertTerm(term);
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            _terminology =
                                <LiteratureTerminologyEntry>[
                                  ..._terminology.where(
                                    (item) =>
                                        item.sourceTerm.toLowerCase() !=
                                        source.toLowerCase(),
                                  ),
                                  term,
                                ]..sort(
                                  (left, right) =>
                                      left.sourceTerm.toLowerCase().compareTo(
                                        right.sourceTerm.toLowerCase(),
                                      ),
                                );
                            sourceController.clear();
                            translatedController.clear();
                          });
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: _terminology.isEmpty
                        ? Center(child: Text(strings.noTerminology))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _terminology.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final term = _terminology[index];
                              return ListTile(
                                dense: true,
                                title: Text(term.sourceTerm),
                                subtitle: Text(term.translatedTerm),
                                trailing: IconButton(
                                  tooltip: strings.removeTerm,
                                  onPressed: () async {
                                    await store.deleteTerm(term.id);
                                    if (dialogContext.mounted) {
                                      setDialogState(
                                        () => _terminology = _terminology
                                            .where((item) => item.id != term.id)
                                            .toList(growable: false),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(strings.close),
              ),
            ],
          ),
        ),
      );
      if (mounted) setState(() {});
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      sourceController.dispose();
      translatedController.dispose();
    }
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
    if (_contentEditing) {
      _contentEditorController.goToPage(page);
      return;
    }
    await _viewerController.goToPage(pageNumber: page);
  }

  void _zoomOut() {
    if (_contentEditing) {
      _contentEditorController.zoomOut();
    } else if (_viewerController.isReady) {
      _viewerController.zoomDown();
    }
  }

  void _zoomIn() {
    if (_contentEditing) {
      _contentEditorController.zoomIn();
    } else if (_viewerController.isReady) {
      _viewerController.zoomUp();
    }
  }

  void _paintSearchMatches(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  void _paintAnnotations(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    for (final annotation in widget.annotations) {
      final color = switch (annotation.colorName) {
        'green' => Colors.lightGreen,
        'blue' => Colors.lightBlue,
        'pink' => Colors.pinkAccent,
        _ => Colors.amber,
      };
      for (final box in annotation.boxes.where(
        (item) => item.pageNumber == page.pageNumber,
      )) {
        final rect = PdfRect(
          box.left,
          box.top,
          box.right,
          box.bottom,
        ).toRectInDocument(page: page, pageRect: pageRect);
        switch (annotation.kind) {
          case LiteratureAnnotationKind.highlight:
            canvas.drawRect(
              rect,
              Paint()
                ..color = color.withValues(alpha: 0.30)
                ..style = PaintingStyle.fill,
            );
          case LiteratureAnnotationKind.underline:
            canvas.drawLine(
              Offset(rect.left, rect.bottom - 1),
              Offset(rect.right, rect.bottom - 1),
              Paint()
                ..color = color.withValues(alpha: 0.9)
                ..strokeWidth = 2,
            );
          case LiteratureAnnotationKind.strikethrough:
            canvas.drawLine(
              Offset(rect.left, rect.center.dy),
              Offset(rect.right, rect.center.dy),
              Paint()
                ..color = color.withValues(alpha: 0.9)
                ..strokeWidth = 2,
            );
          case LiteratureAnnotationKind.note:
            canvas.drawRect(
              rect,
              Paint()
                ..color = color.withValues(alpha: 0.75)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
        }
      }
    }
  }

  Future<void> _editPdfCopy() async {
    final document = _document;
    if (document == null ||
        widget.filePath == null ||
        _pdfEditBusy ||
        _contentEditing) {
      return;
    }
    await showPdfPageEditor(
      context: context,
      pageCount: document.pages.length,
      annotationCount: widget.annotations.length,
      onSaveRequested: (plan) => _saveEditedPdfCopy(plan: plan),
    );
  }

  Future<void> _editPdfContent() async {
    final document = _document;
    if (document == null || widget.filePath == null || _pdfEditBusy) return;
    if (_contentEditing) {
      await _contentEditorController.requestClose();
      return;
    }
    final viewportFraction = _captureCurrentPageViewport();
    setState(() {
      _contentEditing = true;
      _contentEditZoom = (_zoom ?? 1).clamp(0.25, 4).toDouble();
      _contentEditViewportFraction = viewportFraction;
      _pageJumpInvalid = false;
      _selectedText = '';
      _selectedRanges = const <PdfPageTextRange>[];
    });
  }

  void _onContentEditorClosed(PdfContentEditPlan? _) {
    if (!mounted) return;
    setState(() {
      _contentEditing = false;
      _contentEditZoom = null;
      _contentEditViewportFraction = null;
    });
  }

  void _onContentEditorZoomChanged(double zoom) {
    if (!mounted) return;
    setState(() => _contentEditZoom = zoom);
  }

  Offset? _captureCurrentPageViewport() {
    if (!_viewerController.isReady) return null;
    final pageLayouts = _viewerController.layout.pageLayouts;
    final pageIndex = _pageNumber - 1;
    if (pageIndex < 0 || pageIndex >= pageLayouts.length) return null;
    final pageRect = pageLayouts[pageIndex];
    final visiblePage = _viewerController.visibleRect.intersect(pageRect);
    final center = visiblePage.isEmpty ? pageRect.center : visiblePage.center;
    return Offset(
      ((center.dx - pageRect.left) / pageRect.width).clamp(0, 1).toDouble(),
      ((center.dy - pageRect.top) / pageRect.height).clamp(0, 1).toDouble(),
    );
  }

  void _onContentEditorPageChanged(int pageNumber) {
    final document = _document;
    if (!mounted || document == null) return;
    setState(() {
      _pageNumber = pageNumber;
      _pageController.text = '$pageNumber';
    });
    if (_viewerController.isReady) {
      unawaited(
        _viewerController.goToPage(
          pageNumber: pageNumber,
          duration: Duration.zero,
        ),
      );
    } else {
      widget.onPositionChanged(pageNumber, document.pages.length);
    }
  }

  Future<bool> _saveEditedPdfCopy({
    required PdfEditPlan plan,
    PdfContentEditPlan? contentEdits,
  }) async {
    final sourcePath = widget.filePath;
    if (sourcePath == null || _pdfEditBusy || !mounted) return false;
    final strings = _PdfReaderStrings.of(context);
    final destination = await const PicklogicWindowsBridge().pickPdfSavePath(
      title: strings.saveEditedCopy,
      suggestedName: _suggestedEditedFileName(widget.sourceName),
    );
    if (destination == null || !mounted) return false;
    setState(() => _pdfEditBusy = true);
    try {
      final result = await const PdfEditedCopyExporter().export(
        sourcePath: sourcePath,
        destinationPath: destination,
        plan: plan,
        contentEdits: contentEdits,
        annotations: widget.annotations,
      );
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.editedCopySaved(
              result.pageCount,
              result.embeddedAnnotationCount,
              result.editedObjectCount,
              result.sizeBytes,
            ),
          ),
          action: SnackBarAction(
            label: strings.showInFolder,
            onPressed: () => unawaited(
              const PicklogicWindowsBridge().revealItem(result.destinationPath),
            ),
          ),
        ),
      );
      return true;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.pdfEditFailed}: $error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _pdfEditBusy = false);
    }
  }

  Future<void> _onTextSelectionChanged(PdfTextSelection selection) async {
    if (!selection.hasSelectedText || !selection.isCopyAllowed) {
      if (mounted && (_selectedText.isNotEmpty || _selectedRanges.isNotEmpty)) {
        setState(() {
          _selectedText = '';
          _selectedRanges = const <PdfPageTextRange>[];
          _selectionLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _selectionLoading = true);
    try {
      final text = (await selection.getSelectedText()).trim();
      final ranges = await selection.getSelectedTextRanges();
      if (mounted) {
        _acceptSelectedText(text, ranges);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _selectedText = '';
          _selectedRanges = const <PdfPageTextRange>[];
        });
      }
    } finally {
      if (mounted) setState(() => _selectionLoading = false);
    }
  }

  void _onTestingSelectionChanged() {
    final text = widget.selectionTextForTesting?.value ?? '';
    _acceptSelectedText(text, const <PdfPageTextRange>[]);
  }

  void _acceptSelectedText(String text, List<PdfPageTextRange> ranges) {
    if (!mounted) return;
    final source = normalizePdfSelectionText(text);
    if (source.isEmpty) {
      setState(() {
        _selectedText = '';
        _selectedRanges = const <PdfPageTextRange>[];
        _selectionLoading = false;
      });
      return;
    }
    _selectionSourceEditDebounce?.cancel();
    setState(() {
      _selectedText = source;
      _selectedRanges = ranges;
      _selectionLoading = false;
      _selectionSourceEditing = false;
    });
    _queueSelectionTranslation(source);
  }

  void _queueSelectionTranslation(
    String source, {
    bool force = false,
    Duration debounce = const Duration(milliseconds: 90),
  }) {
    final normalized = source.trim();
    if (normalized.isEmpty) return;
    if (!force &&
        normalized == _selectionTranslationSource &&
        _selectionTranslationText?.isNotEmpty == true) {
      if (!_bilingualVisible) setState(() => _bilingualVisible = true);
      return;
    }
    _selectionTranslationDebounce?.cancel();
    final generation = ++_selectionTranslationGeneration;
    final disabled =
        widget.translationEngine == TranslationEngineChoice.off &&
        widget.translationProvider.kind == TranslationProviderKind.disabled;
    if (!_selectionSourceEditing &&
        _selectionSourceController.text != normalized) {
      _selectionSourceController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    setState(() {
      _bilingualVisible = true;
      _selectionTranslationSource = normalized;
      _selectionTranslationText = null;
      _selectionTranslationProviderLabel = null;
      _selectionTranslationError = null;
      _selectionTranslationAlternatives = const <TranslationAlternative>[];
      _selectionTranslationDisabled = disabled;
      _selectionTranslationNeedsConfiguration = false;
      _selectionTranslationBusy = !disabled;
    });
    if (disabled) return;
    _selectionTranslationDebounce = Timer(debounce, () {
      unawaited(_translateSelectionAutomatically(normalized, generation));
    });
  }

  Future<void> _translateSelectionAutomatically(
    String source,
    int generation,
  ) async {
    if (!mounted) return;
    try {
      final configured = await widget.translationProvider.isConfigured();
      if (!mounted || generation != _selectionTranslationGeneration) return;
      if (!configured) {
        setState(() {
          _selectionTranslationBusy = false;
          _selectionTranslationNeedsConfiguration = true;
        });
        return;
      }
      final provider = widget.translationProvider;
      if (provider is ProgressiveTranslationProvider) {
        final progressiveProvider = provider as ProgressiveTranslationProvider;
        var receivedResult = false;
        await for (final result
            in progressiveProvider.translateSelectedTextProgressively(
              source,
              targetLanguage: _selectionTargetLanguage(source),
              terminology: _terminologyMap,
            )) {
          if (!mounted || generation != _selectionTranslationGeneration) {
            return;
          }
          receivedResult = true;
          setState(() => _appendSelectionTranslationResult(result));
        }
        if (!mounted || generation != _selectionTranslationGeneration) return;
        if (!receivedResult) {
          throw StateError('No translation source returned a result.');
        }
        setState(() => _selectionTranslationBusy = false);
        return;
      }
      final result = await widget.translationProvider.translateSelectedText(
        source,
        targetLanguage: _selectionTargetLanguage(source),
        terminology: _terminologyMap,
      );
      if (!mounted || generation != _selectionTranslationGeneration) return;
      setState(() {
        _appendSelectionTranslationResult(result);
        _selectionTranslationBusy = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _selectionTranslationGeneration) return;
      setState(() {
        _selectionTranslationBusy = false;
        if (_selectionTranslationText?.trim().isNotEmpty != true) {
          _selectionTranslationError = error.toString();
        }
      });
    }
  }

  void _appendSelectionTranslationResult(SelectedTextTranslation result) {
    final translated = result.translatedText.trim();
    if (translated.isEmpty) return;
    _selectionTranslationError = null;
    final current = _selectionTranslationText?.trim();
    final alternatives = <TranslationAlternative>[
      ..._selectionTranslationAlternatives,
    ];
    final seen = <String>{
      if (current?.isNotEmpty == true) current!.toLowerCase(),
      for (final alternative in alternatives)
        alternative.translatedText.trim().toLowerCase(),
    };
    if (current?.isNotEmpty != true) {
      _selectionTranslationText = translated;
      _selectionTranslationProviderLabel = result.providerLabel;
      seen.add(translated.toLowerCase());
    } else if (seen.add(translated.toLowerCase())) {
      alternatives.add(
        TranslationAlternative(
          label: result.providerLabel,
          translatedText: translated,
        ),
      );
    }
    for (final alternative in result.alternatives) {
      final value = alternative.translatedText.trim();
      if (value.isNotEmpty && seen.add(value.toLowerCase())) {
        alternatives.add(alternative);
      }
    }
    _selectionTranslationAlternatives =
        List<TranslationAlternative>.unmodifiable(alternatives);
  }

  void _retrySelectionTranslation() {
    _queueSelectionTranslation(_selectionTranslationSource, force: true);
  }

  void _startEditingSelectionSource() {
    final source = _selectionTranslationSource.trim();
    if (source.isEmpty) return;
    _selectionSourceController.value = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );
    setState(() => _selectionSourceEditing = true);
  }

  void _onSelectionSourceEdited(String value) {
    _selectionSourceEditDebounce?.cancel();
    final normalized = normalizePdfSelectionText(value);
    if (normalized.isEmpty) return;
    _selectionSourceEditDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || !_selectionSourceEditing) return;
      _queueSelectionTranslation(
        normalized,
        force: true,
        debounce: Duration.zero,
      );
    });
  }

  void _finishEditingSelectionSource() {
    _selectionSourceEditDebounce?.cancel();
    final normalized = normalizePdfSelectionText(
      _selectionSourceController.text,
    );
    setState(() => _selectionSourceEditing = false);
    if (normalized.isNotEmpty &&
        (normalized != _selectionTranslationSource ||
            _selectionTranslationText?.trim().isEmpty == true)) {
      _queueSelectionTranslation(
        normalized,
        force: true,
        debounce: Duration.zero,
      );
    }
  }

  bool get _currentSelectionTranslationLocked {
    final source = _selectionTranslationSource.trim();
    final translated = _selectionTranslationText?.trim() ?? '';
    return source.isNotEmpty &&
        translated.isNotEmpty &&
        _lockedSelectionTranslations.any(
          (item) =>
              item.sourceText == source && item.translatedText == translated,
        );
  }

  void _toggleCurrentSelectionTranslationLock() {
    final source = _selectionTranslationSource.trim();
    final translated = _selectionTranslationText?.trim() ?? '';
    if (source.isEmpty || translated.isEmpty) return;
    final existing = _lockedSelectionTranslations.indexWhere(
      (item) => item.sourceText == source && item.translatedText == translated,
    );
    setState(() {
      if (existing >= 0) {
        _lockedSelectionTranslations.removeAt(existing);
        return;
      }
      _lockedSelectionTranslations.insert(
        0,
        _LockedSelectionTranslation(
          sourceText: source,
          translatedText: translated,
          providerLabel: _selectionTranslationProviderLabel ?? '',
        ),
      );
      if (_lockedSelectionTranslations.length > 6) {
        _lockedSelectionTranslations.removeRange(
          6,
          _lockedSelectionTranslations.length,
        );
      }
    });
  }

  void _removeLockedSelectionTranslation(int index) {
    if (index < 0 || index >= _lockedSelectionTranslations.length) return;
    setState(() => _lockedSelectionTranslations.removeAt(index));
  }

  void _useAlternativeTranslation(int index) {
    if (index < 0 || index >= _selectionTranslationAlternatives.length) return;
    final selected = _selectionTranslationAlternatives[index];
    final previousText = _selectionTranslationText?.trim() ?? '';
    final previousLabel = _selectionTranslationProviderLabel?.trim() ?? '';
    final alternatives = <TranslationAlternative>[
      ..._selectionTranslationAlternatives,
    ]..removeAt(index);
    if (previousText.isNotEmpty) {
      alternatives.add(
        TranslationAlternative(
          label: previousLabel.isEmpty ? 'Previous result' : previousLabel,
          translatedText: previousText,
        ),
      );
    }
    setState(() {
      _selectionTranslationText = selected.translatedText;
      _selectionTranslationProviderLabel = selected.label;
      _selectionTranslationAlternatives =
          List<TranslationAlternative>.unmodifiable(alternatives);
    });
  }

  void _toggleThumbnails() {
    final visible = !_thumbnailsVisible;
    setState(() => _thumbnailsVisible = visible);
    widget.onThumbnailsVisibilityChanged?.call(visible);
  }

  Future<void> _changeTranslationEngine(TranslationEngineChoice choice) async {
    if (choice == widget.translationEngine) return;
    _selectionTranslationDebounce?.cancel();
    _selectionTranslationGeneration++;
    setState(() {
      _selectionTranslationBusy = false;
      _selectionTranslationText = null;
      _selectionTranslationProviderLabel = null;
      _selectionTranslationError = null;
      _selectionTranslationAlternatives = const <TranslationAlternative>[];
      _selectionTranslationDisabled = choice == TranslationEngineChoice.off;
      _selectionTranslationNeedsConfiguration = false;
    });
    await widget.onTranslationEngineChanged?.call(choice);
    if (mounted &&
        choice != TranslationEngineChoice.off &&
        _selectionTranslationSource.trim().isNotEmpty) {
      _retrySelectionTranslation();
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

  Future<bool> _ensureTranslationConfigured(_PdfReaderStrings strings) async {
    final configured = await widget.translationProvider.isConfigured();
    if (!mounted) return false;
    if (configured) return true;
    if (widget.translationEngine == TranslationEngineChoice.off) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.translationDisabled)));
      return false;
    }
    final configure = widget.onConfigureTranslation;
    if (configure != null) {
      await configure();
      if (!mounted) return false;
      final nowConfigured = await widget.translationProvider.isConfigured();
      if (!mounted) return false;
      if (nowConfigured) return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.translationNeedsConfiguration)),
    );
    return false;
  }

  Future<String?> _extractPageText(int pageNumber) async {
    final document = _document;
    if (document == null ||
        pageNumber < 1 ||
        pageNumber > document.pages.length) {
      return null;
    }
    final text = await document.pages[pageNumber - 1].loadStructuredText();
    final value = text.fullText.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _translateCurrentPage() async {
    final strings = _PdfReaderStrings.of(context);
    if (_translationBusy || _documentTranslationBusy) return;
    if (!await _ensureTranslationConfigured(strings)) return;
    setState(() {
      _translationBusy = true;
      _bilingualVisible = true;
    });
    try {
      await _translatePage(_pageNumber, strings);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.pageTranslationFailed}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _translationBusy = false);
    }
  }

  Future<bool> _translatePage(int pageNumber, _PdfReaderStrings strings) async {
    if (_pageTranslations.containsKey(pageNumber)) return true;
    final source = await _extractPageText(pageNumber);
    if (source == null) {
      if (mounted && pageNumber == _pageNumber) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.noExtractablePageText)));
      }
      return false;
    }
    final result = await widget.translationProvider
        .translateExplicitTextInChunks(
          source,
          targetLanguage: _targetLanguage(strings),
          maxChunkCharacters:
              widget.translationProvider.kind ==
                  TranslationProviderKind.publicAnonymous
              ? 500
              : 6000,
          terminology: _terminologyMap,
        );
    if (!mounted) return false;
    final memory = LiteraturePageTranslation(
      literatureId: widget.literatureId,
      pageNumber: pageNumber,
      targetLanguage: result.targetLanguage,
      sourceText: source,
      translatedText: result.translatedText,
      providerLabel: result.providerLabel,
      updatedAt: DateTime.now().toUtc(),
    );
    final store = widget.translationStore;
    if (store != null && widget.literatureId.isNotEmpty) {
      try {
        await store.upsertPage(memory);
      } on Object {
        // Keep the in-session translation even when optional persistence fails.
      }
    }
    if (!mounted) return false;
    setState(() {
      _pageTranslationSources[pageNumber] = source;
      _pageTranslations[pageNumber] = result.translatedText;
    });
    return true;
  }

  Future<void> _retranslateCurrentPage() async {
    final strings = _PdfReaderStrings.of(context);
    if (_translationBusy || _documentTranslationBusy) return;
    setState(() {
      _pageTranslations.remove(_pageNumber);
      _pageTranslationSources.remove(_pageNumber);
      _translationBusy = true;
    });
    try {
      final store = widget.translationStore;
      if (store != null && widget.literatureId.isNotEmpty) {
        await store.deletePage(
          literatureId: widget.literatureId,
          pageNumber: _pageNumber,
          targetLanguage: _targetLanguage(strings),
        );
      }
      await _translatePage(_pageNumber, strings);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.pageTranslationFailed}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _translationBusy = false);
    }
  }

  Future<void> _translateDocument() async {
    final document = _document;
    final strings = _PdfReaderStrings.of(context);
    if (document == null || _documentTranslationBusy || _translationBusy) {
      return;
    }
    if (!await _ensureTranslationConfigured(strings)) return;
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('pdf-translate-document-confirmation'),
        title: Text(strings.translateDocument),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            strings.translateDocumentDisclosure(document.pages.length),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('pdf-confirm-translate-document-action'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.startTranslation),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      _documentTranslationBusy = true;
      _cancelDocumentTranslation = false;
      _translationProgress = 0;
      _translationTotal = document.pages.length;
      _bilingualVisible = true;
    });
    var translated = 0;
    try {
      for (var page = 1; page <= document.pages.length; page++) {
        if (_cancelDocumentTranslation) break;
        if (await _translatePage(page, strings)) translated++;
        if (!mounted) return;
        setState(() => _translationProgress = page);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _cancelDocumentTranslation
                ? strings.documentTranslationStopped(
                    translated,
                    document.pages.length,
                  )
                : strings.documentTranslationComplete(
                    translated,
                    document.pages.length,
                  ),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${strings.documentTranslationFailed}: $error'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _documentTranslationBusy = false;
          _cancelDocumentTranslation = false;
        });
      }
    }
  }

  List<LiteratureAnnotationBox> _annotationBoxesFromSelection() {
    final boxes = <LiteratureAnnotationBox>[];
    for (final range in _selectedRanges) {
      final fragments = range.enumerateFragmentBoundingRects().toList();
      final bounds = fragments.isEmpty
          ? <PdfRect>[range.bounds]
          : fragments.map((fragment) => fragment.bounds);
      for (final box in bounds) {
        if (box.isEmpty) continue;
        boxes.add(
          LiteratureAnnotationBox(
            pageNumber: range.pageNumber,
            left: box.left,
            top: box.top,
            right: box.right,
            bottom: box.bottom,
          ),
        );
      }
    }
    return List<LiteratureAnnotationBox>.unmodifiable(boxes);
  }

  Future<void> _saveSelectionAsAnnotation() async {
    final save = widget.onSaveAnnotation;
    final source = _selectedText.trim();
    if (save == null || widget.literatureId.isEmpty || source.isEmpty) return;
    final strings = _PdfReaderStrings.of(context);
    final noteController = TextEditingController();
    LiteratureAnnotationKind kind = LiteratureAnnotationKind.highlight;
    var colorName = 'yellow';
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            key: const Key('pdf-annotation-editor'),
            title: Text(strings.saveAnnotation),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(source, maxLines: 5, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<LiteratureAnnotationKind>(
                    initialValue: kind,
                    decoration: InputDecoration(
                      labelText: strings.annotationStyle,
                    ),
                    items: [
                      for (final value in LiteratureAnnotationKind.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(strings.annotationKind(value)),
                        ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => kind = value ?? LiteratureAnnotationKind.highlight,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final color in const [
                        'yellow',
                        'green',
                        'blue',
                        'pink',
                      ])
                        ChoiceChip(
                          label: Text(strings.annotationColor(color)),
                          selected: colorName == color,
                          onSelected: (_) =>
                              setDialogState(() => colorName = color),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('pdf-annotation-note-field'),
                    controller: noteController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: strings.annotationNote,
                      hintText: strings.annotationNoteHint,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                key: const Key('pdf-save-annotation-action'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(strings.save),
              ),
            ],
          ),
        ),
      );
      if (accepted != true || !mounted) return;
      setState(() => _annotationBusy = true);
      final now = DateTime.now().toUtc();
      final boxes = _annotationBoxesFromSelection();
      await save(
        LiteratureAnnotation(
          id: 'annotation-${now.microsecondsSinceEpoch}',
          literatureId: widget.literatureId,
          pageNumber: boxes.firstOrNull?.pageNumber ?? _pageNumber,
          kind: kind,
          selectedText: source,
          note: noteController.text.trim(),
          colorName: colorName,
          createdAt: now,
          updatedAt: now,
          boxes: boxes,
        ),
      );
      if (!mounted) return;
      setState(() => _annotationsVisible = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.annotationSaved)));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.annotationSaveFailed}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _annotationBusy = false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      noteController.dispose();
    }
  }

  Future<void> _deleteAnnotation(LiteratureAnnotation annotation) async {
    final remove = widget.onDeleteAnnotation;
    if (remove == null || _annotationBusy) return;
    final strings = _PdfReaderStrings.of(context);
    setState(() => _annotationBusy = true);
    try {
      await remove(annotation.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.annotationDeleted)));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.annotationDeleteFailed}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _annotationBusy = false);
    }
  }

  Widget _buildReaderToolbar(
    _PdfReaderStrings strings, {
    required String matchLabel,
    required String zoomLabel,
  }) {
    final document = _document;
    final searcher = _searcher;
    return Material(
      key: const Key('pdf-reader-toolbar'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1200;
            final localStatus = Tooltip(
              key: const Key('pdf-local-status'),
              message: widget.isSynthetic
                  ? strings.syntheticDescription
                  : strings.localDescription,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    strings.localRendering,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            );
            final searchControls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: compact ? 150 : 190,
                  child: TextField(
                    key: const Key('pdf-search-field'),
                    controller: _searchController,
                    enabled: searcher != null,
                    decoration: InputDecoration(
                      labelText: strings.searchPdfText,
                      hintText: strings.searchHint,
                      prefixIcon: const Icon(Icons.search, size: 19),
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
                if (!compact)
                  SizedBox(
                    width: 72,
                    child: Text(
                      matchLabel,
                      key: const Key('pdf-search-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  Offstage(
                    child: Text(
                      matchLabel,
                      key: const Key('pdf-search-status'),
                    ),
                  ),
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
              ],
            );
            final zoomControls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('pdf-zoom-out'),
                  tooltip: strings.zoomOut,
                  onPressed: _contentEditing || _viewerController.isReady
                      ? _zoomOut
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    zoomLabel,
                    key: const Key('pdf-zoom-status'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                IconButton(
                  key: const Key('pdf-zoom-in'),
                  tooltip: strings.zoomIn,
                  onPressed: _contentEditing || _viewerController.isReady
                      ? _zoomIn
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            );
            final pageControls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 74,
                  child: TextField(
                    key: const Key('pdf-page-jump-field'),
                    controller: _pageController,
                    enabled: document != null,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: strings.jumpToPage),
                    onSubmitted: (_) => _jumpToPage(),
                  ),
                ),
                IconButton(
                  key: const Key('pdf-page-jump-action'),
                  tooltip: strings.jump,
                  onPressed: document == null ? null : _jumpToPage,
                  icon: const Icon(Icons.arrow_forward),
                ),
                if (!compact)
                  SizedBox(
                    width: 82,
                    child: Text(
                      document == null
                          ? (_loadSucceeded
                                ? strings.preparingPages
                                : strings.loadingPdf)
                          : strings.pagePosition(
                              _pageNumber,
                              document.pages.length,
                            ),
                      key: const Key('pdf-page-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  Offstage(
                    child: Text(
                      document == null
                          ? strings.loadingPdf
                          : strings.pagePosition(
                              _pageNumber,
                              document.pages.length,
                            ),
                      key: const Key('pdf-page-status'),
                    ),
                  ),
              ],
            );
            final readingControls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('pdf-toggle-thumbnails-action'),
                  tooltip: _thumbnailsVisible
                      ? strings.hidePageThumbnails
                      : strings.showPageThumbnails,
                  isSelected: _thumbnailsVisible,
                  onPressed: _toggleThumbnails,
                  icon: Icon(
                    _thumbnailsVisible
                        ? Icons.view_sidebar
                        : Icons.view_sidebar_outlined,
                  ),
                ),
                MenuAnchor(
                  menuChildren: [
                    MenuItemButton(
                      key: const Key('pdf-edit-content-action'),
                      onPressed: _editPdfContent,
                      leadingIcon: Icon(
                        _contentEditing
                            ? Icons.check_circle_outline
                            : Icons.edit_note_outlined,
                      ),
                      child: Text(
                        _contentEditing
                            ? strings.finishEditing
                            : strings.editPdfContent,
                      ),
                    ),
                    MenuItemButton(
                      key: const Key('pdf-edit-pages-action'),
                      onPressed: _editPdfCopy,
                      leadingIcon: const Icon(Icons.view_carousel_outlined),
                      child: Text(strings.organizePdfPages),
                    ),
                  ],
                  builder: (context, controller, child) {
                    final canEdit =
                        widget.filePath != null &&
                        document != null &&
                        !_pdfEditBusy;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: _contentEditing
                              ? strings.finishEditing
                              : strings.editPdfContent,
                          child: FilledButton.tonalIcon(
                            key: const Key('pdf-edit-copy-action'),
                            onPressed: canEdit ? _editPdfContent : null,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.horizontal(
                                  left: Radius.circular(12),
                                ),
                              ),
                            ),
                            icon: _pdfEditBusy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _contentEditing
                                        ? Icons.check_circle_outline
                                        : Icons.edit_document,
                                  ),
                            label: Text(
                              _contentEditing
                                  ? strings.finishEditing
                                  : strings.editPdf,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 34,
                          child: Tooltip(
                            message: strings.morePdfEditActions,
                            child: FilledButton.tonal(
                              key: const Key('pdf-edit-menu-action'),
                              onPressed: canEdit && !_contentEditing
                                  ? () => controller.isOpen
                                        ? controller.close()
                                        : controller.open()
                                  : null,
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                minimumSize: const Size(34, 40),
                                padding: EdgeInsets.zero,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.horizontal(
                                    right: Radius.circular(12),
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.arrow_drop_down,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('pdf-toggle-annotations-action'),
                  onPressed:
                      widget.annotations.isNotEmpty ||
                          widget.onSaveAnnotation != null
                      ? () => setState(
                          () => _annotationsVisible = !_annotationsVisible,
                        )
                      : null,
                  tooltip: strings.annotations(widget.annotations.length),
                  isSelected: _annotationsVisible,
                  icon: Icon(
                    _annotationsVisible ? Icons.notes : Icons.notes_outlined,
                  ),
                ),
                IconButton(
                  key: const Key('pdf-bilingual-toggle-action'),
                  onPressed: () =>
                      setState(() => _bilingualVisible = !_bilingualVisible),
                  tooltip: strings.bilingualReading,
                  isSelected: _bilingualVisible,
                  icon: const Icon(Icons.chrome_reader_mode_outlined),
                ),
                MenuAnchor(
                  key: const Key('pdf-translation-menu'),
                  menuChildren: [
                    MenuItemButton(
                      key: const Key('pdf-translate-page-action'),
                      onPressed:
                          document == null ||
                              _translationBusy ||
                              _documentTranslationBusy
                          ? null
                          : _translateCurrentPage,
                      leadingIcon: const Icon(Icons.translate_outlined),
                      child: Text(strings.translateCurrentPage),
                    ),
                    if (_documentTranslationBusy)
                      MenuItemButton(
                        key: const Key('pdf-stop-document-translation-action'),
                        onPressed: () =>
                            setState(() => _cancelDocumentTranslation = true),
                        leadingIcon: const Icon(Icons.stop_circle_outlined),
                        child: Text(strings.stopTranslation),
                      )
                    else
                      MenuItemButton(
                        key: const Key('pdf-translate-document-action'),
                        onPressed: document == null ? null : _translateDocument,
                        leadingIcon: const Icon(Icons.auto_stories_outlined),
                        child: Text(strings.translateDocument),
                      ),
                    if (widget.translationStore != null)
                      MenuItemButton(
                        key: const Key('pdf-terminology-action'),
                        onPressed: _showTerminologyEditor,
                        leadingIcon: const Icon(Icons.spellcheck_outlined),
                        child: Text(strings.terminology),
                      ),
                  ],
                  builder: (context, controller, child) =>
                      IconButton.filledTonal(
                        onPressed: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        tooltip: strings.translationTools,
                        icon: const Icon(Icons.translate),
                      ),
                ),
              ],
            );
            if (compact) {
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  localStatus,
                  searchControls,
                  zoomControls,
                  pageControls,
                  readingControls,
                ],
              );
            }
            return Row(
              children: [
                localStatus,
                const SizedBox(width: 10),
                searchControls,
                const SizedBox(height: 24, child: VerticalDivider(width: 14)),
                zoomControls,
                const SizedBox(height: 24, child: VerticalDivider(width: 14)),
                pageControls,
                const Spacer(),
                readingControls,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectionToolbar(_PdfReaderStrings strings) => Material(
    key: const Key('pdf-selection-toolbar'),
    color: Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (_selectionLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Chip(
              key: const Key('pdf-selection-status'),
              avatar: const Icon(Icons.text_fields, size: 16),
              label: Text(strings.selectedCharacters(_selectedText.length)),
            ),
          const SizedBox(width: 4),
          TextButton.icon(
            key: const Key('pdf-copy-selection-action'),
            onPressed: _selectedText.isEmpty ? null : _copySelection,
            icon: const Icon(Icons.copy_outlined),
            label: Text(strings.copySelection),
          ),
          Chip(
            key: const Key('pdf-selection-auto-translation-status'),
            avatar: _selectionTranslationBusy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.translate, size: 16),
            label: Text(
              _selectionTranslationBusy
                  ? strings.translatingSelection
                  : strings.selectionAutoTranslate,
            ),
          ),
          TextButton.icon(
            key: const Key('pdf-annotate-selection-action'),
            onPressed:
                _selectedText.isEmpty ||
                    widget.onSaveAnnotation == null ||
                    _annotationBusy
                ? null
                : _saveSelectionAsAnnotation,
            icon: const Icon(Icons.highlight_outlined),
            label: Text(strings.saveAnnotation),
          ),
        ],
      ),
    ),
  );

  Widget _buildDocumentTranslationProgress(_PdfReaderStrings strings) =>
      Material(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: _translationTotal == 0
                      ? null
                      : _translationProgress / _translationTotal,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                strings.translationProgress(
                  _translationProgress,
                  _translationTotal,
                ),
                key: const Key('pdf-document-translation-progress'),
              ),
              IconButton(
                key: const Key('pdf-stop-document-translation-action'),
                tooltip: strings.stopTranslation,
                onPressed: () =>
                    setState(() => _cancelDocumentTranslation = true),
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ),
        ),
      );

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
    final activeZoom = _contentEditing ? _contentEditZoom : _zoom;
    final zoomLabel = activeZoom == null
        ? strings.zoomPreparing
        : '${(activeZoom * 100).round()}%';

    return Column(
      key: const Key('pro-pdf-reader'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildReaderToolbar(
          strings,
          matchLabel: matchLabel,
          zoomLabel: zoomLabel,
        ),
        if (_selectionLoading || _selectedText.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildSelectionToolbar(strings),
        ],
        if (_documentTranslationBusy) ...[
          const SizedBox(height: 6),
          _buildDocumentTranslationProgress(strings),
        ],
        if (_pageJumpInvalid) ...[
          const SizedBox(height: 4),
          Text(
            strings.pageRange(document?.pages.length ?? 1),
            key: const Key('pdf-page-jump-error'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              if (_thumbnailsVisible) ...[
                SizedBox(
                  key: const Key('pdf-thumbnail-pane'),
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
                                onTap: () {
                                  if (_contentEditing) {
                                    _contentEditorController.goToPage(page);
                                  } else {
                                    unawaited(
                                      _viewerController.goToPage(
                                        pageNumber: page,
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  height: 96,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: selected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
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
                                                  ?.copyWith(
                                                    color: Colors.white,
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
                const VerticalDivider(width: 10),
              ],
              if (_annotationsVisible) ...[
                SizedBox(width: 240, child: _buildAnnotationPanel(strings)),
                const VerticalDivider(width: 10),
              ],
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: IndexedStack(
                          key: const Key('pdf-reader-mode-stack'),
                          index: _contentEditing ? 1 : 0,
                          sizing: StackFit.expand,
                          children: [
                            _buildViewer(),
                            if (_contentEditing && document != null)
                              PdfContentEditorDialog.readerSurface(
                                key: ValueKey(
                                  'pdf-reader-surface-editor-${widget.sourceName}',
                                ),
                                document: document,
                                initialPageNumber: _pageNumber,
                                initialZoom: _contentEditZoom ?? _zoom,
                                initialViewportFraction:
                                    _contentEditViewportFraction,
                                controller: _contentEditorController,
                                onClosed: _onContentEditorClosed,
                                onPageChanged: _onContentEditorPageChanged,
                                onZoomChanged: _onContentEditorZoomChanged,
                                onSaveRequested: (contentPlan) =>
                                    _saveEditedPdfCopy(
                                      plan: PdfEditPlan.identity(
                                        document.pages.length,
                                      ),
                                      contentEdits: contentPlan,
                                    ),
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                    if (_bilingualVisible && !_contentEditing) ...[
                      const VerticalDivider(width: 10),
                      SizedBox(
                        width: 380,
                        child: _buildTranslationPanel(strings),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnnotationPanel(_PdfReaderStrings strings) {
    final annotations = widget.annotations;
    return Material(
      key: const Key('pdf-annotation-panel'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    strings.annotations(annotations.length),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: strings.close,
                  onPressed: () => setState(() => _annotationsVisible = false),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: annotations.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        strings.noAnnotations,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: annotations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final annotation = annotations[index];
                      return ListTile(
                        key: Key('pdf-annotation-${annotation.id}'),
                        dense: true,
                        leading: Icon(switch (annotation.kind) {
                          LiteratureAnnotationKind.highlight =>
                            Icons.highlight_outlined,
                          LiteratureAnnotationKind.underline =>
                            Icons.format_underlined_outlined,
                          LiteratureAnnotationKind.strikethrough =>
                            Icons.format_strikethrough_outlined,
                          LiteratureAnnotationKind.note =>
                            Icons.note_alt_outlined,
                        }),
                        title: Text(
                          annotation.selectedText.isEmpty
                              ? annotation.note
                              : annotation.selectedText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          annotation.note.isEmpty
                              ? strings.page(annotation.pageNumber)
                              : '${strings.page(annotation.pageNumber)} · ${annotation.note}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: widget.onDeleteAnnotation == null
                            ? null
                            : IconButton(
                                tooltip: strings.deleteAnnotation,
                                onPressed: _annotationBusy
                                    ? null
                                    : () => _deleteAnnotation(annotation),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                              ),
                        onTap: _viewerController.isReady
                            ? () => _viewerController.goToPage(
                                pageNumber: annotation.pageNumber,
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslationEngineSelector(_PdfReaderStrings strings) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.translate, size: 17),
              const SizedBox(width: 7),
              Text(
                strings.translationEngine,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TranslationEngineChoice>(
                    key: const Key('pdf-translation-engine-selector'),
                    value: widget.translationEngine,
                    isDense: true,
                    isExpanded: true,
                    items: TranslationEngineChoice.values
                        .map(
                          (choice) => DropdownMenuItem(
                            key: Key('pdf-translation-engine-${choice.name}'),
                            value: choice,
                            child: Text(
                              strings.translationEngineName(choice),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _translationBusy || _documentTranslationBusy
                        ? null
                        : (choice) {
                            if (choice != null) {
                              unawaited(_changeTranslationEngine(choice));
                            }
                          },
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildTranslationPanel(_PdfReaderStrings strings) {
    final selectionSource = _selectionTranslationSource.trim();
    final selectionTranslation = _selectionTranslationText?.trim();
    final showingSelection = selectionSource.isNotEmpty;
    final translation = _pageTranslations[_pageNumber];
    final source = _pageTranslationSources[_pageNumber];
    return Material(
      key: const Key('pdf-bilingual-panel'),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        showingSelection
                            ? strings.selectionTranslation
                            : strings.translatedPage(_pageNumber),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (showingSelection &&
                        selectionTranslation?.isNotEmpty == true)
                      IconButton(
                        key: const Key('pdf-copy-selection-translation-action'),
                        tooltip: strings.copyTranslation,
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: selectionTranslation!),
                        ),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                      ),
                    if (showingSelection)
                      IconButton(
                        key: const Key('pdf-show-page-translation-action'),
                        tooltip: strings.showPageTranslation,
                        onPressed: () => setState(() {
                          _selectionTranslationSource = '';
                          _selectionTranslationText = null;
                          _selectionTranslationProviderLabel = null;
                          _selectionTranslationError = null;
                          _selectionTranslationAlternatives =
                              const <TranslationAlternative>[];
                          _selectionTranslationNeedsConfiguration = false;
                        }),
                        icon: const Icon(Icons.article_outlined, size: 18),
                      )
                    else if (translation != null)
                      IconButton(
                        key: const Key('pdf-retranslate-page-action'),
                        tooltip: strings.retranslate,
                        onPressed: _translationBusy || _documentTranslationBusy
                            ? null
                            : _retranslateCurrentPage,
                        icon: const Icon(Icons.refresh, size: 18),
                      ),
                    IconButton(
                      tooltip: strings.close,
                      onPressed: () =>
                          setState(() => _bilingualVisible = false),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                if (widget.translationEngine != null &&
                    widget.onTranslationEngineChanged != null) ...[
                  const SizedBox(height: 4),
                  _buildTranslationEngineSelector(strings),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: showingSelection
                ? _buildSelectionTranslationBody(
                    strings,
                    source: selectionSource,
                    translated: selectionTranslation,
                  )
                : translation == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            strings.pageNotTranslated,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed:
                                _translationBusy || _documentTranslationBusy
                                ? null
                                : _translateCurrentPage,
                            icon: const Icon(Icons.translate_outlined),
                            label: Text(strings.translateCurrentPage),
                          ),
                        ],
                      ),
                    ),
                  )
                : SelectionArea(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (source?.trim().isNotEmpty == true) ...[
                          Text(
                            strings.originalText,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            source!,
                            key: const Key('pdf-page-translation-source'),
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(height: 1.5),
                          ),
                          const Divider(height: 28),
                        ],
                        Text(
                          strings.translatedText,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          translation,
                          key: const Key('pdf-page-translation-text'),
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(height: 1.65),
                        ),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Text(
              '${strings.translationPrivacyForEngine(widget.translationEngine)} ${strings.translationMemory}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionTranslationBody(
    _PdfReaderStrings strings, {
    required String source,
    required String? translated,
  }) {
    final currentIsLocked = _currentSelectionTranslationLocked;
    final lockedToShow = _lockedSelectionTranslations
        .where(
          (item) =>
              item.sourceText != source || item.translatedText != translated,
        )
        .toList(growable: false);
    return ListView(
      key: const Key('pdf-selection-translation-panel'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.selectedOriginal,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              key: const Key('pdf-edit-selection-source-action'),
              tooltip: _selectionSourceEditing
                  ? strings.finishEditingSource
                  : strings.editSelectedText,
              onPressed: _selectionSourceEditing
                  ? _finishEditingSelectionSource
                  : _startEditingSelectionSource,
              icon: Icon(
                _selectionSourceEditing ? Icons.check : Icons.edit_outlined,
                size: 18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          key: const Key('pdf-selection-translation-source'),
          controller: _selectionSourceController,
          readOnly: !_selectionSourceEditing,
          minLines: 1,
          maxLines: 6,
          onChanged: _onSelectionSourceEdited,
          decoration: InputDecoration(
            isDense: true,
            filled: _selectionSourceEditing,
            hintText: strings.editSelectedTextHint,
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        if (_selectionSourceEditing) ...[
          const SizedBox(height: 6),
          Text(
            strings.sourceEditsAutoTranslate,
            key: const Key('pdf-selection-source-edit-hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const Divider(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                strings.translatedText,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            if (translated?.isNotEmpty == true)
              IconButton(
                key: const Key('pdf-lock-selection-translation-action'),
                tooltip: currentIsLocked
                    ? strings.unlockTranslation
                    : strings.lockTranslation,
                onPressed: _toggleCurrentSelectionTranslationLock,
                icon: Icon(
                  currentIsLocked ? Icons.lock : Icons.lock_outline,
                  size: 18,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectionTranslationDisabled) ...[
          DecoratedBox(
            key: const Key('pdf-selection-translation-disabled'),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(strings.translationDisabled),
            ),
          ),
        ] else if (_selectionTranslationNeedsConfiguration) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.tune,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      strings.translationNeedsConfiguration,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (widget.onConfigureTranslation != null) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: strings.configureTranslation,
                      child: TextButton(
                        key: const Key(
                          'pdf-configure-selection-translation-action',
                        ),
                        onPressed: () async {
                          await widget.onConfigureTranslation?.call();
                          if (mounted) _retrySelectionTranslation();
                        },
                        child: Text(strings.configureTranslationShort),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ] else if (_selectionTranslationError != null &&
            translated?.isNotEmpty != true) ...[
          Text(
            '${strings.translationFailed}: $_selectionTranslationError',
            key: const Key('pdf-selection-translation-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('pdf-retry-selection-translation-action'),
              onPressed: _retrySelectionTranslation,
              icon: const Icon(Icons.refresh),
              label: Text(strings.retryTranslation),
            ),
          ),
        ] else if (translated?.isNotEmpty == true) ...[
          Card(
            key: const Key('pdf-selection-primary-translation-card'),
            margin: EdgeInsets.zero,
            elevation: 0,
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selectionTranslationProviderLabel?.isNotEmpty == true)
                      Text(
                        strings.translationSourceLabel(
                          _selectionTranslationProviderLabel!,
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    const SizedBox(height: 5),
                    Text(
                      translated!,
                      key: const Key('pdf-selection-translation-text'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.65),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_selectionTranslationBusy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              key: Key('pdf-selection-translation-loading'),
              minHeight: 2,
            ),
            const SizedBox(height: 6),
            Text(
              strings.comparingTranslationSources,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ] else if (_selectionTranslationBusy) ...[
          const LinearProgressIndicator(
            key: Key('pdf-selection-translation-loading'),
          ),
          const SizedBox(height: 10),
          Text(strings.translatingSelection),
        ],
        if (translated?.isNotEmpty == true &&
            _selectionTranslationAlternatives.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            strings.alternativeTranslations,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          for (
            var index = 0;
            index < _selectionTranslationAlternatives.length;
            index++
          )
            Card(
              key: Key('pdf-selection-translation-alternative-$index'),
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.translationSourceLabel(
                              _selectionTranslationAlternatives[index].label,
                            ),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        TextButton(
                          key: Key(
                            'pdf-use-selection-translation-alternative-$index',
                          ),
                          onPressed: () => _useAlternativeTranslation(index),
                          child: Text(strings.useTranslation),
                        ),
                      ],
                    ),
                    SelectionArea(
                      child: Text(
                        _selectionTranslationAlternatives[index].translatedText,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (lockedToShow.isNotEmpty) ...[
          const Divider(height: 30),
          Text(
            strings.lockedTranslations(lockedToShow.length),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < lockedToShow.length; index++)
            Card(
              key: Key('pdf-locked-selection-translation-$index'),
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_outline, size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              lockedToShow[index].sourceText,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              lockedToShow[index].translatedText,
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(height: 1.45),
                            ),
                            if (lockedToShow[index]
                                .providerLabel
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                strings.translationSourceLabel(
                                  lockedToShow[index].providerLabel,
                                ),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: strings.copyTranslation,
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: lockedToShow[index].translatedText),
                      ),
                      icon: const Icon(Icons.copy_outlined, size: 17),
                    ),
                    IconButton(
                      key: Key('pdf-remove-locked-translation-$index'),
                      tooltip: strings.removeLockedTranslation,
                      onPressed: () {
                        final originalIndex = _lockedSelectionTranslations
                            .indexOf(lockedToShow[index]);
                        _removeLockedSelectionTranslation(originalIndex);
                      },
                      icon: const Icon(Icons.close, size: 17),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
      pagePaintCallbacks: [_paintAnnotations, _paintSearchMatches],
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
    return PdfViewer(
      buildProLocalPdfDocumentRef(widget.filePath!),
      // The full local file is already available. Disabling progressive range
      // access avoids leaving some Windows PDFium builds waiting indefinitely
      // on the first page while preserving bounded page rendering and cache.
      controller: _viewerController,
      params: params,
    );
  }
}

String _suggestedEditedFileName(String sourceName) {
  final fileName = sourceName
      .split(RegExp(r'[\\/]'))
      .where((part) => part.isNotEmpty)
      .last;
  final stem = fileName.toLowerCase().endsWith('.pdf')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;
  return '$stem - edited.pdf';
}

final class _LockedSelectionTranslation {
  const _LockedSelectionTranslation({
    required this.sourceText,
    required this.translatedText,
    required this.providerLabel,
  });

  final String sourceText;
  final String translatedText;
  final String providerLabel;
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
  String get editPdf => isChinese ? '编辑 PDF' : 'Edit PDF';
  String get editPdfContent => isChinese ? '编辑文字和图片' : 'Edit text and images';
  String get finishEditing => isChinese ? '完成编辑' : 'Done editing';
  String get morePdfEditActions =>
      isChinese ? '更多 PDF 编辑选项' : 'More PDF editing options';
  String get organizePdfPages =>
      isChinese ? '整理、旋转和删除页面' : 'Organize, rotate, and remove pages';
  String get saveEditedCopy =>
      isChinese ? '另存编辑后的 PDF' : 'Save edited PDF copy';
  String get showInFolder => isChinese ? '在文件夹中显示' : 'Show in folder';
  String get pdfEditFailed =>
      isChinese ? 'PDF 编辑副本保存失败' : 'Could not save edited PDF copy';
  String editedCopySaved(
    int pages,
    int annotations,
    int editedObjects,
    int bytes,
  ) {
    final size = bytes >= 1024 * 1024
        ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).toStringAsFixed(1)} KB';
    return isChinese
        ? '已保存 $pages 页编辑副本，修改 $editedObjects 个页面对象、写入 $annotations 条批注（$size）。原 PDF 未修改。'
        : 'Saved a $pages-page copy with $editedObjects object edits and $annotations embedded annotations ($size). The source PDF was unchanged.';
  }

  String get localRendering => isChinese ? '本地渲染' : 'Local rendering';
  String get capabilities =>
      isChinese ? '滚动 / 缩放 / 选择 / 复制' : 'Scroll / zoom / select / copy';
  String cacheLimit(int mebibytes) =>
      isChinese ? '缓存上限 $mebibytes MiB' : 'Cache limit $mebibytes MiB';
  String get syntheticDescription => isChinese
      ? '运行时生成的合成 PDF；未读取、上传或修改真实文献。'
      : 'Runtime-generated synthetic PDF; no real literature was read, uploaded, or modified.';
  String get localDescription => isChinese
      ? '原 PDF 保持只读：不上传、不改写；页面编辑和批注可另存为新 PDF。'
      : 'The source PDF remains read-only: no upload, rewrite, or overwrite; page edits and annotations can be saved as a new PDF.';
  String get searchPdfText => isChinese ? '搜索 PDF 文本' : 'Search PDF text';
  String get searchHint => isChinese ? '输入关键词' : 'Enter keywords';
  String get search => isChinese ? '搜索' : 'Search';
  String get previousMatch => isChinese ? '上一个匹配' : 'Previous match';
  String get nextMatch => isChinese ? '下一个匹配' : 'Next match';
  String get zoomOut => isChinese ? '缩小' : 'Zoom out';
  String get zoomIn => isChinese ? '放大' : 'Zoom in';
  String get hidePageThumbnails =>
      isChinese ? '收起页面缩略图' : 'Hide page thumbnails';
  String get showPageThumbnails =>
      isChinese ? '显示页面缩略图' : 'Show page thumbnails';
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
  String get selectionAutoTranslate =>
      isChinese ? '已自动送入右侧翻译' : 'Auto-translating in sidebar';
  String get translatingSelection =>
      isChinese ? '正在翻译所选文字…' : 'Translating selection…';
  String get selectionTranslation =>
      isChinese ? '划词翻译' : 'Selection translation';
  String get translationEngine => isChinese ? '翻译引擎' : 'Engine';
  String translationEngineName(TranslationEngineChoice choice) =>
      switch (choice) {
        TranslationEngineChoice.off =>
          isChinese ? '选择翻译引擎…' : 'Choose an engine…',
        TranslationEngineChoice.aggregate =>
          isChinese ? '聚合快译 · 推荐' : 'Fast aggregate · Recommended',
        TranslationEngineChoice.instant =>
          isChinese ? 'MyMemory · 单引擎' : 'MyMemory · Single engine',
        TranslationEngineChoice.openAiCompatible =>
          isChinese ? 'AI 模型 · 高级' : 'AI model · Advanced',
      };
  String get translationDisabled => isChinese
      ? '选择上方“聚合快译”即可使用本地术语、缓存和公共翻译记忆，不需要 API、端点或模型设置。选择会被记住。'
      : 'Choose Fast aggregate above for local terminology, cache, and public translation memory without an API key, endpoint, or model setup. Your choice is remembered.';
  String get selectedOriginal => isChinese ? '所选原文' : 'Selected text';
  String get editSelectedText =>
      isChinese ? '修正识别原文' : 'Correct extracted text';
  String get finishEditingSource => isChinese ? '完成修正' : 'Finish correction';
  String get editSelectedTextHint => isChinese
      ? '可直接修正断行、连字符或识别错误'
      : 'Correct line breaks, hyphenation, or extraction errors';
  String get sourceEditsAutoTranslate => isChinese
      ? '停止输入后会自动重新翻译，无需再次确认。'
      : 'Translation refreshes automatically when you pause typing.';
  String get showPageTranslation =>
      isChinese ? '切换到整页译文' : 'Show page translation';
  String get configureTranslation =>
      isChinese ? '配置一次翻译服务' : 'Configure translation once';
  String get configureTranslationShort => isChinese ? '设置' : 'Set up';
  String get retryTranslation => isChinese ? '重试翻译' : 'Retry translation';
  String translationProvider(String provider) {
    final localized = provider
        .split(' + ')
        .map(translationSourceLabel)
        .join(' + ');
    return isChinese ? '翻译来源：$localized' : 'Providers: $localized';
  }

  String translationSourceLabel(String provider) => switch (provider) {
    'PickLogic Local' =>
      isChinese ? 'PickLogic 本地术语' : 'PickLogic local terminology',
    'PickLogic Instant · MyMemory' =>
      isChinese ? 'MyMemory 公共翻译' : 'MyMemory public translation',
    'OpenAI-compatible' => isChinese ? '已配置 AI 模型' : 'Configured AI model',
    'MyMemory · Alternative' =>
      isChinese ? 'MyMemory · 候选' : 'MyMemory · Alternative',
    _ => provider,
  };
  String get alternativeTranslations =>
      isChinese ? '其他候选译法' : 'Alternative translations';
  String get useTranslation => isChinese ? '采用' : 'Use';
  String get lockTranslation =>
      isChinese ? '锁定本条，继续查询其他内容' : 'Lock this result and keep looking up text';
  String get unlockTranslation => isChinese ? '取消锁定' : 'Unlock this result';
  String lockedTranslations(int count) =>
      isChinese ? '已锁定译文 · $count' : 'Locked translations · $count';
  String get removeLockedTranslation =>
      isChinese ? '移除锁定译文' : 'Remove locked translation';
  String get comparingTranslationSources => isChinese
      ? '首条译文已显示，正在并行比对其他可用来源…'
      : 'First result is ready; comparing other available sources in parallel…';
  String get bilingualReading => isChinese ? '双语阅读' : 'Bilingual view';
  String get translationTools => isChinese ? '翻译工具' : 'Translation tools';
  String get terminology => isChinese ? '术语表' : 'Terminology';
  String get terminologyNotice => isChinese
      ? '术语仅保存在本机，并在你主动翻译时作为一致性提示发送给已配置的 Provider。'
      : 'Terms stay on this device and are sent as consistency hints only when you explicitly request translation.';
  String get sourceTerm => isChinese ? '原文术语' : 'Source term';
  String get preferredTranslation =>
      isChinese ? '首选译法' : 'Preferred translation';
  String get addTerm => isChinese ? '添加术语' : 'Add term';
  String get noTerminology => isChinese ? '尚未添加术语。' : 'No terminology yet.';
  String get removeTerm => isChinese ? '移除术语' : 'Remove term';
  String get originalText => isChinese ? '原文' : 'Original';
  String get translatedText => isChinese ? '译文' : 'Translation';
  String get retranslate => isChinese ? '重新翻译当前页' : 'Retranslate page';
  String get translateCurrentPage => isChinese ? '翻译当前页' : 'Translate page';
  String get translateDocument => isChinese ? '全文翻译' : 'Translate document';
  String get startTranslation => isChinese ? '开始翻译' : 'Start translation';
  String get stopTranslation => isChinese ? '停止' : 'Stop';
  String translationProgress(int current, int total) =>
      isChinese ? '翻译 $current/$total' : 'Translating $current/$total';
  String translateDocumentDisclosure(int pages) => isChinese
      ? '将按页提取这份 PDF 的文字，并依次发送给你配置的翻译 Provider（共 $pages 页）。不会上传 PDF 文件、图片或未提取内容。可能产生 Provider 费用；可随时停止。是否继续？'
      : 'PickLogic will extract text page by page and send it to your configured translation provider ($pages pages). The PDF file, images, and unextracted content are never uploaded. Provider charges may apply, and you can stop at any time. Continue?';
  String translatedPage(int page) =>
      isChinese ? '译文 · 第 $page 页' : 'Translation · Page $page';
  String get pageNotTranslated => isChinese
      ? '当前页尚未翻译。左侧原文仍保持本地只读。'
      : 'This page has not been translated. The original remains local and read-only.';
  String get translationPrivacy => isChinese
      ? '仅在你主动请求时发送提取文字；不发送 PDF。'
      : 'Only explicitly requested extracted text is sent; the PDF is never sent.';
  String translationPrivacyForEngine(TranslationEngineChoice? choice) =>
      choice == TranslationEngineChoice.instant ||
          choice == TranslationEngineChoice.aggregate
      ? (isChinese
            ? '选择文字后，仅将该段文字发送至 MyMemory；聚合模式还会并行使用本地术语、缓存及已由你配置的 AI。不会发送 PDF、图片、路径或文献记录。'
            : 'Selection sends only that text to MyMemory; aggregate mode also uses local terminology, cache, and any AI provider you already configured. PDFs, images, paths, and library records stay local.')
      : translationPrivacy;
  String get translationMemory => isChinese
      ? '已完成页与术语表保存在本地书库。'
      : 'Completed pages and terminology are saved in the local library.';
  String get noExtractablePageText => isChinese
      ? '当前页没有可提取文字，可能是扫描页。'
      : 'This page has no extractable text and may be scanned.';
  String get pageTranslationFailed =>
      isChinese ? '当前页翻译失败' : 'Page translation failed';
  String documentTranslationComplete(int translated, int total) => isChinese
      ? '全文翻译完成：$translated/$total 页。'
      : 'Document translation complete: $translated/$total pages.';
  String documentTranslationStopped(int translated, int total) => isChinese
      ? '翻译已停止：已完成 $translated/$total 页。'
      : 'Translation stopped after $translated/$total pages.';
  String get documentTranslationFailed =>
      isChinese ? '全文翻译失败' : 'Document translation failed';
  String get saveAnnotation => isChinese ? '保存批注' : 'Save annotation';
  String annotations(int count) =>
      isChinese ? '批注 $count' : 'Annotations $count';
  String get highlight => isChinese ? '高亮' : 'Highlight';
  String get underline => isChinese ? '下划线' : 'Underline';
  String get strikethrough => isChinese ? '删除线' : 'Strikethrough';
  String get note => isChinese ? '笔记' : 'Note';
  String get annotationStyle => isChinese ? '批注样式' : 'Annotation style';
  String annotationKind(LiteratureAnnotationKind kind) => switch (kind) {
    LiteratureAnnotationKind.highlight => highlight,
    LiteratureAnnotationKind.underline => underline,
    LiteratureAnnotationKind.strikethrough => strikethrough,
    LiteratureAnnotationKind.note => note,
  };
  String annotationColor(String color) => switch (color) {
    'green' => isChinese ? '绿色' : 'Green',
    'blue' => isChinese ? '蓝色' : 'Blue',
    'pink' => isChinese ? '粉色' : 'Pink',
    _ => isChinese ? '黄色' : 'Yellow',
  };
  String get annotationNote => isChinese ? '笔记（可选）' : 'Note (optional)';
  String get annotationNoteHint =>
      isChinese ? '记录观点、方法或引用用途' : 'Record an idea, method, or citation use';
  String get annotationSaved =>
      isChinese ? '批注已保存到本地书库。' : 'Annotation saved to the local library.';
  String get annotationSaveFailed =>
      isChinese ? '批注保存失败' : 'Could not save annotation';
  String get annotationDeleted =>
      isChinese ? '批注已从本地书库移除。' : 'Annotation removed from the local library.';
  String get annotationDeleteFailed =>
      isChinese ? '批注删除失败' : 'Could not delete annotation';
  String get deleteAnnotation => isChinese ? '删除批注' : 'Delete annotation';
  String get noAnnotations => isChinese
      ? '选择 PDF 文字后可保存高亮或页码笔记。'
      : 'Select PDF text to save a highlight or page-linked note.';
  String page(int value) => isChinese ? '第 $value 页' : 'Page $value';
  String get cancel => isChinese ? '取消' : 'Cancel';
  String get save => isChinese ? '保存' : 'Save';
  String get selectionCopied =>
      isChinese ? '选中文字已复制。' : 'Selected text copied.';
  String get selectionCopyUnavailable =>
      isChinese ? '此 PDF 不允许复制文字。' : 'This PDF does not allow text copying.';
  String get translationNeedsConfiguration => isChinese
      ? '你选择了高级 AI 模型；该引擎需要端点、模型和密钥。切回“即时翻译”可免配置使用。'
      : 'The advanced AI engine needs an endpoint, model, and key. Choose Instant for no-key translation.';
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
