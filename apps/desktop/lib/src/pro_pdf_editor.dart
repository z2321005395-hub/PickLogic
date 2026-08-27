import 'package:flutter/material.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

Future<PdfEditPlan?> showPdfPageEditor({
  required BuildContext context,
  required int pageCount,
  required int annotationCount,
}) => showDialog<PdfEditPlan>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PdfPageEditorDialog(
    pageCount: pageCount,
    annotationCount: annotationCount,
  ),
);

final class PdfPageEditorDialog extends StatefulWidget {
  const PdfPageEditorDialog({
    super.key,
    required this.pageCount,
    required this.annotationCount,
  });

  final int pageCount;
  final int annotationCount;

  @override
  State<PdfPageEditorDialog> createState() => _PdfPageEditorDialogState();
}

final class _PdfPageEditorDialogState extends State<PdfPageEditorDialog> {
  late List<_EditablePage> _pages;
  final List<List<_EditablePage>> _undo = [];
  final List<List<_EditablePage>> _redo = [];
  var _nextId = 1;

  @override
  void initState() {
    super.initState();
    _pages = [
      for (var page = 1; page <= widget.pageCount; page++)
        _EditablePage(id: _nextId++, sourcePageNumber: page),
    ];
  }

  PdfEditPlan get _plan => PdfEditPlan(
    originalPageCount: widget.pageCount,
    pages: [for (final page in _pages) page.toEdit()],
  );

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

  @override
  Widget build(BuildContext context) {
    final strings = _PdfEditorStrings.of(context);
    final plan = _plan;
    return AlertDialog(
      key: const Key('pdf-page-editor-dialog'),
      title: Row(
        children: [
          const Icon(Icons.edit_document),
          const SizedBox(width: 10),
          Expanded(child: Text(strings.title)),
          IconButton(
            key: const Key('pdf-edit-undo-action'),
            tooltip: strings.undo,
            onPressed: _undo.isEmpty ? null : _undoChange,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const Key('pdf-edit-redo-action'),
            tooltip: strings.redo,
            onPressed: _redo.isEmpty ? null : _redoChange,
            icon: const Icon(Icons.redo),
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
                Chip(label: Text(strings.duplicated(plan.duplicatedPageCount))),
                if (widget.annotationCount > 0)
                  Chip(
                    avatar: const Icon(Icons.highlight_outlined, size: 18),
                    label: Text(strings.annotations(widget.annotationCount)),
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
                              (pages) => pages[index] = pages[index].rotate(-1),
                            ),
                            icon: const Icon(Icons.rotate_left),
                          ),
                          IconButton(
                            key: Key('pdf-edit-rotate-right-$index'),
                            tooltip: strings.rotateRight,
                            onPressed: () => _change(
                              (pages) => pages[index] = pages[index].rotate(1),
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
                                : () =>
                                      _change((pages) => pages.removeAt(index)),
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
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton.icon(
          key: const Key('pdf-edit-save-copy-action'),
          onPressed: plan.changed || widget.annotationCount > 0
              ? () => Navigator.pop(context, plan)
              : null,
          icon: const Icon(Icons.save_as_outlined),
          label: Text(strings.saveCopy),
        ),
      ],
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

  String get title => chinese ? '编辑 PDF 副本' : 'Edit PDF copy';
  String get sourcePreserved => chinese
      ? '原 PDF 保持不变。确认后使用 Windows“另存为”创建新文件。'
      : 'The source PDF stays unchanged. Windows Save As creates a new file after confirmation.';
  String get undo => chinese ? '撤销' : 'Undo';
  String get redo => chinese ? '重做' : 'Redo';
  String get rotateLeft => chinese ? '向左旋转' : 'Rotate left';
  String get rotateRight => chinese ? '向右旋转' : 'Rotate right';
  String get duplicate => chinese ? '复制此页' : 'Duplicate page';
  String get remove => chinese ? '从副本中移除此页' : 'Remove from copy';
  String get cancel => chinese ? '取消' : 'Cancel';
  String get saveCopy => chinese ? '预览并另存副本' : 'Preview and save copy';
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
