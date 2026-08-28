import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';

import 'pdf_content_object_service.dart';
import 'pdf_edit_exporter.dart';
import 'pro_pdf_reader.dart';

/// Packaged-executable gate for PDFium object editing on synthetic data only.
Future<int> runSyntheticPdfContentEditSmoke() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp(
    'picklogic-pdf-content-smoke-',
  );
  final source = File('${directory.path}${Platform.pathSeparator}source.pdf');
  final destination = File(
    '${directory.path}${Platform.pathSeparator}edited.pdf',
  );
  final image = File(
    '${directory.path}${Platform.pathSeparator}replacement.bmp',
  );
  PdfDocument? sourceDocument;
  PdfDocument? editedDocument;
  try {
    final sourceBytes = buildSyntheticLiteraturePdf();
    await source.writeAsBytes(sourceBytes, flush: true);
    await image.writeAsBytes(_twoByTwoBmp(), flush: true);

    const service = PdfContentObjectService();
    sourceDocument = await PdfDocument.openFile(source.path);
    final objects = await service.inspectPage(sourceDocument, 1);
    final text = objects.firstWhere(
      (object) =>
          object.kind == PdfContentObjectKind.text &&
          object.text.contains('PickLogic'),
    );
    await sourceDocument.dispose();
    sourceDocument = null;

    final result = await const PdfEditedCopyExporter().export(
      sourcePath: source.path,
      destinationPath: destination.path,
      plan: PdfEditPlan.identity(2),
      contentEdits: PdfContentEditPlan(
        edits: [
          PdfContentObjectEdit.fromDescriptor(
            text,
          ).copyWith(replacementText: 'PickLogic object editing works'),
          PdfContentObjectEdit.addImage(
            id: 'smoke:new-image',
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
      ),
    );
    if (result.editedObjectCount != 2 ||
        !await destination.exists() ||
        !const ListEquality<int>().equals(
          await source.readAsBytes(),
          sourceBytes,
        )) {
      return 2;
    }

    editedDocument = await PdfDocument.openFile(destination.path);
    final editedText = await editedDocument.pages.first.loadText();
    if (editedText == null ||
        !editedText.fullText.contains('PickLogic object editing works')) {
      return 3;
    }
    final editedObjects = await service.inspectPage(editedDocument, 1);
    if (!editedObjects.any(
      (object) => object.kind == PdfContentObjectKind.image,
    )) {
      return 4;
    }
    return 0;
  } on Object catch (error, stackTrace) {
    stderr.writeln('PDF_CONTENT_EDIT_SMOKE_FAILED error=$error');
    stderr.writeln(stackTrace);
    return 1;
  } finally {
    await editedDocument?.dispose();
    await sourceDocument?.dispose();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

List<int> _twoByTwoBmp() => const <int>[
  0x42,
  0x4D,
  0x46,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0x36,
  0,
  0,
  0,
  0x28,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  1,
  0,
  0x18,
  0,
  0,
  0,
  0,
  0,
  0x10,
  0,
  0,
  0,
  0x13,
  0x0B,
  0,
  0,
  0x13,
  0x0B,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0xFF,
  0,
  0xFF,
  0,
  0,
  0,
  0xFF,
  0,
  0,
  0xFF,
  0xFF,
  0xFF,
  0,
  0,
];

final class ListEquality<T> {
  const ListEquality();

  bool equals(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
