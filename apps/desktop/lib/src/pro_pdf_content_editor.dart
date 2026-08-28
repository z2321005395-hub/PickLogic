import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

import 'pdf_content_object_service.dart';

typedef PdfContentPageInspector =
    Future<List<PdfContentObjectDescriptor>> Function(
      PdfDocument document,
      int pageNumber,
    );
typedef PdfContentImagePicker = Future<String?> Function();
typedef PdfContentPagePreviewBuilder =
    Widget Function(BuildContext context, int pageNumber);

Future<PdfContentEditPlan?> showPdfContentEditor({
  required BuildContext context,
  required PdfDocument document,
  required int initialPageNumber,
  PdfContentPageInspector? inspector,
  PdfContentImagePicker? imagePicker,
  PdfContentPagePreviewBuilder? pagePreviewBuilder,
}) => showDialog<PdfContentEditPlan>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PdfContentEditorDialog(
    document: document,
    initialPageNumber: initialPageNumber,
    inspector: inspector ?? const PdfContentObjectService().inspectPage,
    imagePicker: imagePicker ?? _pickImage,
    pagePreviewBuilder: pagePreviewBuilder,
  ),
);

Future<String?> _pickImage() async {
  final files = await const PicklogicWindowsBridge().pickFiles(
    title: 'Select an image for the PDF',
  );
  if (files.isEmpty) return null;
  final path = files.first;
  const supported = <String>{'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'};
  final separator = path.lastIndexOf('.');
  if (separator < 0) return null;
  final extension = path.substring(separator).toLowerCase();
  return supported.contains(extension) ? path : null;
}

final class PdfContentEditorDialog extends StatefulWidget {
  const PdfContentEditorDialog({
    super.key,
    required this.document,
    required this.initialPageNumber,
    required this.inspector,
    required this.imagePicker,
    this.pagePreviewBuilder,
  });

  final PdfDocument document;
  final int initialPageNumber;
  final PdfContentPageInspector inspector;
  final PdfContentImagePicker imagePicker;
  final PdfContentPagePreviewBuilder? pagePreviewBuilder;

  @override
  State<PdfContentEditorDialog> createState() => _PdfContentEditorDialogState();
}

final class _PdfContentEditorDialogState extends State<PdfContentEditorDialog> {
  final Map<int, List<PdfContentObjectDescriptor>> _objectsByPage = {};
  Map<String, PdfContentObjectEdit> _edits = {};
  final List<Map<String, PdfContentObjectEdit>> _undo = [];
  final List<Map<String, PdfContentObjectEdit>> _redo = [];
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _leftController = TextEditingController();
  final TextEditingController _bottomController = TextEditingController();
  final TextEditingController _widthController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _rotationController = TextEditingController();
  final TextEditingController _fontSizeController = TextEditingController();
  late int _pageNumber;
  String? _selectedId;
  bool _loading = false;
  Object? _loadError;
  int _loadGeneration = 0;
  int _newObjectId = 1;
  bool _gestureActive = false;

  @override
  void initState() {
    super.initState();
    _pageNumber = widget.initialPageNumber.clamp(
      1,
      widget.document.pages.length,
    );
    unawaited(_loadPage());
  }

  @override
  void dispose() {
    _textController.dispose();
    _leftController.dispose();
    _bottomController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _rotationController.dispose();
    _fontSizeController.dispose();
    super.dispose();
  }

  PdfPage get _page => widget.document.pages[_pageNumber - 1];

  List<PdfContentObjectDescriptor> get _pageObjects =>
      _objectsByPage[_pageNumber] ?? const [];

  PdfContentEditPlan get _plan => PdfContentEditPlan(
    edits: _edits.values.where((edit) => edit.changed).toList(growable: false),
  );

  PdfContentObjectDescriptor? _descriptorFor(String id) {
    for (final descriptor in _pageObjects) {
      if (descriptor.id == id) return descriptor;
    }
    return null;
  }

  PdfContentObjectEdit? get _selectedEdit {
    final id = _selectedId;
    if (id == null) return null;
    final existing = _edits[id];
    if (existing != null) return existing;
    final descriptor = _descriptorFor(id);
    return descriptor == null
        ? null
        : PdfContentObjectEdit.fromDescriptor(descriptor);
  }

