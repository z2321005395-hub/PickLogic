import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_research_core/picklogic_research_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_system_insight_core/picklogic_system_insight_core.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

import 'pro_pdf_reader.dart';
import 'pro_translation.dart';
import 'workspace_controller.dart';

const Set<String> proWorkspaceSections = {'literature', 'research', 'system'};

typedef LiteraturePdfPicker = Future<String?> Function();
typedef LiteraturePdfMultiPicker = Future<List<String>> Function();
typedef LiteraturePdfSourceBuilder = PdfByteSource Function(String path);
typedef LiteraturePdfReaderBuilder =
    Widget Function(
      BuildContext context,
      LiteratureLibraryEntry entry,
      LiteratureReadingPositionChanged onPositionChanged,
    );

enum _LiteratureStatus {
  catalogUnavailable,
  pdfOnly,
  duplicate,
  invalidPdf,
  added,
  addedWithSkipped,
  addFailed,
  metadataSaved,
  metadataSaveFailed,
  positionSaveFailed,
}

final class ProWorkspaceRoute extends StatelessWidget {
  const ProWorkspaceRoute({
    super.key,
    required this.section,
    this.pdfReaderBuilder,
    this.libraryStore,
    this.pdfPicker,
    this.pdfMultiPicker,
    this.pdfSourceBuilder,
    this.literaturePdfReaderBuilder,
    this.annotationStore,
  });

  final String section;
  final WidgetBuilder? pdfReaderBuilder;
  final LiteratureLibraryStore? libraryStore;
  final LiteraturePdfPicker? pdfPicker;
  final LiteraturePdfMultiPicker? pdfMultiPicker;
  final LiteraturePdfSourceBuilder? pdfSourceBuilder;
  final LiteraturePdfReaderBuilder? literaturePdfReaderBuilder;
  final LiteratureAnnotationStore? annotationStore;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_routeTitle(context, section)),
      actions: [
        Tooltip(
          message: Localizations.localeOf(context).languageCode == 'zh'
              ? '未授权位置只读；测试工作区和已管理目录可按操作预览整理'
              : 'Unauthorized locations are read-only; Test Workspace and managed folders use operation previews',
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.verified_user_outlined, size: 20),
          ),
        ),
      ],
    ),
    body: ProWorkspaceView(
      section: section,
      pdfReaderBuilder: pdfReaderBuilder,
      libraryStore: libraryStore,
      pdfPicker: pdfPicker,
      pdfMultiPicker: pdfMultiPicker,
      pdfSourceBuilder: pdfSourceBuilder,
      literaturePdfReaderBuilder: literaturePdfReaderBuilder,
      annotationStore: annotationStore,
    ),
  );
}

final class ProWorkspaceView extends StatelessWidget {
  const ProWorkspaceView({
    super.key,
    required this.section,
    this.pdfReaderBuilder,
    this.libraryStore,
    this.pdfPicker,
    this.pdfMultiPicker,
    this.pdfSourceBuilder,
    this.literaturePdfReaderBuilder,
    this.annotationStore,
  });

  final String section;
  final WidgetBuilder? pdfReaderBuilder;
  final LiteratureLibraryStore? libraryStore;
  final LiteraturePdfPicker? pdfPicker;
  final LiteraturePdfMultiPicker? pdfMultiPicker;
  final LiteraturePdfSourceBuilder? pdfSourceBuilder;
  final LiteraturePdfReaderBuilder? literaturePdfReaderBuilder;
  final LiteratureAnnotationStore? annotationStore;

  @override
  Widget build(BuildContext context) => switch (section) {
    'literature' => LiteratureManagerLiteView(
      pdfReaderBuilder: pdfReaderBuilder,
      libraryStore: libraryStore,
      pdfPicker: pdfPicker,
      pdfMultiPicker: pdfMultiPicker,
      pdfSourceBuilder: pdfSourceBuilder,
      literaturePdfReaderBuilder: literaturePdfReaderBuilder,
      annotationStore: annotationStore,
    ),
    'research' => const ResearchBucketsView(),
    'system' => const SystemInsightReadOnlyView(),
    _ => const SizedBox.shrink(),
  };
}

final class LiteratureManagerLiteView extends StatefulWidget {
  const LiteratureManagerLiteView({
    super.key,
    this.pdfReaderBuilder,
    this.libraryStore,
    this.pdfPicker,
    this.pdfMultiPicker,
    this.pdfSourceBuilder,
    this.literaturePdfReaderBuilder,
    this.annotationStore,
  });

  final WidgetBuilder? pdfReaderBuilder;
  final LiteratureLibraryStore? libraryStore;
  final LiteraturePdfPicker? pdfPicker;
  final LiteraturePdfMultiPicker? pdfMultiPicker;
  final LiteraturePdfSourceBuilder? pdfSourceBuilder;
  final LiteraturePdfReaderBuilder? literaturePdfReaderBuilder;
  final LiteratureAnnotationStore? annotationStore;

  @override
  State<LiteratureManagerLiteView> createState() =>
      _LiteratureManagerLiteViewState();
}

