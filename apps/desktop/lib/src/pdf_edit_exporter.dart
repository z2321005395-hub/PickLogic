import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';

import 'pdf_content_object_service.dart';

final class PdfEditExportResult {
  const PdfEditExportResult({
    required this.destinationPath,
    required this.pageCount,
    required this.embeddedAnnotationCount,
    required this.editedObjectCount,
    required this.sizeBytes,
  });

  final String destinationPath;
  final int pageCount;
  final int embeddedAnnotationCount;
  final int editedObjectCount;
  final int sizeBytes;
}

/// Exports an edited copy without overwriting the source or an existing target.
final class PdfEditedCopyExporter {
  const PdfEditedCopyExporter({this.maximumSourceBytes = 512 * 1024 * 1024});

  final int maximumSourceBytes;

  Future<PdfEditExportResult> export({
    required String sourcePath,
    required String destinationPath,
    required PdfEditPlan plan,
    PdfContentEditPlan? contentEdits,
    List<LiteratureAnnotation> annotations = const <LiteratureAnnotation>[],
  }) async {
    final source = File(sourcePath).absolute;
    final destination = File(destinationPath).absolute;
    if (!sourcePath.toLowerCase().endsWith('.pdf') ||
        !destinationPath.toLowerCase().endsWith('.pdf')) {
      throw ArgumentError('Source and destination must be PDF files.');
    }
    if (!await source.exists()) {
      throw StateError('The source PDF no longer exists.');
    }
    final sourceBytes = await source.length();
    if (sourceBytes > maximumSourceBytes) {
      throw StateError('The source PDF exceeds the bounded editing limit.');
    }
    if (!await destination.parent.exists()) {
      throw StateError('The selected destination folder no longer exists.');
    }
    if (await destination.exists()) {
      throw StateError('PickLogic will not overwrite an existing PDF.');
    }
    final sourceCanonical = await source.resolveSymbolicLinks();
    final destinationParentCanonical = await destination.parent
        .resolveSymbolicLinks();
    final destinationCanonical =
        '$destinationParentCanonical${Platform.pathSeparator}${_fileName(destination.path)}';
    if (_samePath(sourceCanonical, destinationCanonical)) {
      throw StateError('The edited copy must use a new file name.');
    }

    PdfDocument? sourceDocument;
    PdfDocument? outputDocument;
    File? temporary;
    try {
      sourceDocument = await PdfDocument.openFile(source.path);
      if (sourceDocument.pages.length != plan.originalPageCount) {
        throw StateError('The source PDF page count changed; reopen it first.');
      }
      final permissions = sourceDocument.permissions;
      if (permissions != null && !permissions.allowsCopying) {
        throw StateError('This PDF does not permit copying into a new file.');
      }
      if (plan.changed &&
          permissions != null &&
          !permissions.allowsDocumentAssembly) {
        throw StateError('This PDF does not permit page assembly changes.');
      }
      if (annotations.isNotEmpty &&
          permissions != null &&
          !permissions.allowsModifyAnnotations) {
        throw StateError('This PDF does not permit annotation changes.');
      }

      final contentPlan = contentEdits ?? PdfContentEditPlan.empty();
      if (contentPlan.changed &&
          permissions != null &&
          (permissions.permissions & 0x0008) == 0) {
        throw StateError('This PDF does not permit content changes.');
      }
      await const PdfContentObjectService().applyToDocument(
        sourceDocument,
        contentPlan,
      );

      final embeddedAnnotationCount = annotations.isEmpty
          ? 0
          : await _embedAnnotations(sourceDocument, annotations);
      outputDocument = await PdfDocument.createNew(
        sourceName: destination.path,
      );
      outputDocument.pages = [
        for (final pageEdit in plan.pages)
          sourceDocument.pages[pageEdit.sourcePageNumber - 1].rotatedBy(
            PdfPageRotation.values[pageEdit.clockwiseQuarterTurns],
          ),
      ];
      final encoded = await outputDocument.encodePdf();
      if (encoded.isEmpty) {
        throw StateError('PDFium returned an empty edited document.');
      }
      if (await destination.exists()) {
        throw StateError(
          'The selected destination now exists; nothing was overwritten.',
        );
      }
      temporary = File(
        '${destination.parent.path}${Platform.pathSeparator}.${_fileName(destination.path)}.picklogic-${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await temporary.create(exclusive: true);
      final sink = await temporary.open(mode: FileMode.writeOnly);
      try {
        await sink.writeFrom(encoded);
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (await destination.exists()) {
        throw StateError(
          'The selected destination now exists; nothing was overwritten.',
        );
      }
      await temporary.rename(destination.path);
      temporary = null;
      return PdfEditExportResult(
        destinationPath: destination.path,
        pageCount: plan.pages.length,
        embeddedAnnotationCount: embeddedAnnotationCount,
        editedObjectCount: contentPlan.edits
            .where((edit) => edit.changed)
            .length,
        sizeBytes: encoded.length,
      );
    } finally {
      await outputDocument?.dispose();
      await sourceDocument?.dispose();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<int> _embedAnnotations(
    PdfDocument document,
    List<LiteratureAnnotation> annotations,
  ) async {
    final api = pdfium_bindings.getPdfium();
    return document.useNativeDocumentHandle((nativeHandle) {
      final nativeDocument = pdfium_bindings.FPDF_DOCUMENT.fromAddress(
        nativeHandle,
      );
      var embedded = 0;
      for (final annotation in annotations) {
        if (annotation.pageNumber > document.pages.length) {
          throw StateError('An annotation points outside the source PDF.');
        }
        final page = api.FPDF_LoadPage(
          nativeDocument,
          annotation.pageNumber - 1,
        );
        if (page == ffi.nullptr) {
          throw StateError('PDFium could not load an annotated page.');
        }
        try {
          _writeAnnotation(
            api,
            page,
            annotation,
            document.pages[annotation.pageNumber - 1],
          );
          embedded++;
        } finally {
          api.FPDF_ClosePage(page);
        }
      }
      return embedded;
    });
  }

  void _writeAnnotation(
    pdfium_bindings.PDFium api,
    pdfium_bindings.FPDF_PAGE page,
    LiteratureAnnotation annotation,
    PdfPage sourcePage,
  ) {
    final boxes = annotation.boxes
        .where((box) => box.pageNumber == annotation.pageNumber)
        .toList(growable: false);
    final hasMarkupGeometry =
        boxes.isNotEmpty && annotation.kind != LiteratureAnnotationKind.note;
    final subtype = hasMarkupGeometry
        ? switch (annotation.kind) {
            LiteratureAnnotationKind.highlight =>
              pdfium_bindings.FPDF_ANNOT_HIGHLIGHT,
            LiteratureAnnotationKind.underline =>
              pdfium_bindings.FPDF_ANNOT_UNDERLINE,
            LiteratureAnnotationKind.strikethrough =>
              pdfium_bindings.FPDF_ANNOT_STRIKEOUT,
            LiteratureAnnotationKind.note => pdfium_bindings.FPDF_ANNOT_TEXT,
          }
        : pdfium_bindings.FPDF_ANNOT_TEXT;
    final nativeAnnotation = api.FPDFPage_CreateAnnot(page, subtype);
    if (nativeAnnotation == ffi.nullptr) {
      throw StateError('PDFium could not create an annotation.');
    }
    try {
      final color = _annotationColor(annotation.colorName);
      if (api.FPDFAnnot_SetColor(
            nativeAnnotation,
            pdfium_bindings.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
            color.$1,
            color.$2,
            color.$3,
            hasMarkupGeometry ? 110 : 255,
          ) ==
          0) {
        throw StateError('PDFium could not set an annotation color.');
      }
      using((arena) {
        final bounds = boxes.isEmpty
            ? (
                left: 24.0,
                top: math.max(48.0, sourcePage.height - 24.0),
                right: 48.0,
                bottom: math.max(24.0, sourcePage.height - 48.0),
              )
            : (
                left: boxes.map((box) => box.left).reduce(math.min),
                top: boxes.map((box) => box.top).reduce(math.max),
                right: boxes.map((box) => box.right).reduce(math.max),
                bottom: boxes.map((box) => box.bottom).reduce(math.min),
              );
        final rect = arena<pdfium_bindings.FS_RECTF>();
        rect.ref
          ..left = bounds.left
          ..top = bounds.top
          ..right = bounds.right
          ..bottom = bounds.bottom;
        if (api.FPDFAnnot_SetRect(nativeAnnotation, rect) == 0) {
          throw StateError('PDFium could not position an annotation.');
        }
        if (hasMarkupGeometry) {
          for (final box in boxes) {
            final quad = arena<pdfium_bindings.FS_QUADPOINTSF>();
            quad.ref
              ..x1 = box.left
              ..y1 = box.top
              ..x2 = box.right
              ..y2 = box.top
              ..x3 = box.left
              ..y3 = box.bottom
              ..x4 = box.right
              ..y4 = box.bottom;
            if (api.FPDFAnnot_AppendAttachmentPoints(nativeAnnotation, quad) ==
                0) {
              throw StateError('PDFium could not attach a text annotation.');
            }
          }
        }
        final contents = [
          if (annotation.note.trim().isNotEmpty) annotation.note.trim(),
          if (annotation.selectedText.trim().isNotEmpty)
            annotation.selectedText.trim(),
        ].join('\n');
        final key = 'Contents'.toNativeUtf8(allocator: arena).cast<ffi.Char>();
        final value = contents
            .toNativeUtf16(allocator: arena)
            .cast<pdfium_bindings.FPDF_WCHAR>();
        if (api.FPDFAnnot_SetStringValue(nativeAnnotation, key, value) == 0) {
          throw StateError('PDFium could not store annotation text.');
        }
      });
    } finally {
      api.FPDFPage_CloseAnnot(nativeAnnotation);
    }
  }

  (int, int, int) _annotationColor(String name) => switch (name) {
    'green' => (102, 187, 106),
    'blue' => (66, 165, 245),
    'pink' => (236, 64, 122),
    _ => (255, 193, 7),
  };

  bool _samePath(String left, String right) => Platform.isWindows
      ? left.toLowerCase() == right.toLowerCase()
      : left == right;

  String _fileName(String path) =>
      path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;
}
