import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

typedef PdfPageSaveRequested = Future<bool> Function(PdfEditPlan plan);

Future<PdfEditPlan?> showPdfPageEditor({
  required BuildContext context,
  required int pageCount,
  required int annotationCount,
  PdfPageSaveRequested? onSaveRequested,
}) => showDialog<PdfEditPlan>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PdfPageEditorDialog(
    pageCount: pageCount,
    annotationCount: annotationCount,
    onSaveRequested: onSaveRequested,
  ),
);

final class PdfPageEditorDialog extends StatefulWidget {
  const PdfPageEditorDialog({
    super.key,
    required this.pageCount,
    required this.annotationCount,
    this.onSaveRequested,
  });

  final int pageCount;
  final int annotationCount;
  final PdfPageSaveRequested? onSaveRequested;

  @override
  State<PdfPageEditorDialog> createState() => _PdfPageEditorDialogState();
}

final class _PdfPageEditorDialogState extends State<PdfPageEditorDialog> {
  late List<_EditablePage> _pages;
  late List<_EditablePage> _savedPages;
  final List<List<_EditablePage>> _undo = [];
  final List<List<_EditablePage>> _redo = [];
  var _nextId = 1;
  var _allowPop = false;
  var _exitPromptVisible = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _pages = [
      for (var page = 1; page <= widget.pageCount; page++)
        _EditablePage(id: _nextId++, sourcePageNumber: page),
    ];
    _savedPages = List<_EditablePage>.of(_pages);
  }

  PdfEditPlan get _plan => PdfEditPlan(
    originalPageCount: widget.pageCount,
    pages: [for (final page in _pages) page.toEdit()],
  );

  bool get _hasUnsavedChanges {
    if (_pages.length != _savedPages.length) return true;
    for (var index = 0; index < _pages.length; index++) {
      final current = _pages[index];
      final saved = _savedPages[index];
      if (current.id != saved.id ||
          current.sourcePageNumber != saved.sourcePageNumber ||
          current.clockwiseQuarterTurns != saved.clockwiseQuarterTurns) {
        return true;
      }
    }
    return false;
  }

  void _change(void Function(List<_EditablePage> pages) update) {
    setState(() {
      _undo.add(List<_EditablePage>.of(_pages));
      _redo.clear();
      final next = List<_EditablePage>.of(_pages);
      update(next);
      _pages = next;
    });
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(List<_EditablePage>.of(_pages));
      _pages = _undo.removeLast();
    });
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(List<_EditablePage>.of(_pages));
      _pages = _redo.removeLast();
    });
  }

  void _closeEditor([PdfEditPlan? result]) {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<bool> _saveCurrent({required bool closeAfterSave}) async {
    if (_saving || !_hasUnsavedChanges) return false;
    final plan = _plan;
    final save = widget.onSaveRequested;
    if (save == null) {
      _closeEditor(plan);
      return true;
    }
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await save(plan);
      if (!mounted) return saved;
      if (saved) {
        setState(() => _savedPages = List<_EditablePage>.of(_pages));
        if (closeAfterSave) _closeEditor(plan);
      }
      return saved;
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  Future<void> _requestClose() async {
    if (_saving || _exitPromptVisible) return;
    if (!_hasUnsavedChanges) {
      _closeEditor();
      return;
    }
    _exitPromptVisible = true;
    final strings = _PdfEditorStrings.of(context);
    final decision = await showDialog<_UnsavedPageEditDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const Key('pdf-edit-unsaved-dialog'),
        title: Text(strings.unsavedTitle),
        content: Text(strings.unsavedMessage),
        actions: [
          TextButton(
            key: const Key('pdf-edit-continue-editing-action'),
            onPressed: () =>
                Navigator.pop(dialogContext, _UnsavedPageEditDecision.cancel),
            child: Text(strings.cancel),
          ),
          TextButton(
            key: const Key('pdf-edit-discard-action'),
            onPressed: () =>
                Navigator.pop(dialogContext, _UnsavedPageEditDecision.dontSave),
            child: Text(strings.dontSave),
          ),
          FilledButton.icon(
            key: const Key('pdf-edit-confirm-save-copy-action'),
            onPressed: () =>
                Navigator.pop(dialogContext, _UnsavedPageEditDecision.saveCopy),
            icon: const Icon(Icons.save_as_outlined),
            label: Text(strings.saveCopy),
          ),
        ],
      ),
    );
    _exitPromptVisible = false;
    if (!mounted || decision == null) return;
    switch (decision) {
      case _UnsavedPageEditDecision.cancel:
        return;
      case _UnsavedPageEditDecision.dontSave:
        _closeEditor();
        return;
      case _UnsavedPageEditDecision.saveCopy:
        await _saveCurrent(closeAfterSave: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _PdfEditorStrings.of(context);
    final plan = _plan;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_hasUnsavedChanges && !_saving) {
            unawaited(_saveCurrent(closeAfterSave: false));
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (_undo.isNotEmpty && !_saving) _undoChange();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (_redo.isNotEmpty && !_saving) _redoChange();
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope<PdfEditPlan>(
          canPop: _allowPop || !_hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_requestClose());
          },
          child: AlertDialog(
            key: const Key('pdf-page-editor-dialog'),
            title: Row(
              children: [
                const Icon(Icons.edit_document),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _hasUnsavedChanges ? '${strings.title} *' : strings.title,
                  ),
                ),
                Tooltip(
                  message: strings.saveShortcut,
                  child: FilledButton.tonalIcon(
                    key: const Key('pdf-edit-save-copy-action'),
                    onPressed: _hasUnsavedChanges && !_saving
                        ? () => unawaited(_saveCurrent(closeAfterSave: false))
                        : null,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? strings.saving : strings.saveCopy),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('pdf-edit-undo-action'),
                  tooltip: strings.undoShortcut,
                  onPressed: _undo.isEmpty || _saving ? null : _undoChange,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  key: const Key('pdf-edit-redo-action'),
                  tooltip: strings.redoShortcut,
                  onPressed: _redo.isEmpty || _saving ? null : _redoChange,
                  icon: const Icon(Icons.redo),
                ),
                IconButton(
                  key: const Key('pdf-edit-close-action'),
                  tooltip: strings.close,
                  onPressed: _saving ? null : _requestClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            content: SizedBox(
              width: 760,
              height: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.copy_all_outlined),
                          const SizedBox(width: 10),
                          Expanded(child: Text(strings.sourcePreserved)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(strings.pages(plan.pages.length))),
                      Chip(label: Text(strings.rotated(plan.rotatedPageCount))),
                      Chip(label: Text(strings.removed(plan.removedPageCount))),
                      Chip(
                        label: Text(
                          strings.duplicated(plan.duplicatedPageCount),
                        ),
                      ),
                      if (widget.annotationCount > 0)
                        Chip(
                          avatar: const Icon(
                            Icons.highlight_outlined,
                            size: 18,
                          ),
                          label: Text(
                            strings.annotations(widget.annotationCount),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ReorderableListView.builder(
                      key: const Key('pdf-edit-page-list'),
                      buildDefaultDragHandles: false,
                      itemCount: _pages.length,
                      onReorderItem: (oldIndex, newIndex) {
                        if (newIndex == oldIndex) return;
                        _change((pages) {
                          final item = pages.removeAt(oldIndex);
                          pages.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final page = _pages[index];
                        return Card(
                          key: ValueKey('pdf-edit-page-${page.id}'),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.drag_indicator),
                              ),
                            ),
                            title: Text(strings.outputPage(index + 1)),
                            subtitle: Text(
                              strings.sourcePage(
                                page.sourcePageNumber,
                                page.clockwiseQuarterTurns,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: Key('pdf-edit-rotate-left-$index'),
                                  tooltip: strings.rotateLeft,
                                  onPressed: () => _change(
                                    (pages) =>
                                        pages[index] = pages[index].rotate(-1),
                                  ),
                                  icon: const Icon(Icons.rotate_left),
                                ),
                                IconButton(
                                  key: Key('pdf-edit-rotate-right-$index'),
                                  tooltip: strings.rotateRight,
                                  onPressed: () => _change(
                                    (pages) =>
                                        pages[index] = pages[index].rotate(1),
                                  ),
                                  icon: const Icon(Icons.rotate_right),
                                ),
                                IconButton(
                                  key: Key('pdf-edit-duplicate-$index'),
                                  tooltip: strings.duplicate,
                                  onPressed: () => _change(
                                    (pages) => pages.insert(
                                      index + 1,
                                      page.copyWith(id: _nextId++),
                                    ),
                                  ),
                                  icon: const Icon(Icons.content_copy_outlined),
                                ),
                                IconButton(
                                  key: Key('pdf-edit-remove-$index'),
                                  tooltip: strings.remove,
                                  onPressed: _pages.length == 1
                                      ? null
                                      : () => _change(
                                          (pages) => pages.removeAt(index),
                                        ),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _saving ? null : _requestClose,
                child: Text(strings.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _EditablePage {
  const _EditablePage({
    required this.id,
    required this.sourcePageNumber,
    this.clockwiseQuarterTurns = 0,
  });

  final int id;
  final int sourcePageNumber;
  final int clockwiseQuarterTurns;

  _EditablePage rotate(int delta) => _EditablePage(
    id: id,
    sourcePageNumber: sourcePageNumber,
    clockwiseQuarterTurns: (clockwiseQuarterTurns + delta) % 4,
  );

  _EditablePage copyWith({required int id}) => _EditablePage(
    id: id,
    sourcePageNumber: sourcePageNumber,
    clockwiseQuarterTurns: clockwiseQuarterTurns,
  );

  PdfPageEdit toEdit() => PdfPageEdit(
    sourcePageNumber: sourcePageNumber,
    clockwiseQuarterTurns: clockwiseQuarterTurns,
  );
}

final class _PdfEditorStrings {
  const _PdfEditorStrings(this.chinese);

  factory _PdfEditorStrings.of(BuildContext context) => _PdfEditorStrings(
    PickLogicLocalizations.of(context).locale.languageCode == 'zh',
  );

  final bool chinese;

  String get title => chinese ? '编辑 PDF 页面' : 'Edit PDF pages';
  String get sourcePreserved => chinese
      ? '直接调整页面；关闭时再决定另存副本或放弃，原 PDF 保持不变。'
      : 'Edit pages directly. Choose save copy or discard when closing; the source PDF stays unchanged.';
  String get undo => chinese ? '撤销' : 'Undo';
  String get redo => chinese ? '重做' : 'Redo';
  String get undoShortcut => chinese ? '撤销 (Ctrl+Z)' : 'Undo (Ctrl+Z)';
  String get redoShortcut => chinese ? '重做 (Ctrl+Y)' : 'Redo (Ctrl+Y)';
  String get rotateLeft => chinese ? '向左旋转' : 'Rotate left';
  String get rotateRight => chinese ? '向右旋转' : 'Rotate right';
  String get duplicate => chinese ? '复制此页' : 'Duplicate page';
  String get remove => chinese ? '从副本中移除此页' : 'Remove from copy';
  String get cancel => chinese ? '取消' : 'Cancel';
  String get close => chinese ? '关闭' : 'Close';
  String get saveCopy => chinese ? '另存编辑副本' : 'Save edited copy';
  String get saveShortcut =>
      chinese ? '保存编辑副本 (Ctrl+S)' : 'Save edited copy (Ctrl+S)';
  String get saving => chinese ? '正在保存…' : 'Saving…';
  String get unsavedTitle =>
      chinese ? '要保存对 PDF 的更改吗？' : 'Do you want to save changes to the PDF?';
  String get unsavedMessage => chinese
      ? '如果不保存，所做的页面更改将丢失。保存时会创建新 PDF，原文件不会被覆盖。'
      : 'If you do not save, your page changes will be lost. Saving creates a new PDF and never overwrites the source.';
  String get dontSave => chinese ? '不保存' : "Don't save";
  String pages(int count) => chinese ? '$count 页' : '$count pages';
  String rotated(int count) => chinese ? '旋转 $count 页' : '$count rotated';
  String removed(int count) => chinese ? '移除 $count 页' : '$count removed';
  String duplicated(int count) => chinese ? '复制 $count 页' : '$count duplicated';
  String annotations(int count) =>
      chinese ? '写入 $count 条批注' : 'Embed $count annotations';
  String outputPage(int number) =>
      chinese ? '输出第 $number 页' : 'Output page $number';
  String sourcePage(int source, int turns) {
    final degrees = turns * 90;
    if (chinese) {
      return degrees == 0 ? '来自原第 $source 页' : '来自原第 $source 页 · 顺时针 $degrees°';
    }
    return degrees == 0
        ? 'From source page $source'
        : 'From source page $source · $degrees° clockwise';
  }
}

enum _UnsavedPageEditDecision { saveCopy, dontSave, cancel }