final class _LiteratureManagerLiteViewState
    extends State<LiteratureManagerLiteView> {
  late final WindowsOpenAiCompatibleTranslationProvider _translationProvider =
      WindowsOpenAiCompatibleTranslationProvider();
  late final WindowsWorkspaceController _workspaceController =
      WindowsWorkspaceController();
  late final Future<WindowsBrowseRoot> _workspaceReady;
  late final Future<LiteratureLibraryStore> _storeFuture;
  late final Future<LiteratureAnnotationStore> _annotationStoreFuture;
  final TextEditingController _librarySearchController =
      TextEditingController();
  Future<void> _saveTail = Future<void>.value();
  List<LiteratureLibraryEntry> _entries = const <LiteratureLibraryEntry>[];
  final Map<String, List<LiteratureAnnotation>> _annotations = {};
  String? _selectedId;
  String? _tagFilter;
  _LiteratureStatus? _status;
  bool _loading = true;
  bool _adding = false;
  bool _dragging = false;
  bool _catalogAvailable = true;
  int _statusCount = 0;

  @override
  void initState() {
    super.initState();
    _storeFuture = widget.libraryStore == null
        ? _createDefaultStore()
        : Future<LiteratureLibraryStore>.value(widget.libraryStore);
    _annotationStoreFuture = widget.annotationStore == null
        ? _createDefaultAnnotationStore()
        : Future<LiteratureAnnotationStore>.value(widget.annotationStore);
    _workspaceReady = _workspaceController.initialize();
    unawaited(_loadLibrary());
  }

  @override
  void dispose() {
    _librarySearchController.dispose();
    super.dispose();
  }

  Future<LiteratureLibraryStore> _createDefaultStore() async {
    final supportDirectory = await const PicklogicWindowsBridge()
        .getApplicationSupportDirectory();
    final separator = Platform.pathSeparator;
    final sqlitePath = '$supportDirectory${separator}literature_catalog_v1.db';
    final legacyPath =
        '$supportDirectory${separator}literature_catalog_v1.json';
    final sqliteStore = SqliteLiteratureLibraryStore(sqlitePath);
    final hadSqliteCatalog = await File(sqlitePath).exists();
    if (!hadSqliteCatalog && await File(legacyPath).exists()) {
      final legacyEntries = await JsonFileLiteratureLibraryStore(
        legacyPath,
      ).load();
      await sqliteStore.save(legacyEntries);
    }
    return sqliteStore;
  }

  Future<LiteratureAnnotationStore> _createDefaultAnnotationStore() async {
    final supportDirectory = await const PicklogicWindowsBridge()
        .getApplicationSupportDirectory();
    final sqlitePath =
        '$supportDirectory${Platform.pathSeparator}literature_catalog_v1.db';
    return SqliteLiteratureAnnotationStore(sqlitePath);
  }

  Future<void> _loadLibrary() async {
    try {
      final store = await _storeFuture;
      final entries = await store.load();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _selectedId = entries.firstOrNull?.id;
        _loading = false;
      });
      final selectedId = entries.firstOrNull?.id;
      if (selectedId != null) unawaited(_loadAnnotations(selectedId));
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _catalogAvailable = false;
        _status = _LiteratureStatus.catalogUnavailable;
      });
    }
  }

  Future<void> _loadAnnotations(String literatureId) async {
    try {
      final store = await _annotationStoreFuture;
      final annotations = await store.loadFor(literatureId);
      if (!mounted) return;
      setState(() => _annotations[literatureId] = annotations);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_LiteratureStrings.of(context).annotationLoadFailed),
          ),
        );
      }
    }
  }

  void _selectEntry(String id) {
    setState(() => _selectedId = id);
    if (!_annotations.containsKey(id)) unawaited(_loadAnnotations(id));
  }

  Future<void> _saveAnnotation(LiteratureAnnotation annotation) async {
    final store = await _annotationStoreFuture;
    await store.upsert(annotation);
    await _loadAnnotations(annotation.literatureId);
  }

  Future<void> _deleteAnnotation(String literatureId, String id) async {
    final store = await _annotationStoreFuture;
    await store.delete(id);
    await _loadAnnotations(literatureId);
  }

  Future<void> _addLiterature() async {
    if (_adding || !_catalogAvailable) return;
    setState(() {
      _adding = true;
      _status = null;
    });
    try {
      final strings = _LiteratureStrings.of(context);
      final paths = widget.pdfMultiPicker != null
          ? await widget.pdfMultiPicker!.call()
          : widget.pdfPicker != null
          ? <String>[
              if (await widget.pdfPicker!.call() case final String path) path,
            ]
          : await const PicklogicWindowsBridge().pickPdfFiles(
              title: strings.pdfPickerTitle,
            );
      if (paths.isNotEmpty) await _importLiterature(paths);
    } on Object {
      if (mounted) {
        setState(() => _status = _LiteratureStatus.addFailed);
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _importDroppedLiterature(List<String> paths) async {
    if (_adding || !_catalogAvailable || paths.isEmpty) return;
    setState(() {
      _adding = true;
      _dragging = false;
      _status = null;
    });
    try {
      await _importLiterature(paths);
    } on Object {
      if (mounted) setState(() => _status = _LiteratureStatus.addFailed);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _importLiterature(List<String> paths) async {
    final knownPaths = <String>{
      for (final entry in _entries) entry.localPath.toLowerCase(),
    };
    final additions = <LiteratureLibraryEntry>[];
    var skippedPdfOnly = false;
    var skippedDuplicate = false;
    var skippedInvalid = false;
    var skippedFailure = false;

    for (final path in paths.toSet()) {
      if (!path.toLowerCase().endsWith('.pdf')) {
        skippedPdfOnly = true;
        continue;
      }
      if (!knownPaths.add(path.toLowerCase())) {
        skippedDuplicate = true;
        continue;
      }
      try {
        final source =
            widget.pdfSourceBuilder?.call(path) ?? FilePdfByteSource(path);
        final probe = await const BoundedPdfMetadataReader().read(source);
        if (!probe.hasPdfHeader) {
          skippedInvalid = true;
          continue;
        }
        additions.add(
          LiteratureLibraryEntry.fromProbe(
            localPath: path,
            fileName: _fileNameFromPath(path),
            probe: probe,
            addedAt: DateTime.now().toUtc(),
          ),
        );
      } on Object {
        skippedFailure = true;
      }
    }

    if (additions.isEmpty) {
      if (!mounted) return;
      setState(() {
        _statusCount = 0;
        _status = skippedFailure
            ? _LiteratureStatus.addFailed
            : skippedInvalid
            ? _LiteratureStatus.invalidPdf
            : skippedPdfOnly
            ? _LiteratureStatus.pdfOnly
            : _LiteratureStatus.duplicate;
      });
      return;
    }

    final updated = List<LiteratureLibraryEntry>.unmodifiable([
      ...additions.reversed,
      ..._entries,
    ]);
    await _enqueueSave(updated);
    if (!mounted) return;
    setState(() {
      _entries = updated;
      _selectedId = additions.last.id;
      _statusCount = additions.length;
      _status =
          skippedPdfOnly || skippedDuplicate || skippedInvalid || skippedFailure
          ? _LiteratureStatus.addedWithSkipped
          : _LiteratureStatus.added;
    });
  }

  Future<void> _enqueueSave(List<LiteratureLibraryEntry> entries) {
    final operation = _saveTail.then((_) async {
      final store = await _storeFuture;
      await store.save(entries);
    });
    _saveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _recordPosition(String id, int currentPage, int totalPages) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final updatedEntry = _entries[index].recordPosition(
      currentPage: currentPage,
      totalPages: totalPages,
      openedAt: DateTime.now().toUtc(),
    );
    final updated = List<LiteratureLibraryEntry>.of(_entries);
    updated[index] = updatedEntry;
    final snapshot = List<LiteratureLibraryEntry>.unmodifiable(updated);
    setState(() => _entries = snapshot);
    unawaited(_persistReadingPosition(snapshot));
  }

  Future<void> _persistReadingPosition(
    List<LiteratureLibraryEntry> snapshot,
  ) async {
    try {
      await _enqueueSave(snapshot);
    } on Object {
      if (mounted) {
        setState(() => _status = _LiteratureStatus.positionSaveFailed);
      }
    }
  }

  LiteratureLibraryEntry? get _selectedEntry =>
      _entries.where((entry) => entry.id == _selectedId).firstOrNull;

  List<LiteratureLibraryEntry> get _visibleEntries {
    final query = _librarySearchController.text.trim().toLowerCase();
    return _entries
        .where((entry) {
          final record = entry.record;
          if (_tagFilter != null && !record.tags.contains(_tagFilter)) {
            return false;
          }
          if (query.isEmpty) return true;
          final searchable = <String>[
            record.title,
            ...record.authors,
            record.journal,
            record.doi ?? '',
            ...record.tags,
            ...record.keywords,
            entry.fileName,
          ].join('\n').toLowerCase();
          return searchable.contains(query);
        })
        .toList(growable: false);
  }

  List<String> get _availableTags {
    final tags =
        <String>{
          for (final entry in _entries) ...entry.record.tags,
        }.toList(growable: false)..sort(
          (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
        );
    return tags;
  }

  Future<void> _showCitation(
    LiteratureLibraryEntry entry,
    _LiteratureStrings strings,
  ) async {
    const formatter = LiteratureCitationFormatter();
    var format = CitationExportFormat.plainText;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final output = formatter.format(entry.record, format: format);
          return AlertDialog(
            key: const Key('literature-citation-dialog'),
            title: Text(strings.citationExport),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<CitationExportFormat>(
                    segments: const [
                      ButtonSegment(
                        value: CitationExportFormat.plainText,
                        label: Text('Text'),
                      ),
                      ButtonSegment(
                        value: CitationExportFormat.bibtex,
                        label: Text('BibTeX'),
                      ),
                      ButtonSegment(
                        value: CitationExportFormat.ris,
                        label: Text('RIS'),
                      ),
                    ],
                    selected: <CitationExportFormat>{format},
                    onSelectionChanged: (value) =>
                        setDialogState(() => format = value.single),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        output,
                        key: const Key('literature-citation-output'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    strings.citationPortability,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                key: const Key('literature-copy-intext-action'),
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: formatter.inText(entry.record)),
                ),
                icon: const Icon(Icons.format_quote_outlined),
                label: Text(strings.copyInText),
              ),
              FilledButton.tonalIcon(
                key: const Key('literature-copy-citation-action'),
                onPressed: () => Clipboard.setData(ClipboardData(text: output)),
                icon: const Icon(Icons.copy_outlined),
                label: Text(strings.copyCitation),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(strings.close),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMetadata(
    LiteratureLibraryEntry entry,
    _LiteratureStrings strings,
  ) async {
    final edit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('literature-metadata-dialog'),
        title: Text(strings.literatureMetadata),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LabelValue(label: strings.fileName, value: entry.fileName),
                _LabelValue(label: strings.localPath, value: entry.localPath),
                _LabelValue(label: strings.title, value: entry.record.title),
                _LabelValue(
                  label: strings.author,
                  value: entry.record.authors.isEmpty
                      ? strings.notFound
                      : entry.record.authors.join('; '),
                ),
                _LabelValue(
                  label: strings.journal,
                  value: entry.record.journal.isEmpty
                      ? strings.notFound
                      : entry.record.journal,
                ),
                _LabelValue(
                  label: 'DOI',
                  value: entry.record.doi ?? strings.notFound,
                ),
                _LabelValue(
                  label: strings.year,
                  value: entry.record.year?.toString() ?? strings.notFound,
                ),
                const SizedBox(height: 8),
                Text(strings.metadataLimit),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('literature-edit-metadata-action'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.editMetadata),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.close),
          ),
        ],
      ),
    );
    if (edit == true && mounted) {
      await _showMetadataEditor(entry, strings);
    }
  }

  Future<void> _showMetadataEditor(
    LiteratureLibraryEntry entry,
    _LiteratureStrings strings,
  ) async {
    final titleController = TextEditingController(text: entry.record.title);
    final authorsController = TextEditingController(
      text: entry.record.authors.join('; '),
    );
    final journalController = TextEditingController(text: entry.record.journal);
    final doiController = TextEditingController(text: entry.record.doi ?? '');
    final volumeController = TextEditingController(text: entry.record.volume);
    final issueController = TextEditingController(text: entry.record.issue);
    final pagesController = TextEditingController(text: entry.record.pages);
    final tagsController = TextEditingController(
      text: entry.record.tags.join('; '),
    );
    final yearController = TextEditingController(
      text: entry.record.year?.toString() ?? '',
    );
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('literature-metadata-editor'),
          title: Text(strings.editMetadata),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('literature-title-field'),
                    controller: titleController,
                    decoration: InputDecoration(labelText: strings.title),
                  ),
                  TextField(
                    key: const Key('literature-authors-field'),
                    controller: authorsController,
                    decoration: InputDecoration(labelText: strings.authorsHint),
                  ),
                  TextField(
                    key: const Key('literature-journal-field'),
                    controller: journalController,
                    decoration: InputDecoration(labelText: strings.journal),
                  ),
                  TextField(
                    key: const Key('literature-doi-field'),
                    controller: doiController,
                    decoration: const InputDecoration(labelText: 'DOI'),
                  ),
                  TextField(
                    key: const Key('literature-year-field'),
                    controller: yearController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: strings.year),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: volumeController,
                          decoration: InputDecoration(
                            labelText: strings.volume,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: issueController,
                          decoration: InputDecoration(labelText: strings.issue),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: pagesController,
                          decoration: InputDecoration(labelText: strings.pages),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    key: const Key('literature-tags-field'),
                    controller: tagsController,
                    decoration: InputDecoration(labelText: strings.tagsHint),
                  ),
                  const SizedBox(height: 12),
                  Text(strings.manualMetadataNotice),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const Key('literature-save-metadata-action'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.save),
            ),
          ],
        ),
      );
      if (save != true || !mounted) return;
      final title = titleController.text.trim();
      final year = int.tryParse(yearController.text.trim());
      if (title.isEmpty ||
          (yearController.text.trim().isNotEmpty && year == null)) {
        setState(() => _status = _LiteratureStatus.metadataSaveFailed);
        return;
      }
      final record = entry.record;
      final updatedRecord = LiteratureRecord(
        id: record.id,
        localFileId: record.localFileId,
        doi: doiController.text.trim().isEmpty
            ? null
            : doiController.text.trim(),
        title: title,
        authors: authorsController.text
            .split(RegExp(r'[;,]'))
            .map((author) => author.trim())
            .where((author) => author.isNotEmpty)
            .toList(growable: false),
        journal: journalController.text.trim(),
        year: year,
        volume: volumeController.text.trim(),
        issue: issueController.text.trim(),
        pages: pagesController.text.trim(),
        abstractText: record.abstractText,
        keywords: record.keywords,
        tags: tagsController.text
            .split(RegExp(r'[;,]'))
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(growable: false),
        readingProgress: record.readingProgress,
        lastOpenedAt: record.lastOpenedAt,
        metadataSource: 'manual local edit',
        metadataConfidence: 1,
      );
      final index = _entries.indexWhere(
        (candidate) => candidate.id == entry.id,
      );
      if (index < 0) return;
      final updatedEntries = List<LiteratureLibraryEntry>.of(_entries);
      updatedEntries[index] = entry.replaceRecord(updatedRecord);
      final snapshot = List<LiteratureLibraryEntry>.unmodifiable(
        updatedEntries,
      );
      await _enqueueSave(snapshot);
      if (!mounted) return;
      setState(() {
        _entries = snapshot;
        _status = _LiteratureStatus.metadataSaved;
      });
    } on Object {
      if (mounted) {
        setState(() => _status = _LiteratureStatus.metadataSaveFailed);
      }
    } finally {
      // showDialog completes when pop starts, while the closing route can still
      // paint its text fields for a few frames. Keep controllers alive through
      // that transition before releasing their listeners.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      titleController.dispose();
      authorsController.dispose();
      journalController.dispose();
      doiController.dispose();
      volumeController.dispose();
      issueController.dispose();
      pagesController.dispose();
      tagsController.dispose();
      yearController.dispose();
    }
  }

  Future<void> _showRenamePreview(
    LiteratureLibraryEntry entry,
    _LiteratureStrings strings,
  ) async {
    final preview = const LiteratureNaming().previewRename(
      record: entry.record,
      originalFileName: entry.fileName,
    );
    final access = _workspaceController.accessFor(entry.localPath);
    final mayRename = access != WorkspaceAccessLevel.browseOnly;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('literature-rename-preview-dialog'),
        title: Text(strings.renamePreview),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LabelValue(label: strings.current, value: entry.fileName),
              _LabelValue(
                label: strings.preview,
                value: preview.proposedFileName,
              ),
              const SizedBox(height: 8),
              Text(
                mayRename
                    ? strings.renameAuthorized(
                        access == WorkspaceAccessLevel.testWorkspace,
                      )
                    : strings.previewOnly,
              ),
            ],
          ),
        ),
        actions: [
          if (!mayRename)
            OutlinedButton.icon(
              key: const Key('literature-authorize-folder-action'),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _workspaceReady;
                final selected = await _workspaceController
                    .authorizeManagedFolder(chinese: strings.isChinese);
                if (selected != null && mounted) {
                  await _showRenamePreview(entry, strings);
                }
              },
              icon: const Icon(Icons.folder_shared_outlined),
              label: Text(strings.authorizeFolder),
            ),
          if (mayRename)
            FilledButton.icon(
              key: const Key('literature-confirm-rename-action'),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _executeLiteratureRename(
                  entry,
                  preview.proposedFileName,
                  strings,
                );
              },
              icon: const Icon(Icons.drive_file_rename_outline),
              label: Text(strings.confirmRename),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.close),
          ),
        ],
      ),
    );
  }

  Future<void> _executeLiteratureRename(
    LiteratureLibraryEntry entry,
    String proposedName,
    _LiteratureStrings strings,
  ) async {
    OperationResult? result;
    try {
      final previewed = await _workspaceController.previewRename(
        entry.localPath,
        proposedName,
      );
      result = await _workspaceController.execute(
        previewed.transitionTo(OperationStatus.confirmed),
      );
      if (!result.success || result.plan.destination == null) {
        throw StateError(result.message);
      }
      final destination = result.plan.destination!.value;
      final renamedEntry = LiteratureLibraryEntry(
        record: entry.record,
        localPath: destination,
        fileName: File(destination).uri.pathSegments.last,
        addedAt: entry.addedAt,
        currentPage: entry.currentPage,
        totalPages: entry.totalPages,
      );
      final index = _entries.indexWhere(
        (candidate) => candidate.id == entry.id,
      );
      if (index < 0) throw StateError('The literature entry no longer exists.');
      final updated = List<LiteratureLibraryEntry>.of(_entries);
      updated[index] = renamedEntry;
      final snapshot = List<LiteratureLibraryEntry>.unmodifiable(updated);
      try {
        await _enqueueSave(snapshot);
      } on Object {
        await _workspaceController.undo(result.plan);
        rethrow;
      }
      if (!mounted) return;
      setState(() => _entries = snapshot);
      final completedPlan = result.plan;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.renameCompleted),
          action: SnackBarAction(
            label: strings.undo,
            onPressed: () => unawaited(
              _undoLiteratureRename(
                original: entry,
                renamed: renamedEntry,
                completedPlan: completedPlan,
                strings: strings,
              ),
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.renameFailed}: $error')),
      );
    }
  }

  Future<void> _undoLiteratureRename({
    required LiteratureLibraryEntry original,
    required LiteratureLibraryEntry renamed,
    required OperationPlan completedPlan,
    required _LiteratureStrings strings,
  }) async {
    try {
      final undo = await _workspaceController.undo(completedPlan);
      if (!undo.success) throw StateError(undo.message);
      final index = _entries.indexWhere(
        (candidate) => candidate.id == renamed.id,
      );
      if (index < 0) return;
      final updated = List<LiteratureLibraryEntry>.of(_entries);
      updated[index] = original;
      final snapshot = List<LiteratureLibraryEntry>.unmodifiable(updated);
      await _enqueueSave(snapshot);
      if (!mounted) return;
      setState(() => _entries = snapshot);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.renameUndone)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${strings.undoFailed}: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _LiteratureStrings.of(context);
    final selected = _selectedEntry;
    return DropTarget(
      enable: !_loading && !_adding && _catalogAvailable,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) => unawaited(
        _importDroppedLiterature(
          details.files.map((file) => file.path).toList(growable: false),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            key: const Key('literature-manager-lite-view'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProHeader(
                  icon: Icons.menu_book_outlined,
                  title: strings.managerTitle,
                  subtitle: strings.managerSubtitle,
                  badge: strings.localReadOnly,
                  trailing: FilledButton.icon(
                    key: const Key('literature-add-action'),
                    onPressed: _loading || _adding || !_catalogAvailable
                        ? null
                        : _addLiterature,
                    icon: _adding
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(strings.addLiterature),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        strings.status(_status!, count: _statusCount),
                        key: const Key('literature-status'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_entries.isEmpty)
                  Expanded(
                    child: _EmptyWorkspace(
                      icon: Icons.picture_as_pdf_outlined,
                      title: strings.library,
                      message: strings.emptyLibrary,
                    ),
                  )
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final library = _buildLibraryList(strings);
                        final reader = selected == null
                            ? _EmptyWorkspace(
                                icon: Icons.menu_book_outlined,
                                title: strings.selectLiterature,
                                message: strings.selectLiteratureHint,
                              )
                            : _buildReaderPane(selected, strings);
                        if (constraints.maxWidth < 820) {
                          return Column(
                            children: [
                              SizedBox(height: 210, child: library),
                              const SizedBox(height: 10),
                              Expanded(child: reader),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 310, child: library),
                            const SizedBox(width: 12),
                            Expanded(child: reader),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  strings.libraryPrivacy,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('literature-drop-overlay'),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.94),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      strings.dropPdfHere,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLibraryList(_LiteratureStrings strings) {
    final entries = _visibleEntries;
    final tags = _availableTags;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.persistentLibrary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('literature-library-search'),
                  controller: _librarySearchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: strings.searchLibrary,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _librarySearchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.clearSearch,
                            onPressed: () {
                              _librarySearchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text(strings.allTags),
                          selected: _tagFilter == null,
                          onSelected: (_) => setState(() => _tagFilter = null),
                        ),
                        for (final tag in tags) ...[
                          const SizedBox(width: 6),
                          ChoiceChip(
                            label: Text(tag),
                            selected: _tagFilter == tag,
                            onSelected: (_) => setState(() => _tagFilter = tag),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(child: Text(strings.noLibraryMatches))
                : ListView.separated(
                    key: const Key('literature-library-list'),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final record = entry.record;
                      final annotationCount =
                          _annotations[entry.id]?.length ?? 0;
                      return ListTile(
                        key: Key('literature-entry-${entry.id}'),
                        selected: entry.id == _selectedId,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(
                          record.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${record.authors.isEmpty ? strings.authorUnknown : record.authors.first} · '
                          '${record.year?.toString() ?? strings.yearUnknown}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${(record.readingProgress * 100).round()}%'),
                            if (annotationCount > 0)
                              Text(
                                strings.annotationCount(annotationCount),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                          ],
                        ),
                        onTap: () => _selectEntry(entry.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderPane(
    LiteratureLibraryEntry selected,
    _LiteratureStrings strings,
  ) {
    final progressPercent = (selected.record.readingProgress * 100).round();
    final reader =
        widget.literaturePdfReaderBuilder?.call(
          context,
          selected,
          (currentPage, totalPages) =>
              _recordPosition(selected.id, currentPage, totalPages),
        ) ??
        widget.pdfReaderBuilder?.call(context) ??
        ProLocalPdfReader(
          key: ValueKey<String>(selected.id),
          path: selected.localPath,
          fileName: selected.fileName,
          initialPageNumber: selected.currentPage,
          onPositionChanged: (currentPage, totalPages) =>
              _recordPosition(selected.id, currentPage, totalPages),
          translationProvider: _translationProvider,
          onConfigureTranslation: () => unawaited(
            showTranslationConfigurationDialog(context, _translationProvider),
          ),
          literatureId: selected.id,
          annotations:
              _annotations[selected.id] ?? const <LiteratureAnnotation>[],
          onSaveAnnotation: _saveAnnotation,
          onDeleteAnnotation: (id) => _deleteAnnotation(selected.id, id),
        );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.record.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selected.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('literature-metadata-action'),
                      onPressed: () => _showMetadata(selected, strings),
                      icon: const Icon(Icons.info_outline),
                      label: Text(strings.metadataAction),
                    ),
                    OutlinedButton.icon(
                      key: const Key('literature-rename-preview-action'),
                      onPressed: () => _showRenamePreview(selected, strings),
                      icon: const Icon(Icons.drive_file_rename_outline),
                      label: Text(strings.previewAction),
                    ),
                    OutlinedButton.icon(
                      key: const Key('literature-citation-action'),
                      onPressed: () => _showCitation(selected, strings),
                      icon: const Icon(Icons.format_quote_outlined),
                      label: Text(strings.citationAction),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: selected.record.readingProgress,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  selected.totalPages == null
                      ? '$progressPercent%'
                      : strings.pagePosition(
                          selected.currentPage,
                          selected.totalPages!,
                        ),
                  key: const Key('literature-page-position'),
                ),
                Text(
                  '$progressPercent%',
                  key: const Key('literature-progress-value'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(child: reader),
          ],
        ),
      ),
    );
  }

  String _fileNameFromPath(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}

final class ResearchBucketsView extends StatelessWidget {
  const ResearchBucketsView({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = _ResearchStrings.of(context);
    final workspace =
        ResearchWorkspace(
            id: 'synthetic-project',
            name: 'Synthetic microscopy project',
          )
          ..link(
            const ResearchLink(
              projectId: 'synthetic-project',
              fileId: 'paper',
              bucket: ResearchBucket.literature,
              note: 'Local literature record',
            ),
          )
          ..link(
            const ResearchLink(
              projectId: 'synthetic-project',
              fileId: 'table',
              bucket: ResearchBucket.rawData,
              note: 'Synthetic measurements',
            ),
          )
          ..link(
            const ResearchLink(
              projectId: 'synthetic-project',
              fileId: 'image',
              bucket: ResearchBucket.figures,
              note: 'Synthetic figure',
            ),
          );
    return Padding(
      key: const Key('research-buckets-view'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProHeader(
            icon: Icons.science_outlined,
            title: strings.title,
            subtitle: strings.subtitle,
            badge: strings.virtualLinks,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                key: const Key('research-bucket-grid'),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: constraints.maxWidth >= 1000
                      ? 4
                      : constraints.maxWidth >= 620
                      ? 2
                      : 1,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: constraints.maxWidth >= 620 ? 2.2 : 3.2,
                  children: [
                    for (final summary in workspace.bucketSummaries)
                      _BucketCard(summary: summary, strings: strings),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.readOnlyNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final class SystemInsightReadOnlyView extends StatelessWidget {
  const SystemInsightReadOnlyView({super.key});

  static const _observations = [
    SystemObservation(
      kind: SystemObservationKind.softwareCache,
      label: 'Synthetic application cache',
      sizeBytes: 12582912,
      isWindowsCore: false,
      isRunning: false,
      isSigned: true,
      ownerApplication: 'Synthetic App',
      evidence: ['Synthetic cache classification supplied by a fixture.'],
    ),
    SystemObservation(
      kind: SystemObservationKind.service,
      label: 'Synthetic Windows service',
      sizeBytes: 0,
      isWindowsCore: true,
      isRunning: true,
      isSigned: true,
      ownerApplication: 'Windows',
      evidence: ['Fixture marks this observation as Windows core.'],
    ),
    SystemObservation(
      kind: SystemObservationKind.unknown,
      label: 'Synthetic unknown component',
      sizeBytes: 4096,
      isWindowsCore: false,
      isRunning: false,
      isSigned: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = _SystemStrings.of(context);
    return Padding(
      key: const Key('system-insight-read-only-view'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProHeader(
            icon: Icons.monitor_heart_outlined,
            title: strings.title,
            subtitle: strings.subtitle,
            badge: strings.noChanges,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              key: const Key('system-observation-list'),
              itemCount: _observations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _SystemObservationCard(
                observation: _observations[index],
                strings: strings,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.readOnlyNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

final class _ProHeader extends StatelessWidget {
  const _ProHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final identity = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Chip(label: Text(badge)),
        ],
      );
      if (trailing == null) return identity;
      if (constraints.maxWidth < 700) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: trailing!),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: identity),
          const SizedBox(width: 10),
          trailing!,
        ],
      );
    },
  );
}

final class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, child: Text(label)),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

final class _BucketCard extends StatelessWidget {
  const _BucketCard({required this.summary, required this.strings});

  final ResearchBucketSummary summary;
  final _ResearchStrings strings;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('research-bucket-${summary.bucket.name}'),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(_bucketIcon(summary.bucket)),
          Text(
            strings.bucketLabel(summary.bucket),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(strings.linkedItems(summary.count)),
        ],
      ),
    ),
  );
}

final class _SystemObservationCard extends StatelessWidget {
  const _SystemObservationCard({
    required this.observation,
    required this.strings,
  });

  final SystemObservation observation;
  final _SystemStrings strings;

  Future<void> _showInsight(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: Key('system-insight-dialog-${observation.kind.name}'),
      title: Text(strings.observationLabel(observation.kind)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabelValue(
              label: strings.category,
              value: strings.categoryValue(observation.kind),
            ),
            _LabelValue(
              label: strings.status,
              value: strings.statusValue(observation),
            ),
            const SizedBox(height: 8),
            Text(strings.insightDetail(observation.kind)),
            const SizedBox(height: 8),
            Text(strings.syntheticRestriction),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.close),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(_systemIcon(observation.kind)),
      title: Text(strings.observationLabel(observation.kind)),
      subtitle: Text(strings.observationSummary(observation.kind)),
      trailing: OutlinedButton(
        key: Key('system-insight-action-${observation.kind.name}'),
        onPressed: () => _showInsight(context),
        child: Text(strings.viewInsight),
      ),
    ),
  );
}

IconData _bucketIcon(ResearchBucket bucket) => switch (bucket) {
  ResearchBucket.literature => Icons.menu_book_outlined,
  ResearchBucket.rawData => Icons.dataset_outlined,
  ResearchBucket.processedData => Icons.analytics_outlined,
  ResearchBucket.figures => Icons.image_outlined,
  ResearchBucket.scripts => Icons.code_outlined,
  ResearchBucket.notes => Icons.note_alt_outlined,
  ResearchBucket.presentations => Icons.slideshow_outlined,
  ResearchBucket.manuscripts => Icons.article_outlined,
};

final class _LiteratureStrings {
  const _LiteratureStrings(this.isChinese);

  factory _LiteratureStrings.of(BuildContext context) => _LiteratureStrings(
    PickLogicLocalizations.of(context).locale.languageCode == 'zh',
  );

  final bool isChinese;

  String get managerTitle => isChinese ? '轻量文献管理' : 'Literature Manager Lite';
  String get managerSubtitle => isChinese
      ? '本地目录 · 有界元数据 · PDF 不上传、不改写'
      : 'Local catalog · bounded metadata · PDFs are never uploaded or modified';
  String get localReadOnly => isChinese ? '本地只读' : 'LOCAL READ-ONLY';
  String get addLiterature => isChinese ? '添加文献' : 'Add literature';
  String get pdfPickerTitle => isChinese ? '添加本地 PDF 文献' : 'Add a local PDF';
  String get library => isChinese ? '文献列表' : 'Library';
  String get emptyLibrary => isChinese
      ? '暂无文献。点击“添加文献”选择 PDF，或直接拖入 PDF；不会扫描目录。'
      : 'No literature yet. Choose Add literature or drop PDFs here; no directory will be scanned.';
  String get persistentLibrary =>
      isChinese ? '文献列表 · 持久保存' : 'Library · Persistent';
  String get searchLibrary => isChinese
      ? '搜索标题、作者、期刊、DOI 或标签'
      : 'Search title, author, journal, DOI, or tag';
  String get clearSearch => isChinese ? '清除搜索' : 'Clear search';
  String get allTags => isChinese ? '全部' : 'All';
  String get noLibraryMatches =>
      isChinese ? '没有匹配的文献。' : 'No matching literature.';
  String annotationCount(int count) =>
      isChinese ? '$count 条批注' : '$count notes';
  String get authorUnknown => isChinese ? '作者未知' : 'Author unknown';
  String get yearUnknown => isChinese ? '年份未知' : 'Year unknown';
  String get doiNotFound => isChinese ? '未发现 DOI' : 'DOI not found';
  String get literatureMetadata => isChinese ? '文献元数据' : 'Literature metadata';
  String get metadataAction => isChinese ? '元数据' : 'Metadata';
  String get previewAction => isChinese ? '重命名预览' : 'Rename preview';
  String get citationAction => isChinese ? '引用' : 'Cite';
  String get citationExport => isChinese ? '引用与导出' : 'Citation and export';
  String get copyCitation => isChinese ? '复制引用' : 'Copy citation';
  String get copyInText => isChinese ? '复制文内引用' : 'Copy in-text citation';
  String get citationPortability => isChinese
      ? 'BibTeX 与 RIS 可导入 Zotero、EndNote、ReadCube Papers 等支持标准交换格式的工具。快速文本不是完整 CSL 排版。'
      : 'BibTeX and RIS can be imported into tools that support standard exchange formats, including Zotero, EndNote, and ReadCube Papers. Quick text is not full CSL formatting.';
  String get selectLiterature => isChinese ? '选择一篇文献' : 'Select literature';
  String get selectLiteratureHint => isChinese
      ? '从左侧列表选择 PDF 后即可继续阅读。'
      : 'Choose a PDF from the library to continue reading.';
  String get close => isChinese ? '关闭' : 'Close';
  String get fileName => isChinese ? '文件名' : 'Filename';
  String get localPath => isChinese ? '本地位置' : 'Local location';
  String get title => isChinese ? '标题' : 'Title';
  String get author => isChinese ? '作者' : 'Author';
  String get authorsHint =>
      isChinese ? '作者（用分号分隔）' : 'Authors (semicolon separated)';
  String get journal => isChinese ? '期刊' : 'Journal';
  String get year => isChinese ? '年份' : 'Year';
  String get volume => isChinese ? '卷' : 'Volume';
  String get issue => isChinese ? '期' : 'Issue';
  String get pages => isChinese ? '页码' : 'Pages';
  String get tagsHint => isChinese ? '标签（用分号分隔）' : 'Tags (semicolon separated)';
  String get notFound => isChinese ? '未发现' : 'Not found';
  String get editMetadata => isChinese ? '编辑元数据' : 'Edit metadata';
  String get save => isChinese ? '保存' : 'Save';
  String get cancel => isChinese ? '取消' : 'Cancel';
  String get dropPdfHere =>
      isChinese ? '松开以加入本地 PDF' : 'Drop to add local PDFs';
  String get manualMetadataNotice => isChinese
      ? '这里只修改 PickLogic 书库记录，不写入或重命名原 PDF。'
      : 'This edits only the PickLogic catalog; the source PDF is not written or renamed.';
  String get metadataLimit => isChinese
      ? '元数据来自 PDF 首尾有界窗口；压缩或加密字段可能无法识别。'
      : 'Metadata comes from bounded PDF head and tail windows; compressed or encrypted fields may not be detected.';
  String get pdfReaderLocal =>
      isChinese ? 'PDF 阅读区域 · 本地' : 'PDF reader · Local';
  String get persistentReadingProgress =>
      isChinese ? '阅读进度 · 持久保存' : 'Reading progress · Persistent';
  String get pagePending => isChinese
      ? '页码将在 PDF 打开后保存。'
      : 'The page position will be saved after the PDF opens.';
  String pagePosition(int currentPage, int totalPages) => isChinese
      ? '第 $currentPage / $totalPages 页'
      : 'Page $currentPage of $totalPages';
  String get progressPrivacy => isChinese
      ? '进度仅写入 PickLogic 私有目录，不写入 PDF。'
      : 'Progress is written only to PickLogic private storage, never to the PDF.';
  String get renamePreview => isChinese ? '自动命名预览' : 'Rename preview';
  String get current => isChinese ? '当前文件名' : 'Current';
  String get preview => isChinese ? '预览名称' : 'Preview';
  String get previewOnly => isChinese
      ? '仅预览 · 当前位置为只读。可授权其所在目录后，再通过 OperationPlan 确认重命名。'
      : 'Preview only · this location is read-only. Authorize its folder before confirming a rename through OperationPlan.';
  String renameAuthorized(bool testWorkspace) => isChinese
      ? (testWorkspace
            ? '测试工作区 · 将先创建 OperationPlan，再由你确认执行。'
            : '已管理目录 · 将先创建 OperationPlan，再由你确认执行。')
      : (testWorkspace
            ? 'Test Workspace · an OperationPlan will be created before your confirmation.'
            : 'Managed folder · an OperationPlan will be created before your confirmation.');
  String get authorizeFolder => isChinese ? '授权目录' : 'Authorize folder';
  String get confirmRename => isChinese ? '确认重命名' : 'Confirm rename';
  String get renameCompleted => isChinese
      ? '文献已重命名，书库引用已更新。'
      : 'Literature renamed and the library reference was updated.';
  String get renameFailed => isChinese ? '重命名失败' : 'Rename failed';
  String get undo => isChinese ? '撤销' : 'Undo';
  String get renameUndone => isChinese ? '重命名已撤销。' : 'Rename undone.';
  String get undoFailed => isChinese ? '撤销失败' : 'Undo failed';
  String get libraryPrivacy => isChinese
      ? '列表仅保存本地引用和阅读状态；不会扫描文献目录、上传 PDF 或改动原文件。'
      : 'The library stores only local references and reading state; it never scans literature folders, uploads PDFs, or changes source files.';
  String get annotationLoadFailed => isChinese
      ? '无法读取本地批注；PDF 仍以只读方式打开。'
      : 'Local annotations could not be loaded; the PDF remains open read-only.';

  String status(_LiteratureStatus status, {int count = 0}) => switch (status) {
    _LiteratureStatus.catalogUnavailable =>
      isChinese
          ? '文献目录不可用；为避免覆盖现有状态，添加功能已暂停。'
          : 'The literature catalog is unavailable. Adding is paused to avoid overwriting existing state.',
    _LiteratureStatus.pdfOnly =>
      isChinese ? '仅支持本地 PDF 文件。' : 'Only local PDF files are supported.',
    _LiteratureStatus.duplicate =>
      isChinese ? '该 PDF 已在文献列表中。' : 'This PDF is already in the library.',
    _LiteratureStatus.invalidPdf =>
      isChinese
          ? '所选文件未通过 PDF 头部验证，未添加。'
          : 'The selected file failed PDF header validation and was not added.',
    _LiteratureStatus.added =>
      isChinese
          ? '已添加 ${count == 0 ? 1 : count} 篇文献；PDF 原文件保持只读且位置不变。'
          : '${count == 0 ? 1 : count} literature item(s) added. Source PDFs remain read-only in place.',
    _LiteratureStatus.addedWithSkipped =>
      isChinese
          ? '已添加 $count 篇；重复、非 PDF、损坏或不可读取的项目已跳过。'
          : '$count item(s) added; duplicates, non-PDFs, corrupt, or unreadable items were skipped.',
    _LiteratureStatus.addFailed =>
      isChinese
          ? '无法添加此 PDF；目录状态与原文件均未更改。'
          : 'This PDF could not be added. The catalog and source file were not changed.',
    _LiteratureStatus.metadataSaved =>
      isChinese
          ? '元数据已保存到本地书库；原 PDF 未修改。'
          : 'Metadata saved to the local catalog; the source PDF was not modified.',
    _LiteratureStatus.metadataSaveFailed =>
      isChinese
          ? '元数据未保存；请检查标题和年份。原 PDF 未修改。'
          : 'Metadata was not saved. Check the title and year; the source PDF was not modified.',
    _LiteratureStatus.positionSaveFailed =>
      isChinese
          ? '阅读位置暂未保存；PDF 未被修改。'
          : 'The reading position was not saved. The PDF was not modified.',
  };
}

final class _ResearchStrings {
  const _ResearchStrings(this.isChinese);

  factory _ResearchStrings.of(BuildContext context) => _ResearchStrings(
    PickLogicLocalizations.of(context).locale.languageCode == 'zh',
  );

  final bool isChinese;

  String get title => isChinese ? '研究工作区' : 'Research workspace';
  String get subtitle => isChinese
      ? '合成项目骨架 · 仅虚拟关联，不移动文件'
      : 'Synthetic project skeleton · virtual links only, no file moves';
  String get virtualLinks => isChinese ? '虚拟关联' : 'VIRTUAL LINKS';
  String get readOnlyNote => isChinese
      ? '此页面只保存文件标识的虚拟关联；原位置、文件名和内容均保持不变。'
      : 'This page stores only virtual file-ID links; locations, names, and contents remain unchanged.';

  String bucketLabel(ResearchBucket bucket) => switch (bucket) {
    ResearchBucket.literature => isChinese ? '文献' : 'Literature',
    ResearchBucket.rawData => isChinese ? '原始数据' : 'Raw data',
    ResearchBucket.processedData => isChinese ? '处理后数据' : 'Processed data',
    ResearchBucket.figures => isChinese ? '图像' : 'Figures',
    ResearchBucket.scripts => isChinese ? '脚本' : 'Scripts',
    ResearchBucket.notes => isChinese ? '笔记' : 'Notes',
    ResearchBucket.presentations => isChinese ? '演示文稿' : 'Presentations',
    ResearchBucket.manuscripts => isChinese ? '稿件' : 'Manuscripts',
  };

  String linkedItems(int count) =>
      isChinese ? '$count 个关联项目' : '$count linked item(s)';
}

final class _SystemStrings {
  const _SystemStrings(this.isChinese);

  factory _SystemStrings.of(BuildContext context) => _SystemStrings(
    PickLogicLocalizations.of(context).locale.languageCode == 'zh',
  );

  final bool isChinese;

  String get title => isChinese ? '系统洞察 · 只读' : 'System Insight · Read-only';
  String get subtitle => isChinese
      ? '仅展示合成观测 · 未读取真实系统目录'
      : 'Synthetic observations only · no real system directory was read';
  String get noChanges => isChinese ? '不修改系统' : 'NO SYSTEM CHANGES';
  String get readOnlyNote => isChinese
      ? '未读取真实系统目录，也未修改注册表、服务、启动项、计划任务、卸载器或系统文件。'
      : 'No real system directory was read, and no registry, service, startup, scheduled-task, uninstaller, or system-file change was made.';
  String get viewInsight => isChinese ? '查看洞察' : 'View insight';
  String get category => isChinese ? '类别' : 'Category';
  String get status => isChinese ? '状态' : 'Status';
  String get close => isChinese ? '关闭' : 'Close';
  String get syntheticRestriction => isChinese
      ? '限制：此处仅为合成只读示例，不能据此删除或更改系统项目。'
      : 'Limitation: this is a synthetic read-only example and cannot justify deleting or changing system items.';

  String observationLabel(SystemObservationKind kind) => switch (kind) {
    SystemObservationKind.softwareCache =>
      isChinese ? '合成应用缓存' : 'Synthetic application cache',
    SystemObservationKind.service =>
      isChinese ? '合成系统服务' : 'Synthetic system service',
    SystemObservationKind.unknown =>
      isChinese ? '合成未知组件' : 'Synthetic unknown component',
    _ => isChinese ? '合成系统项目' : 'Synthetic system item',
  };

  String observationSummary(SystemObservationKind kind) => switch (kind) {
    SystemObservationKind.softwareCache =>
      isChinese
          ? '可识别的应用缓存示例；仅建议审阅。'
          : 'Recognized application-cache example; review only.',
    SystemObservationKind.service =>
      isChinese
          ? '受保护的系统服务示例；不可直接更改。'
          : 'Protected system-service example; no direct changes.',
    SystemObservationKind.unknown =>
      isChinese
          ? '证据不足的未知项目示例；保持不变。'
          : 'Unknown-item example with insufficient evidence; leave unchanged.',
    _ => isChinese ? '只读系统观测示例。' : 'Read-only system observation example.',
  };

  String categoryValue(SystemObservationKind kind) => switch (kind) {
    SystemObservationKind.softwareCache =>
      isChinese ? '软件缓存' : 'Software cache',
    SystemObservationKind.service => isChinese ? '系统服务' : 'System service',
    SystemObservationKind.unknown => isChinese ? '未知' : 'Unknown',
    _ => isChinese ? '系统项目' : 'System item',
  };

  String statusValue(SystemObservation observation) => observation.isWindowsCore
      ? (isChinese ? '受保护' : 'Protected')
      : observation.kind == SystemObservationKind.unknown
      ? (isChinese ? '未知' : 'Unknown')
      : (isChinese ? '仅审阅' : 'Review only');

  String insightDetail(SystemObservationKind kind) => switch (kind) {
    SystemObservationKind.softwareCache =>
      isChinese
          ? '事实：合成夹具将其标记为应用缓存。建议：仅在所属应用的官方设置中审阅。'
          : 'Fact: the synthetic fixture marks this as application cache. Recommendation: review it only through the owning application settings.',
    SystemObservationKind.service =>
      isChinese
          ? '事实：合成夹具将其标记为核心系统服务。建议：保持不变。'
          : 'Fact: the synthetic fixture marks this as a core system service. Recommendation: leave it unchanged.',
    SystemObservationKind.unknown =>
      isChinese
          ? '事实：当前证据无法识别此合成项目。建议：保持不变并补充证据。'
          : 'Fact: available evidence cannot identify this synthetic item. Recommendation: leave it unchanged and gather more evidence.',
    _ =>
      isChinese
          ? '这是一个合成的只读系统观测。'
          : 'This is a synthetic read-only system observation.',
  };
}

IconData _systemIcon(SystemObservationKind kind) => switch (kind) {
  SystemObservationKind.softwareCache => Icons.cached_outlined,
  SystemObservationKind.service => Icons.settings_suggest_outlined,
  SystemObservationKind.unknown => Icons.help_outline,
  _ => Icons.monitor_heart_outlined,
};

String _routeTitle(BuildContext context, String section) {
  final isChinese =
      PickLogicLocalizations.of(context).locale.languageCode == 'zh';
  return switch (section) {
    'literature' => isChinese ? '文献' : 'Literature',
    'research' => isChinese ? '研究' : 'Research',
    'system' => isChinese ? '系统洞察' : 'System Insight',
    _ => 'PickLogic Pro',
  };
}
