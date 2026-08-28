import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';
import 'package:picklogic_desktop/src/pdf_edit_exporter.dart';
import 'package:picklogic_desktop/src/pdf_content_object_service.dart';
import 'package:picklogic_desktop/src/pro_pdf_editor.dart';
import 'package:picklogic_desktop/src/pro_pdf_reader.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

void main() {
  testWidgets(
    'page editor supports rotate, duplicate, undo, and save preview',
    (tester) async {
      PdfEditPlan? accepted;
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _localizedApp(
          home: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  accepted = await showPdfPageEditor(
                    context: context,
                    pageCount: 3,
                    annotationCount: 1,
                  );
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pdf-page-editor-dialog')), findsOneWidget);
      expect(find.text('Embed 1 annotations'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf-edit-rotate-right-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pdf-edit-duplicate-0')));
      await tester.pump();
      expect(find.text('4 pages'), findsOneWidget);
      expect(find.text('2 rotated'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf-edit-undo-action')));
      await tester.pump();
      expect(find.text('3 pages'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pdf-edit-redo-action')));
      await tester.pump();
      expect(find.text('4 pages'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pdf-edit-save-copy-action')));
      await tester.pumpAndSettle();
      expect(accepted, isNotNull);
      expect(accepted!.pages, hasLength(4));
      expect(accepted!.rotatedPageCount, 2);
      expect(accepted!.duplicatedPageCount, 1);
    },
  );

  test(
    'exporter preserves source and writes rearranged annotated PDF copy',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'picklogic-pdf-edit-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = File(
        '${directory.path}${Platform.pathSeparator}source.pdf',
      );
      final destination = File(
        '${directory.path}${Platform.pathSeparator}edited.pdf',
      );
      final sourceBytes = buildSyntheticLiteraturePdf();
      await source.writeAsBytes(sourceBytes, flush: true);
      final plan = PdfEditPlan.identity(
        2,
      ).move(1, 0).rotate(0, clockwise: true).duplicate(1);
      final now = DateTime.utc(2026, 8, 27);
      final result = await const PdfEditedCopyExporter().export(
        sourcePath: source.path,
        destinationPath: destination.path,
        plan: plan,
        annotations: [
          LiteratureAnnotation(
            id: 'synthetic-annotation',
            literatureId: 'synthetic-literature',
            pageNumber: 1,
            kind: LiteratureAnnotationKind.highlight,
            selectedText: 'PickLogic synthetic literature sample',
            note: 'Synthetic export check',
            colorName: 'yellow',
            createdAt: now,
            updatedAt: now,
            boxes: [
              LiteratureAnnotationBox(
                pageNumber: 1,
                left: 70,
                top: 742,
                right: 390,
                bottom: 710,
              ),
            ],
          ),
        ],
      );

      expect(await source.readAsBytes(), sourceBytes);
      expect(await destination.exists(), isTrue);
      expect(result.pageCount, 3);
      expect(result.embeddedAnnotationCount, 1);
      expect(result.sizeBytes, greaterThan(0));

      final edited = await PdfDocument.openFile(destination.path);
      addTearDown(edited.dispose);
      expect(edited.pages, hasLength(3));
      expect(edited.pages.first.rotation, PdfPageRotation.clockwise90);
      expect(
        (await edited.pages.first.loadText())?.fullText,
        contains('Insight evidence page'),
      );
      expect(
        (await edited.pages[1].loadText())?.fullText,
        contains('PickLogic synthetic literature sample'),
      );
      final annotationCount = await edited.useNativeDocumentHandle((handle) {
        final api = pdfium_bindings.getPdfium();
        final document = pdfium_bindings.FPDF_DOCUMENT.fromAddress(handle);
        var count = 0;
        for (var index = 0; index < edited.pages.length; index++) {
          final page = api.FPDF_LoadPage(document, index);
          if (page == ffi.nullptr) continue;
          count += api.FPDFPage_GetAnnotCount(page);
          api.FPDF_ClosePage(page);
        }
        return count;
      });
      expect(annotationCount, greaterThanOrEqualTo(1));
    },
  );

  testWidgets('exporter replaces PDF text and inserts a bounded image object', (
    tester,
  ) async {
    await pdfrxFlutterInitialize();
    final directory = await Directory.systemTemp.createTemp(
      'picklogic-pdf-content-edit-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.pdf');
    final destination = File(
      '${directory.path}${Platform.pathSeparator}edited.pdf',
    );
    final image = File(
      '${directory.path}${Platform.pathSeparator}replacement.png',
    );
    final sourceBytes = buildSyntheticLiteraturePdf();
    await source.writeAsBytes(sourceBytes, flush: true);
    await image.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR42mP8z8Dwn4GBgYGJAQoAHgQCAZg6pXQAAAAASUVORK5CYII=',
      ),
      flush: true,
    );

    final sourceDocument = await PdfDocument.openFile(source.path);
    final service = const PdfContentObjectService();
    final objects = await service.inspectPage(sourceDocument, 1);
    await sourceDocument.dispose();
    final textObject = objects.firstWhere(
      (object) =>
          object.kind == PdfContentObjectKind.text &&
          object.text.contains('PickLogic'),
    );
    final contentPlan = PdfContentEditPlan(
      edits: [
        PdfContentObjectEdit.fromDescriptor(
          textObject,
        ).copyWith(replacementText: 'PickLogic object editing works'),
        PdfContentObjectEdit.addImage(
          id: 'new:1:image',
          pageNumber: 1,
          bounds: const PdfContentBounds(
            left: 72,
            bottom: 520,
            right: 172,
            top: 620,
          ),
          imagePath: image.path,
        ),
      ],
    );

    final result = await const PdfEditedCopyExporter().export(
      sourcePath: source.path,
      destinationPath: destination.path,
      plan: PdfEditPlan.identity(2),
      contentEdits: contentPlan,
    );

    expect(await source.readAsBytes(), sourceBytes);
    expect(result.editedObjectCount, 2);
    final edited = await PdfDocument.openFile(destination.path);
    addTearDown(edited.dispose);
    expect(
      (await edited.pages.first.loadText())?.fullText,
      contains('PickLogic object editing works'),
    );
    final editedObjects = await service.inspectPage(edited, 1);
    expect(
      editedObjects.where(
        (object) => object.kind == PdfContentObjectKind.image,
      ),
      isNotEmpty,
    );
  });

  test('exporter refuses to overwrite an existing PDF', () async {
    final directory = await Directory.systemTemp.createTemp(
      'picklogic-pdf-overwrite-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}${Platform.pathSeparator}source.pdf');
    final destination = File(
      '${directory.path}${Platform.pathSeparator}existing.pdf',
    );
    await source.writeAsBytes(buildSyntheticLiteraturePdf());
    await destination.writeAsString('existing synthetic sentinel');

    expect(
      () => const PdfEditedCopyExporter().export(
        sourcePath: source.path,
        destinationPath: destination.path,
        plan: PdfEditPlan.identity(2).rotate(0, clockwise: true),
      ),
      throwsStateError,
    );
    expect(await destination.readAsString(), 'existing synthetic sentinel');
  });
}

Widget _localizedApp({required Widget home}) => MaterialApp(
  locale: const Locale('en'),
  theme: PickLogicTokens.lightTheme(),
  supportedLocales: PickLogicLocalizations.supportedLocales,
  localizationsDelegates: const [
    PickLogicLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: home),
);