  Future<void> _loadPage() async {
    final generation = ++_loadGeneration;
    if (_objectsByPage.containsKey(_pageNumber)) {
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final objects = await widget.inspector(widget.document, _pageNumber);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _objectsByPage[_pageNumber] = objects;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  void _goToPage(int pageNumber) {
    final bounded = pageNumber.clamp(1, widget.document.pages.length);
    if (bounded == _pageNumber) return;
    setState(() {
      _pageNumber = bounded;
      _selectedId = null;
    });
    unawaited(_loadPage());
  }

  Map<String, PdfContentObjectEdit> _snapshot() => Map.of(_edits);

  void _recordHistory() {
    _undo.add(_snapshot());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _commit(PdfContentObjectEdit edit) {
    setState(() {
      _recordHistory();
      _edits[edit.id] = edit;
      _selectedId = edit.id;
      _syncInspector(edit);
    });
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_snapshot());
      _edits = _undo.removeLast();
      _repairSelection();
    });
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_snapshot());
      _edits = _redo.removeLast();
      _repairSelection();
    });
  }

  void _repairSelection() {
    final selected = _selectedEdit;
    if (selected == null || selected.deleted) {
      _selectedId = null;
      return;
    }
    _syncInspector(selected);
  }

  void _select(PdfContentObjectEdit edit) {
    setState(() {
      _selectedId = edit.id;
      _syncInspector(edit);
    });
  }

  void _syncInspector(PdfContentObjectEdit edit) {
    final descriptor = _descriptorFor(edit.id);
    _textController.text =
        edit.replacementText ?? descriptor?.text ?? edit.replacementText ?? '';
    _leftController.text = edit.targetBounds.left.toStringAsFixed(1);
    _bottomController.text = edit.targetBounds.bottom.toStringAsFixed(1);
    _widthController.text = edit.targetBounds.width.toStringAsFixed(1);
    _heightController.text = edit.targetBounds.height.toStringAsFixed(1);
    _rotationController.text = edit.rotationDegrees.toStringAsFixed(0);
    _fontSizeController.text = edit.fontSize.toStringAsFixed(1);
  }

  void _applyInspector() {
    final edit = _selectedEdit;
    if (edit == null) return;
    final left = double.tryParse(_leftController.text);
    final bottom = double.tryParse(_bottomController.text);
    final width = double.tryParse(_widthController.text);
    final height = double.tryParse(_heightController.text);
    final rotation = double.tryParse(_rotationController.text);
    final fontSize = double.tryParse(_fontSizeController.text);
    if (left == null ||
        bottom == null ||
        width == null ||
        height == null ||
        width < 4 ||
        height < 4 ||
        rotation == null ||
        fontSize == null ||
        fontSize <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_ContentEditorStrings.of(context).invalidSize)),
      );
      return;
    }
    final descriptor = _descriptorFor(edit.id);
    final target = PdfContentBounds(
      left: left,
      bottom: bottom,
      right: left + width,
      top: bottom + height,
    ).clampToPage(pageWidth: _page.width, pageHeight: _page.height);
    final text = _textController.text;
    _commit(
      edit.copyWith(
        targetBounds: target,
        replacementText:
            edit.kind == PdfContentObjectKind.text &&
                (edit.isNew || text != descriptor?.text)
            ? text
            : null,
        clearReplacementText:
            edit.kind == PdfContentObjectKind.text &&
            !edit.isNew &&
            text == descriptor?.text,
        fontSize: fontSize,
        rotationDegrees: rotation % 360,
      ),
    );
  }

  Future<void> _addText() async {
    final strings = _ContentEditorStrings.of(context);
    final controller = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const Key('pdf-add-text-dialog'),
          title: Text(strings.addText),
          content: TextField(
            key: const Key('pdf-add-text-field'),
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: strings.enterText,
              helperText: strings.newTextFontNotice,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const Key('pdf-confirm-add-text'),
              onPressed: () {
                final value = controller.text;
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              child: Text(strings.add),
            ),
          ],
        ),
      );
      if (text == null || !mounted) return;
      final bounds = PdfContentBounds(
        left: 72,
        bottom: math.max(24, _page.height - 120),
        right: math.min(_page.width - 24, 332),
        top: math.max(52, _page.height - 88),
      ).clampToPage(pageWidth: _page.width, pageHeight: _page.height);
      _commit(
        PdfContentObjectEdit.addText(
          id: 'new:${_pageNumber}:${_newObjectId++}',
          pageNumber: _pageNumber,
          bounds: bounds,
          text: text,
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _addImage() async {
    final path = await widget.imagePicker();
    if (path == null || !mounted) {
      if (path == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_ContentEditorStrings.of(context).imageNotSelected),
          ),
        );
      }
      return;
    }
    final bounds = PdfContentBounds(
      left: 72,
      bottom: math.max(24, _page.height - 240),
      right: math.min(_page.width - 24, 272),
      top: math.max(124, _page.height - 80),
    ).clampToPage(pageWidth: _page.width, pageHeight: _page.height);
    _commit(
      PdfContentObjectEdit.addImage(
        id: 'new:${_pageNumber}:${_newObjectId++}',
        pageNumber: _pageNumber,
        bounds: bounds,
        imagePath: path,
      ),
    );
  }

  Future<void> _replaceImage() async {
    final edit = _selectedEdit;
    if (edit == null || edit.kind != PdfContentObjectKind.image) return;
    final path = await widget.imagePicker();
    if (path == null || !mounted) return;
    _commit(edit.copyWith(replacementImagePath: path));
  }

  void _deleteSelected() {
    final edit = _selectedEdit;
    if (edit == null) return;
    setState(() {
      _recordHistory();
      if (edit.isNew) {
        _edits.remove(edit.id);
        _selectedId = null;
      } else {
        _edits[edit.id] = edit.copyWith(deleted: true);
      }
    });
  }

  void _restore(PdfContentObjectEdit edit) =>
      _commit(edit.copyWith(deleted: false));

  void _beginGesture(PdfContentObjectEdit edit) {
    if (_gestureActive) return;
    setState(() {
      _gestureActive = true;
      _recordHistory();
      _edits[edit.id] = edit;
      _selectedId = edit.id;
    });
  }

  void _moveObject(
    PdfContentObjectEdit edit,
    DragUpdateDetails details,
    double scale,
  ) {
    final moved = edit.targetBounds
        .translate(details.delta.dx / scale, -details.delta.dy / scale)
        .clampToPage(pageWidth: _page.width, pageHeight: _page.height);
    setState(() {
      _edits[edit.id] = edit.copyWith(targetBounds: moved);
      _syncInspector(_edits[edit.id]!);
    });
  }

  void _resizeObject(
    PdfContentObjectEdit edit,
    DragUpdateDetails details,
    double scale,
  ) {
    final width = math.max(
      4.0,
      edit.targetBounds.width + details.delta.dx / scale,
    );
    final height = math.max(
      4.0,
      edit.targetBounds.height + details.delta.dy / scale,
    );
    final resized = edit.targetBounds
        .resize(width: width, height: height)
        .clampToPage(pageWidth: _page.width, pageHeight: _page.height);
    setState(() {
      _edits[edit.id] = edit.copyWith(targetBounds: resized);
      _syncInspector(_edits[edit.id]!);
    });
  }

  void _endGesture(DragEndDetails _) => _gestureActive = false;

  @override
  Widget build(BuildContext context) {
    final strings = _ContentEditorStrings.of(context);
    final mediaSize = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('pdf-content-editor-dialog'),
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(1500, mediaSize.width - 32),
        height: math.min(920, mediaSize.height - 32),
        child: Column(
          children: [
            _buildHeader(strings),
            const Divider(height: 1),
            _buildToolbar(strings),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildCanvas(strings)),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 320, child: _buildInspector(strings)),
                ],
              ),
            ),
            const Divider(height: 1),
            _buildFooter(strings),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_ContentEditorStrings strings) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    child: Row(
      children: [
        const Icon(Icons.edit_note_outlined),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                strings.sourcePreserved,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          key: const Key('pdf-content-undo-action'),
          tooltip: strings.undo,
          onPressed: _undo.isEmpty ? null : _undoChange,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          key: const Key('pdf-content-redo-action'),
          tooltip: strings.redo,
          onPressed: _redo.isEmpty ? null : _redoChange,
          icon: const Icon(Icons.redo),
        ),
        IconButton(
          tooltip: strings.close,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _buildToolbar(_ContentEditorStrings strings) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        IconButton(
          key: const Key('pdf-content-previous-page'),
          tooltip: strings.previousPage,
          onPressed: _pageNumber > 1 ? () => _goToPage(_pageNumber - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text(strings.pagePosition(_pageNumber, widget.document.pages.length)),
        IconButton(
          key: const Key('pdf-content-next-page'),
          tooltip: strings.nextPage,
          onPressed: _pageNumber < widget.document.pages.length
              ? () => _goToPage(_pageNumber + 1)
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          key: const Key('pdf-content-add-text-action'),
          onPressed: _loading ? null : _addText,
          icon: const Icon(Icons.title),
          label: Text(strings.addText),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          key: const Key('pdf-content-add-image-action'),
          onPressed: _loading ? null : _addImage,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(strings.addImage),
        ),
        const Spacer(),
        Chip(
          avatar: const Icon(Icons.layers_outlined, size: 18),
          label: Text(strings.objectCount(_pageObjects.length)),
        ),
      ],
    ),
  );

  Widget _buildCanvas(_ContentEditorStrings strings) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 8),
            Text(strings.objectReadFailed),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _loadPage, child: Text(strings.retry)),
          ],
        ),
      );
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = math.min(
            (constraints.maxWidth - 48) / _page.width,
            (constraints.maxHeight - 48) / _page.height,
          );
          final safeScale = math.max(0.05, scale);
          return Center(
            child: SizedBox(
              key: const Key('pdf-content-page-canvas'),
              width: _page.width * safeScale,
              height: _page.height * safeScale,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child:
                        widget.pagePreviewBuilder?.call(context, _pageNumber) ??
                        PdfPageView(
                          document: widget.document,
                          pageNumber: _pageNumber,
                          maximumDpi: 144,
                          decoration: const BoxDecoration(color: Colors.white),
                        ),
                  ),
                  for (final edit in _canvasObjects)
                    _buildObjectOverlay(edit, safeScale, strings),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<PdfContentObjectEdit> get _canvasObjects {
    final objects = <PdfContentObjectEdit>[
      for (final descriptor in _pageObjects)
        _edits[descriptor.id] ??
            PdfContentObjectEdit.fromDescriptor(descriptor),
      ..._edits.values.where(
        (edit) => edit.pageNumber == _pageNumber && edit.isNew,
      ),
    ];
    return objects.where((edit) => !edit.deleted).toList(growable: false);
  }

  Widget _buildObjectOverlay(
    PdfContentObjectEdit edit,
    double scale,
    _ContentEditorStrings strings,
  ) {
    final bounds = edit.targetBounds;
    final selected = edit.id == _selectedId;
    final color = edit.kind == PdfContentObjectKind.text
        ? Colors.blue
        : Colors.deepPurple;
    final descriptor = _descriptorFor(edit.id);
    final visualChanged =
        edit.isNew ||
        edit.replacementText != null ||
        edit.replacementImagePath != null ||
        edit.targetBounds != edit.sourceBounds ||
        edit.rotationDegrees != 0;
    return Positioned(
      key: ValueKey('pdf-content-object-${edit.id}'),
      left: bounds.left * scale,
      top: (_page.height - bounds.top) * scale,
      width: math.max(8, bounds.width * scale),
      height: math.max(8, bounds.height * scale),
      child: Transform.rotate(
        angle: edit.rotationDegrees * math.pi / 180,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _select(edit),
          onPanStart: (_) => _beginGesture(edit),
          onPanUpdate: (details) =>
              _moveObject(_edits[edit.id] ?? edit, details, scale),
          onPanEnd: _endGesture,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: visualChanged
                  ? Colors.white.withValues(alpha: 0.92)
                  : color.withValues(alpha: selected ? 0.08 : 0.02),
              border: Border.all(
                color: color.withValues(alpha: selected ? 1 : 0.40),
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _buildObjectPreview(edit, descriptor, strings),
                ),
                if (selected)
                  Positioned(
                    right: -7,
                    bottom: -7,
                    child: GestureDetector(
                      key: const Key('pdf-content-resize-handle'),
                      onPanStart: (_) => _beginGesture(edit),
                      onPanUpdate: (details) => _resizeObject(
                        _edits[edit.id] ?? edit,
                        details,
                        scale,
                      ),
                      onPanEnd: _endGesture,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(color: Colors.white, width: 2),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildObjectPreview(
    PdfContentObjectEdit edit,
    PdfContentObjectDescriptor? descriptor,
    _ContentEditorStrings strings,
  ) {
    if (edit.kind == PdfContentObjectKind.text) {
      final text = edit.replacementText ?? descriptor?.text ?? '';
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Text(
          text,
          maxLines: 4,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: edit.replacementText != null || edit.isNew
                ? Colors.black87
                : Colors.transparent,
            fontSize: math.max(7, math.min(22, edit.fontSize)),
          ),
        ),
      );
    }
    final path = edit.replacementImagePath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.fill,
        errorBuilder: (_, _, _) {
          return const Center(child: Icon(Icons.broken_image_outlined));
        },
      );
    }
    return Center(
      child: Tooltip(
        message: strings.imageObject,
        child: Icon(
          Icons.image_outlined,
          color: edit.targetBounds != edit.sourceBounds
              ? Colors.deepPurple
              : Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildInspector(_ContentEditorStrings strings) {
    final selected = _selectedEdit;
    final listed = <PdfContentObjectEdit>[
      for (final descriptor in _pageObjects)
        _edits[descriptor.id] ??
            PdfContentObjectEdit.fromDescriptor(descriptor),
      ..._edits.values.where(
        (edit) => edit.pageNumber == _pageNumber && edit.isNew,
      ),
    ];
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.objects,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: listed.isEmpty
                  ? Center(child: Text(strings.noEditableObjects))
                  : ListView.builder(
                      key: const Key('pdf-content-object-list'),
                      itemCount: listed.length,
                      itemBuilder: (context, index) {
                        final edit = listed[index];
                        final descriptor = _descriptorFor(edit.id);
                        final label = edit.kind == PdfContentObjectKind.text
                            ? (edit.replacementText ?? descriptor?.text ?? '')
                            : (edit.replacementImagePath == null
                                  ? strings.imageObject
                                  : _fileName(edit.replacementImagePath!));
                        return ListTile(
                          dense: true,
                          selected: edit.id == _selectedId,
                          leading: Icon(
                            edit.kind == PdfContentObjectKind.text
                                ? Icons.title
                                : Icons.image_outlined,
                          ),
                          title: Text(
                            label.isEmpty ? strings.emptyTextObject : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: edit.deleted
                              ? IconButton(
                                  key: Key('pdf-content-restore-$index'),
                                  tooltip: strings.restore,
                                  onPressed: () => _restore(edit),
                                  icon: const Icon(Icons.restore),
                                )
                              : null,
                          onTap: edit.deleted ? null : () => _select(edit),
                        );
                      },
                    ),
            ),
            const Divider(),
            if (selected == null)
              Expanded(
                child: Center(
                  child: Text(
                    strings.selectObject,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      selected.kind == PdfContentObjectKind.text
                          ? strings.textObject
                          : strings.imageObject,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (selected.kind == PdfContentObjectKind.text) ...[
                      TextField(
                        key: const Key('pdf-content-text-field'),
                        controller: _textController,
                        maxLines: 4,
                        decoration: InputDecoration(labelText: strings.text),
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      OutlinedButton.icon(
                        key: const Key('pdf-content-replace-image-action'),
                        onPressed: _replaceImage,
                        icon: const Icon(Icons.find_replace_outlined),
                        label: Text(strings.replaceImage),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: _NumericField(
                            key: const Key('pdf-content-left-field'),
                            controller: _leftController,
                            label: 'X',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _NumericField(
                            key: const Key('pdf-content-bottom-field'),
                            controller: _bottomController,
                            label: 'Y',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _NumericField(
                            key: const Key('pdf-content-width-field'),
                            controller: _widthController,
                            label: strings.width,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _NumericField(
                            key: const Key('pdf-content-height-field'),
                            controller: _heightController,
                            label: strings.height,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _NumericField(
                            key: const Key('pdf-content-rotation-field'),
                            controller: _rotationController,
                            label: strings.rotation,
                          ),
                        ),
                        if (selected.kind == PdfContentObjectKind.text) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _NumericField(
                              key: const Key('pdf-content-font-size-field'),
                              controller: _fontSizeController,
                              label: strings.fontSize,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const Key('pdf-content-apply-object-action'),
                      onPressed: _applyInspector,
                      icon: const Icon(Icons.check),
                      label: Text(strings.apply),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('pdf-content-delete-object-action'),
                      onPressed: _deleteSelected,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(strings.removeObject),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(_ContentEditorStrings strings) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            strings.limitations,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const Key('pdf-content-save-copy-action'),
          onPressed: _plan.changed ? () => Navigator.pop(context, _plan) : null,
          icon: const Icon(Icons.save_as_outlined),
          label: Text(strings.saveCopy),
        ),
      ],
    ),
  );

  String _fileName(String path) =>
      path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;
}

final class _NumericField extends StatelessWidget {
  const _NumericField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, isDense: true),
  );
}

final class _ContentEditorStrings {
  const _ContentEditorStrings(this.chinese);

  factory _ContentEditorStrings.of(BuildContext context) =>
      _ContentEditorStrings(
        PickLogicLocalizations.of(context).locale.languageCode == 'zh',
      );

  final bool chinese;

  String get title => chinese ? '编辑文字和图片' : 'Edit text and images';
  String get sourcePreserved => chinese
      ? '直接编辑页面对象；最终只另存新 PDF，原文件不会改写。'
      : 'Edit page objects directly, then save a new PDF without rewriting the source.';
  String get undo => chinese ? '撤销' : 'Undo';
  String get redo => chinese ? '重做' : 'Redo';
  String get close => chinese ? '关闭' : 'Close';
  String get previousPage => chinese ? '上一页' : 'Previous page';
  String get nextPage => chinese ? '下一页' : 'Next page';
  String pagePosition(int current, int total) =>
      chinese ? '第 $current / $total 页' : 'Page $current of $total';
  String get addText => chinese ? '添加文字' : 'Add text';
  String get addImage => chinese ? '添加图片' : 'Add image';
  String get enterText => chinese ? '输入要加入 PDF 的文字' : 'Enter PDF text';
  String get newTextFontNotice => chinese
      ? '新文字使用 PDF 标准字体；复杂中文字体嵌入仍会明确提示。'
      : 'New text uses a standard PDF font; complex CJK font embedding is reported explicitly.';
  String get add => chinese ? '添加' : 'Add';
  String get cancel => chinese ? '取消' : 'Cancel';
  String get retry => chinese ? '重试' : 'Retry';
  String get objectReadFailed => chinese
      ? '无法读取此页的可编辑对象。'
      : 'Could not read editable objects on this page.';
  String objectCount(int count) =>
      chinese ? '$count 个可编辑对象' : '$count editable objects';
  String get objects => chinese ? '页面对象' : 'Page objects';
  String get noEditableObjects => chinese
      ? '此页没有可直接编辑的顶层文字或图片。'
      : 'No directly editable top-level text or image objects.';
  String get selectObject => chinese
      ? '点击页面中的文字或图片，或从上方列表选择。'
      : 'Select text or an image on the page or from the list.';
  String get textObject => chinese ? '文字对象' : 'Text object';
  String get imageObject => chinese ? '图片对象' : 'Image object';
  String get emptyTextObject => chinese ? '空文字对象' : 'Empty text object';
  String get text => chinese ? '文字' : 'Text';
  String get replaceImage => chinese ? '替换图片' : 'Replace image';
  String get width => chinese ? '宽度' : 'Width';
  String get height => chinese ? '高度' : 'Height';
  String get rotation => chinese ? '旋转角度' : 'Rotation';
  String get fontSize => chinese ? '字号' : 'Font size';
  String get apply => chinese ? '应用修改' : 'Apply changes';
  String get removeObject => chinese ? '从副本中删除对象' : 'Remove from copy';
  String get restore => chinese ? '恢复对象' : 'Restore object';
  String get invalidSize => chinese
      ? '请输入有效的位置、尺寸、字号和旋转角度。'
      : 'Enter valid position, size, font size, and rotation values.';
  String get imageNotSelected => chinese
      ? '未选择受支持的 PNG、JPEG、BMP、GIF 或 WebP 图片。'
      : 'No supported PNG, JPEG, BMP, GIF, or WebP image was selected.';
  String get limitations => chinese
      ? '支持顶层文字与图片对象；扫描页、轮廓字、复杂表格和嵌套对象需要后续 OCR/高级编辑。'
      : 'Top-level text and image objects are supported. Scans, outlined text, complex tables, and nested objects need later OCR/advanced editing.';
  String get saveCopy => chinese ? '另存编辑副本' : 'Save edited copy';
}
