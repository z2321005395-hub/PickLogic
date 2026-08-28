import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart'
    hide TranslationProvider;
import 'package:picklogic_desktop/src/pro_pdf_content_editor.dart';
import 'package:picklogic_desktop/src/pro_pdf_reader.dart';
import 'package:picklogic_desktop/src/pro_translation.dart';
import 'package:picklogic_desktop/src/pro_workspace.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

void main() {
  test('local PDF reader disables progressive loading on Windows files', () {
    final documentRef = buildProLocalPdfDocumentRef(r'X:\synthetic\reader.pdf');

    expect(documentRef.file, r'X:\synthetic\reader.pdf');
    expect(documentRef.useProgressiveLoading, isFalse);
  });

  test('PDF selection normalization repairs cross-line extracted text', () {
    expect(
      normalizePdfSelectionText('micro-\nstructure  evolves\r\nrapidly'),
      'microstructure evolves rapidly',
    );
  });

  testWidgets(
    'Literature uses a bounded list-reader layout with opt-in details',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = _MemoryLiteratureStore([_entry()]);

      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('zh'),
          home: ProWorkspaceRoute(
            section: 'literature',
            libraryStore: store,
            literaturePdfReaderBuilder: (_, entry, onPositionChanged) =>
                ColoredBox(
                  key: const Key('reader-area-test-double'),
                  color: Colors.transparent,
                  child: Center(child: Text('第 ${entry.currentPage} 页阅读区')),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('literature-library-list')), findsOneWidget);
      expect(
        find.byKey(const Key('literature-collection-sidebar')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reader-area-test-double')), findsOneWidget);
      expect(find.byKey(const Key('literature-metadata-dialog')), findsNothing);
      expect(
        find.byKey(const Key('literature-rename-preview-dialog')),
        findsNothing,
      );
      expect(find.text('10.5555/picklogic.synthetic'), findsNothing);

      await tester.tap(
        find.byKey(const Key('literature-focus-reading-action')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('literature-library-list')), findsNothing);
      expect(
        find.byKey(const Key('literature-collection-sidebar')),
        findsNothing,
      );
      expect(find.byKey(const Key('reader-area-test-double')), findsOneWidget);
      expect(find.text('退出专注'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('literature-focus-reading-action')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('literature-library-list')), findsOneWidget);
      expect(
        find.byKey(const Key('literature-collection-sidebar')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('literature-metadata-action')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('literature-metadata-dialog')),
        findsOneWidget,
      );
      expect(find.text('10.5555/picklogic.synthetic'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('literature-rename-preview-action')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('literature-rename-preview-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('仅预览'), findsOneWidget);
    },
  );

  testWidgets('Literature imports multiple PDFs and saves manual metadata', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryLiteratureStore([]);
    final source = _MemoryPdfSource(
      '%PDF-1.7 /Title (Synthetic batch item) %%EOF'.codeUnits,
    );

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: ProWorkspaceRoute(
          section: 'literature',
          libraryStore: store,
          pdfMultiPicker: () async => <String>[
            r'X:\synthetic\first.pdf',
            r'X:\synthetic\second.pdf',
            r'X:\synthetic\notes.txt',
          ],
          pdfSourceBuilder: (_) => source,
          literaturePdfReaderBuilder: (_, _, _) =>
              const SizedBox(key: Key('batch-reader-test-double')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('literature-add-action')));
    await tester.pumpAndSettle();

    expect(store.entries, hasLength(2));
    expect(find.textContaining('2 item(s) added'), findsOneWidget);
    await tester.tap(find.byKey(const Key('literature-metadata-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('literature-edit-metadata-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('literature-title-field')),
      'Corrected synthetic title',
    );
    await tester.enterText(
      find.byKey(const Key('literature-authors-field')),
      'Ada Example; Lin Test',
    );
    await tester.enterText(
      find.byKey(const Key('literature-journal-field')),
      'Synthetic Journal',
    );
    await tester.enterText(
      find.byKey(const Key('literature-year-field')),
      '2026',
    );
    await tester.tap(find.byKey(const Key('literature-save-metadata-action')));
    await tester.pumpAndSettle();

    expect(store.entries.first.record.title, 'Corrected synthetic title');
    expect(store.entries.first.record.authors, ['Ada Example', 'Lin Test']);
    expect(store.entries.first.record.journal, 'Synthetic Journal');
    expect(store.entries.first.record.metadataSource, 'manual local edit');
    expect(find.textContaining('Metadata saved'), findsOneWidget);
  });

  testWidgets('Literature search, tags, and portable citation export work', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tagged = _entry();
    final store = _MemoryLiteratureStore([
      LiteratureLibraryEntry(
        record: LiteratureRecord(
          id: tagged.record.id,
          localFileId: tagged.record.localFileId,
          doi: tagged.record.doi,
          title: tagged.record.title,
          authors: tagged.record.authors,
          year: tagged.record.year,
          tags: const ['methods'],
          metadataConfidence: tagged.record.metadataConfidence,
        ),
        localPath: tagged.localPath,
        fileName: tagged.fileName,
        addedAt: tagged.addedAt,
      ),
    ]);

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: ProWorkspaceRoute(
          section: 'literature',
          libraryStore: store,
          annotationStore: InMemoryLiteratureAnnotationStore(),
          literaturePdfReaderBuilder: (_, _, _) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('methods'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('literature-library-search')),
      'no matching title',
    );
    await tester.pump();
    expect(find.text('No matching literature.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('literature-library-search')),
      'synthetic',
    );
    await tester.pump();
    expect(
      find.byKey(const Key('literature-entry-lit-synthetic')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('literature-citation-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('literature-citation-dialog')), findsOneWidget);
    await tester.tap(find.text('BibTeX'));
    await tester.pump();
    expect(find.textContaining('@article{'), findsOneWidget);
    expect(find.textContaining('10.5555/picklogic.synthetic'), findsOneWidget);
  });

  testWidgets('BibTeX import creates a reference that can attach a PDF later', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const bibText = r'''
@article{synthetic2026,
  title = {Imported reference workflow},
  author = {Example, Ada},
  year = {2026},
  journal = {Synthetic Research}
}
''';
    final store = _MemoryLiteratureStore([]);

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: ProWorkspaceRoute(
          section: 'literature',
          libraryStore: store,
          referencePicker: () async => [r'X:\synthetic\library.bib'],
          referenceLoader: (_) async => bibText,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.byKey(const Key('literature-import-reference-action')),
    );
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 50 && store.entries.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(store.entries, hasLength(1));
    expect(store.entries.single.record.title, 'Imported reference workflow');
    expect(store.entries.single.hasLocalPdf, isFalse);
    expect(
      find.byKey(const Key('literature-attach-pdf-action')),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 reference record(s) imported'),
      findsOneWidget,
    );
  });

  testWidgets('collections, bulk trash, and restore preserve source PDFs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entry = _entry();
    final store = _MemoryLiteratureStore([entry]);
    final collection = LiteratureCollection(
      id: 'collection-project-a',
      name: 'Project A',
      createdAt: DateTime.utc(2026, 8, 27),
    );
    final collectionStore = InMemoryLiteratureCollectionStore([collection]);

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: ProWorkspaceRoute(
          section: 'literature',
          libraryStore: store,
          collectionStore: collectionStore,
          annotationStore: InMemoryLiteratureAnnotationStore(),
          literaturePdfReaderBuilder: (_, _, _) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('literature-check-lit-synthetic')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('literature-bulk-collection-action')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project A').last);
    await tester.pumpAndSettle();
    expect(store.entries.single.collectionIds, [collection.id]);

    await tester.tap(find.byKey(const Key('literature-bulk-trash-action')));
    await tester.pumpAndSettle();
    expect(store.entries.single.isTrashed, isTrue);
    expect(store.entries.single.localPath, entry.localPath);

    await tester.tap(find.byKey(const Key('literature-scope-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('literature-check-lit-synthetic')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('literature-bulk-restore-action')));
    await tester.pumpAndSettle();
    expect(store.entries.single.isTrashed, isFalse);
    expect(store.entries.single.localPath, entry.localPath);
  });

  testWidgets('persisted page translation restores bilingual source and text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final translationStore = InMemoryLiteratureTranslationStore();
    await translationStore.upsertPage(
      LiteraturePageTranslation(
        literatureId: 'lit-synthetic',
        pageNumber: 1,
        targetLanguage: 'English',
        sourceText: '本地原文',
        translatedText: 'Local translation',
        providerLabel: 'Synthetic translator',
        updatedAt: DateTime.utc(2026, 8, 27),
      ),
    );

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: ProLocalPdfReader(
            path: r'X:\synthetic\reader.pdf',
            fileName: 'reader.pdf',
            initialPageNumber: 1,
            onPositionChanged: (_, _) {},
            viewerBuilder: (_) => const SizedBox.expand(),
            literatureId: 'lit-synthetic',
            translationStore: translationStore,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('pdf-bilingual-toggle-action')));
    await tester.pump();

    expect(find.byKey(const Key('pdf-bilingual-panel')), findsOneWidget);
    expect(find.text('本地原文'), findsOneWidget);
    expect(find.text('Local translation'), findsOneWidget);
    expect(
      find.byKey(const Key('pdf-retranslate-page-action')),
      findsOneWidget,
    );
  });

  testWidgets(
    'PDF selection translates automatically into the persistent right sidebar',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selection = ValueNotifier<String>('');
      addTearDown(selection.dispose);
      final provider = _ImmediateTranslationProvider();
      final engineChanges = <TranslationEngineChoice>[];

      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('zh'),
          home: Scaffold(
            body: ProLocalPdfReader(
              path: r'X:\synthetic\reader.pdf',
              fileName: 'reader.pdf',
              initialPageNumber: 1,
              onPositionChanged: (_, _) {},
              viewerBuilder: (_) => const SizedBox.expand(),
              translationProvider: provider,
              translationEngine: TranslationEngineChoice.instant,
              onTranslationEngineChanged: (choice) async {
                engineChanges.add(choice);
              },
              selectionTextForTesting: selection,
            ),
          ),
        ),
      );
      await tester.pump();

      selection.value = 'Selected scientific sentence.';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(
        find.byKey(const Key('pdf-selection-translation-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pdf-translation-result-dialog')),
        findsNothing,
      );
      expect(find.text('Selected scientific sentence.'), findsOneWidget);
      expect(find.text('译文：Selected scientific sentence.'), findsOneWidget);
      expect(
        find.byKey(const Key('pdf-selection-translation-alternative-0')),
        findsOneWidget,
      );
      expect(find.text('候选：Selected scientific sentence.'), findsOneWidget);
      expect(provider.sources, ['Selected scientific sentence.']);
      expect(
        find.byKey(const Key('pdf-translation-engine-selector')),
        findsOneWidget,
      );
      expect(find.text('MyMemory · 单引擎'), findsOneWidget);
      expect(
        find.byKey(const Key('pdf-configure-selection-translation-action')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('pdf-translation-engine-selector')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('AI 模型 · 高级').last);
      await tester.pump(const Duration(milliseconds: 250));
      expect(engineChanges, [TranslationEngineChoice.openAiCompatible]);

      selection.value = 'A second term.';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(find.text('A second term.'), findsOneWidget);
      expect(find.text('译文：A second term.'), findsOneWidget);
      expect(find.text('译文：Selected scientific sentence.'), findsNothing);
      expect(provider.sources, [
        'Selected scientific sentence.',
        'Selected scientific sentence.',
        'A second term.',
      ]);
      expect(provider.targets, [
        'Simplified Chinese',
        'Simplified Chinese',
        'Simplified Chinese',
      ]);

      selection.value = '材料科学';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.text('译文：材料科学'), findsOneWidget);
      expect(provider.targets.last, 'English');
    },
  );

  testWidgets(
    'aggregate selection shows the fast result while slower sources continue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selection = ValueNotifier<String>('');
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('zh'),
          home: Scaffold(
            body: ProLocalPdfReader(
              path: r'X:\synthetic\reader.pdf',
              fileName: 'reader.pdf',
              initialPageNumber: 1,
              onPositionChanged: (_, _) {},
              viewerBuilder: (_) => const SizedBox.expand(),
              translationProvider: _ProgressiveTranslationProvider(),
              translationEngine: TranslationEngineChoice.aggregate,
              selectionTextForTesting: selection,
            ),
          ),
        ),
      );
      await tester.pump();

      selection.value = 'grain boundary';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('晶界'), findsOneWidget);
      expect(find.text('首条译文已显示，正在并行比对其他可用来源…'), findsOneWidget);
      expect(
        find.byKey(const Key('pdf-selection-translation-loading')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('晶粒边界'), findsOneWidget);
      expect(
        find.byKey(const Key('pdf-selection-translation-alternative-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pdf-selection-translation-loading')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'selection source correction retranslates and locked results survive lookup',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selection = ValueNotifier<String>('');
      addTearDown(selection.dispose);
      final provider = _ImmediateTranslationProvider();

      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('zh'),
          home: Scaffold(
            body: ProLocalPdfReader(
              path: r'X:\synthetic\reader.pdf',
              fileName: 'reader.pdf',
              initialPageNumber: 1,
              onPositionChanged: (_, _) {},
              viewerBuilder: (_) => const SizedBox.expand(),
              translationProvider: provider,
              translationEngine: TranslationEngineChoice.instant,
              selectionTextForTesting: selection,
            ),
          ),
        ),
      );
      await tester.pump();

      selection.value = 'micro-\nstructure';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(provider.sources.last, 'microstructure');

      await tester.tap(
        find.byKey(const Key('pdf-edit-selection-source-action')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('pdf-selection-translation-source')),
        'grain\nboundary',
      );
      await tester.pump(const Duration(milliseconds: 430));
      await tester.pump();
      expect(provider.sources.last, 'grain boundary');
      expect(find.text('译文：grain boundary'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('pdf-lock-selection-translation-action')),
      );
      await tester.tap(
        find.byKey(const Key('pdf-lock-selection-translation-action')),
      );
      await tester.pump();

      selection.value = 'second lookup';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();

      expect(find.text('译文：second lookup'), findsOneWidget);
      expect(
        find.byKey(const Key('pdf-locked-selection-translation-0')),
        findsOneWidget,
      );
      expect(find.text('译文：grain boundary'), findsOneWidget);
    },
  );

  testWidgets('PDF annotation panel exposes page-linked local notes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final createdAt = DateTime.utc(2026, 8, 27);
    var deletedId = '';

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: ProLocalPdfReader(
            path: r'X:\synthetic\reader.pdf',
            fileName: 'reader.pdf',
            initialPageNumber: 1,
            onPositionChanged: (_, _) {},
            viewerBuilder: (_) => const SizedBox.expand(),
            literatureId: 'lit-synthetic',
            annotations: [
              LiteratureAnnotation(
                id: 'annotation-1',
                literatureId: 'lit-synthetic',
                pageNumber: 3,
                kind: LiteratureAnnotationKind.highlight,
                selectedText: 'Evidence-linked annotation',
                note: 'Use in methods.',
                colorName: 'yellow',
                createdAt: createdAt,
                updatedAt: createdAt,
              ),
            ],
            onSaveAnnotation: (_) async {},
            onDeleteAnnotation: (id) async => deletedId = id,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('pdf-edit-copy-action')), findsOneWidget);
    expect(find.byTooltip('Edit text and images'), findsOneWidget);
    expect(find.byKey(const Key('pdf-edit-menu-action')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pdf-toggle-annotations-action')));
    await tester.pump();
    expect(find.byKey(const Key('pdf-annotation-panel')), findsOneWidget);
    expect(find.text('Evidence-linked annotation'), findsOneWidget);
    expect(find.textContaining('Page 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete annotation'));
    await tester.pump();
    expect(deletedId, 'annotation-1');
  });

  testWidgets(
    'all three Pro workspaces switch between pure Chinese and English',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Future<void> pump(String section, Locale locale) async {
        await tester.pumpWidget(
          _localizedApp(
            locale: locale,
            home: ProWorkspaceRoute(
              section: section,
              libraryStore: section == 'literature'
                  ? _MemoryLiteratureStore([])
                  : null,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump('literature', const Locale('zh'));
      expect(find.text('文献'), findsOneWidget);
      expect(find.text('文献库'), findsOneWidget);
      expect(find.text('添加文献'), findsOneWidget);
      expect(find.text('Literature Library'), findsNothing);

      await pump('literature', const Locale('en'));
      expect(find.text('Literature'), findsOneWidget);
      expect(find.text('Literature Library'), findsOneWidget);
      expect(find.text('Add literature'), findsOneWidget);
      expect(find.text('文献库'), findsNothing);

      await pump('research', const Locale('zh'));
      expect(find.text('研究'), findsOneWidget);
      expect(find.text('研究工作区'), findsOneWidget);
      expect(find.text('原始数据'), findsOneWidget);
      expect(find.text('Research workspace'), findsNothing);
      expect(find.text('Raw data'), findsNothing);

      await pump('research', const Locale('en'));
      expect(find.text('Research'), findsOneWidget);
      expect(find.text('Research workspace'), findsOneWidget);
      expect(find.text('Raw data'), findsOneWidget);
      expect(find.text('研究工作区'), findsNothing);

      await pump('system', const Locale('zh'));
      expect(find.text('系统洞察'), findsOneWidget);
      expect(find.text('系统洞察 · 只读'), findsOneWidget);
      expect(find.text('合成系统服务'), findsOneWidget);
      expect(find.text('System Insight · Read-only'), findsNothing);

      await pump('system', const Locale('en'));
      expect(find.text('System Insight'), findsOneWidget);
      expect(find.text('System Insight · Read-only'), findsOneWidget);
      expect(find.text('Synthetic system service'), findsOneWidget);
      expect(find.text('系统洞察 · 只读'), findsNothing);
    },
  );

  testWidgets('PDF picker failure gives an actionable recovery message', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('zh'),
        home: ProWorkspaceRoute(
          section: 'literature',
          libraryStore: _MemoryLiteratureStore([]),
          pdfMultiPicker: () async =>
              throw PlatformException(code: 'dialog_failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('literature-add-action')));
    await tester.pumpAndSettle();

    expect(find.textContaining('若文件在云盘中，请先下载到本机后重试'), findsOneWidget);
  });

  testWidgets('System Insight details remain hidden until explicitly opened', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: const ProWorkspaceRoute(section: 'system'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('system-insight-dialog-service')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('system-insight-action-service')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('system-insight-dialog-service')),
      findsOneWidget,
    );
    expect(find.text('Category'), findsOneWidget);
    expect(find.textContaining('leave it unchanged'), findsOneWidget);
    expect(find.textContaining('删除'), findsNothing);
  });

  testWidgets('PDF controls stay compact, themed, and locale-pure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget build(Locale locale) => _localizedApp(
      locale: locale,
      home: Scaffold(
        body: ProLocalPdfReader(
          path: r'X:\synthetic\reader.pdf',
          fileName: 'reader.pdf',
          initialPageNumber: 1,
          onPositionChanged: (_, _) {},
          viewerBuilder: (_) =>
              const SizedBox.expand(key: Key('pdf-viewer-test-double')),
        ),
      ),
    );

    await tester.pumpWidget(build(const Locale('zh')));
    await tester.pump();
    expect(find.text('本地渲染'), findsOneWidget);
    expect(find.text('搜索 PDF 文本'), findsOneWidget);
    expect(find.text('跳至页'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('pdf-edit-copy-action')),
        matching: find.text('编辑 PDF'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pdf-translation-menu')), findsOneWidget);
    expect(find.byKey(const Key('pdf-thumbnail-pane')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pdf-toggle-thumbnails-action')));
    await tester.pump();
    expect(find.byKey(const Key('pdf-thumbnail-pane')), findsNothing);
    await tester.tap(find.byKey(const Key('pdf-toggle-thumbnails-action')));
    await tester.pump();
    expect(find.byKey(const Key('pdf-thumbnail-pane')), findsOneWidget);
    expect(find.text('Local rendering'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(build(const Locale('en')));
    await tester.pump();
    expect(find.text('Local rendering'), findsOneWidget);
    expect(find.text('Search PDF text'), findsOneWidget);
    expect(find.text('Go to page'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('pdf-edit-copy-action')),
        matching: find.text('Edit PDF'),
      ),
      findsOneWidget,
    );
    expect(find.text('本地渲染'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF content editing stays on the current reader surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PdfContentEditorController();
    var editorVisible = true;
    var currentPage = 2;
    var currentZoom = 1.25;

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                const Text(
                  'Literature reader',
                  key: Key('reader-shell-test-double'),
                ),
                Expanded(
                  child: editorVisible
                      ? PdfContentEditorDialog.testing(
                          controller: controller,
                          embedded: true,
                          readerSurface: true,
                          initialPageNumber: currentPage,
                          initialZoom: 1.25,
                          imagePicker: () async => null,
                          pagePreviewBuilder: (_, _) =>
                              const ColoredBox(color: Colors.white),
                          pageSizesForTesting: const [
                            Size(612, 792),
                            Size(612, 792),
                          ],
                          objectsForTesting: const {1: [], 2: []},
                          onPageChanged: (page) => currentPage = page,
                          onZoomChanged: (zoom) => currentZoom = zoom,
                          onClosed: (_) =>
                              setState(() => editorVisible = false),
                        )
                      : const SizedBox.expand(
                          key: Key('reader-page-test-double'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-shell-test-double')), findsOneWidget);
    expect(
      find.byKey(const Key('pdf-content-editor-reader-surface')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pdf-content-editor-dialog')), findsNothing);
    expect(find.text('Editing on page'), findsOneWidget);
    expect(find.text('Edit text and images'), findsNothing);
    expect(
      find.byKey(const Key('pdf-content-add-text-action')),
      findsOneWidget,
    );

    controller.goToPage(1);
    await tester.pumpAndSettle();
    expect(currentPage, 1);
    controller.zoomIn();
    await tester.pump();
    expect(currentZoom, 1.5625);

    await controller.requestClose();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('pdf-content-editor-reader-surface')),
      findsNothing,
    );
    expect(find.byKey(const Key('reader-page-test-double')), findsOneWidget);
    expect(find.byKey(const Key('reader-shell-test-double')), findsOneWidget);
  });
}

Widget _localizedApp({required Locale locale, required Widget home}) =>
    MaterialApp(
      locale: locale,
      theme: PickLogicTokens.lightTheme(),
      supportedLocales: PickLogicLocalizations.supportedLocales,
      localizationsDelegates: const [
        PickLogicLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

LiteratureLibraryEntry _entry() => LiteratureLibraryEntry(
  record: const LiteratureRecord(
    id: 'lit-synthetic',
    localFileId: 'local-lit-synthetic',
    doi: '10.5555/picklogic.synthetic',
    title: '合成文献示例',
    authors: ['示例作者'],
    year: 2026,
    readingProgress: 0.35,
    metadataConfidence: 0.9,
  ),
  localPath: r'X:\synthetic\paper.pdf',
  fileName: 'paper.pdf',
  addedAt: DateTime.utc(2026, 8, 13),
  currentPage: 7,
  totalPages: 20,
);

final class _MemoryLiteratureStore implements LiteratureLibraryStore {
  _MemoryLiteratureStore(List<LiteratureLibraryEntry> entries)
    : entries = List<LiteratureLibraryEntry>.of(entries);

  List<LiteratureLibraryEntry> entries;

  @override
  Future<List<LiteratureLibraryEntry>> load() async =>
      List<LiteratureLibraryEntry>.unmodifiable(entries);

  @override
  Future<void> save(List<LiteratureLibraryEntry> entries) async {
    this.entries = List<LiteratureLibraryEntry>.of(entries);
  }
}

final class _MemoryPdfSource implements PdfByteSource {
  _MemoryPdfSource(this.bytes);

  final List<int> bytes;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<List<int>> readRange({
    required int offset,
    required int length,
  }) async {
    if (offset >= bytes.length) return const <int>[];
    return bytes.sublist(offset, (offset + length).clamp(0, bytes.length));
  }
}

final class _ImmediateTranslationProvider implements TranslationProvider {
  final List<String> sources = <String>[];
  final List<String> targets = <String>[];

  @override
  TranslationProviderKind get kind => TranslationProviderKind.openAiCompatible;

  @override
  String get label => 'Synthetic translator';

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async {
    sources.add(selectedText);
    targets.add(targetLanguage);
    return SelectedTextTranslation(
      sourceText: selectedText,
      translatedText: '译文：$selectedText',
      targetLanguage: targetLanguage,
      providerLabel: label,
      alternatives: [
        TranslationAlternative(
          label: 'Synthetic alternative',
          translatedText: '候选：$selectedText',
        ),
      ],
    );
  }
}

final class _ProgressiveTranslationProvider
    implements TranslationProvider, ProgressiveTranslationProvider {
  @override
  TranslationProviderKind get kind => TranslationProviderKind.publicAnonymous;

  @override
  String get label => 'Synthetic aggregate';

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async => SelectedTextTranslation(
    sourceText: selectedText,
    translatedText: '晶界',
    targetLanguage: targetLanguage,
    providerLabel: 'Fast source',
  );

  @override
  Stream<SelectedTextTranslation> translateSelectedTextProgressively(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async* {
    yield SelectedTextTranslation(
      sourceText: selectedText,
      translatedText: '晶界',
      targetLanguage: targetLanguage,
      providerLabel: 'Fast source',
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    yield SelectedTextTranslation(
      sourceText: selectedText,
      translatedText: '晶粒边界',
      targetLanguage: targetLanguage,
      providerLabel: 'Slow source',
    );
  }
}
