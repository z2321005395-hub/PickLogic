import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';

/// Bounded PDFium adapter for top-level text and image page objects.
///
/// The source document is mutated only in memory immediately before an edited
/// copy is encoded. The caller remains responsible for the source-preserving
/// Save As contract.
final class PdfContentObjectService {
  const PdfContentObjectService({
    this.maximumImageBytes = 32 * 1024 * 1024,
    this.maximumDecodedDimension = 4096,
    this.maximumDecodedPixels = 16 * 1024 * 1024,
  });

  final int maximumImageBytes;
  final int maximumDecodedDimension;
  final int maximumDecodedPixels;

  Future<List<PdfContentObjectDescriptor>> inspectPage(
    PdfDocument document,
    int pageNumber,
  ) async {
    if (pageNumber < 1 || pageNumber > document.pages.length) {
      throw RangeError.range(
        pageNumber,
        1,
        document.pages.length,
        'pageNumber',
      );
    }
    final api = pdfium_bindings.getPdfium();
    return document.useNativeDocumentHandle((nativeHandle) {
      final nativeDocument = pdfium_bindings.FPDF_DOCUMENT.fromAddress(
        nativeHandle,
      );
      final page = api.FPDF_LoadPage(nativeDocument, pageNumber - 1);
      if (page == ffi.nullptr) {
        throw StateError('PDFium could not load the selected page.');
      }
      final textPage = api.FPDFText_LoadPage(page);
      try {
        final result = <PdfContentObjectDescriptor>[];
        final count = api.FPDFPage_CountObjects(page);
        for (var objectIndex = 0; objectIndex < count; objectIndex++) {
          final object = api.FPDFPage_GetObject(page, objectIndex);
          if (object == ffi.nullptr) continue;
          final type = api.FPDFPageObj_GetType(object);
          final kind = switch (type) {
            pdfium_bindings.FPDF_PAGEOBJ_TEXT => PdfContentObjectKind.text,
            pdfium_bindings.FPDF_PAGEOBJ_IMAGE => PdfContentObjectKind.image,
            _ => null,
          };
          if (kind == null) continue;
          final bounds = _readBounds(api, object);
          if (bounds == null) continue;
          result.add(
            PdfContentObjectDescriptor(
              pageNumber: pageNumber,
              objectIndex: objectIndex,
              kind: kind,
              bounds: bounds,
              text: kind == PdfContentObjectKind.text && textPage != ffi.nullptr
                  ? _readText(api, object, textPage)
                  : '',
              fontSize: kind == PdfContentObjectKind.text
                  ? _readFontSize(api, object)
                  : null,
            ),
          );
        }
        return result;
      } finally {
        if (textPage != ffi.nullptr) api.FPDFText_ClosePage(textPage);
        api.FPDF_ClosePage(page);
      }
    });
  }

  Future<void> applyToDocument(
    PdfDocument document,
    PdfContentEditPlan plan,
  ) async {
    if (!plan.changed) return;
    final decodedImages = <String, _DecodedPdfImage>{};
    try {
      for (final path
          in plan.edits
              .map((edit) => edit.replacementImagePath)
              .whereType<String>()
              .toSet()) {
        decodedImages[path] = await _decodeImage(path);
      }
      final api = pdfium_bindings.getPdfium();
      await document.useNativeDocumentHandle((nativeHandle) {
        final nativeDocument = pdfium_bindings.FPDF_DOCUMENT.fromAddress(
          nativeHandle,
        );
        final pageNumbers =
            plan.edits
                .where((edit) => edit.changed)
                .map((edit) => edit.pageNumber)
                .toSet()
                .toList()
              ..sort();
        for (final pageNumber in pageNumbers) {
          if (pageNumber < 1 || pageNumber > document.pages.length) {
            throw StateError('A content edit points outside the source PDF.');
          }
          final page = api.FPDF_LoadPage(nativeDocument, pageNumber - 1);
          if (page == ffi.nullptr) {
            throw StateError('PDFium could not load an edited page.');
          }
          try {
            _applyPage(
              api: api,
              nativeDocument: nativeDocument,
              page: page,
              edits: plan.forPage(pageNumber),
              decodedImages: decodedImages,
            );
            if (api.FPDFPage_GenerateContent(page) == 0) {
              throw StateError('PDFium could not regenerate edited content.');
            }
          } finally {
            api.FPDF_ClosePage(page);
          }
        }
      });
    } finally {
      for (final image in decodedImages.values) {
        image.dispose();
      }
    }
  }

  void _applyPage({
    required pdfium_bindings.PDFium api,
    required pdfium_bindings.FPDF_DOCUMENT nativeDocument,
    required pdfium_bindings.FPDF_PAGE page,
    required List<PdfContentObjectEdit> edits,
    required Map<String, _DecodedPdfImage> decodedImages,
  }) {
    final originalObjects = <int, pdfium_bindings.FPDF_PAGEOBJECT>{};
    final originalCount = api.FPDFPage_CountObjects(page);
    for (var index = 0; index < originalCount; index++) {
      final object = api.FPDFPage_GetObject(page, index);
      if (object != ffi.nullptr) originalObjects[index] = object;
    }

    for (final edit in edits.where((item) => !item.isNew)) {
      final object = originalObjects[edit.sourceObjectIndex];
      if (object == null) {
        throw StateError('The PDF object list changed; reopen the editor.');
      }
      final expectedType = edit.kind == PdfContentObjectKind.text
          ? pdfium_bindings.FPDF_PAGEOBJ_TEXT
          : pdfium_bindings.FPDF_PAGEOBJ_IMAGE;
      if (api.FPDFPageObj_GetType(object) != expectedType) {
        throw StateError('The selected PDF object changed; reopen the editor.');
      }
      if (edit.deleted) {
        if (api.FPDFPage_RemoveObject(page, object) == 0) {
          throw StateError('PDFium could not remove the selected object.');
        }
        api.FPDFPageObj_Destroy(object);
        continue;
      }
      if (edit.kind == PdfContentObjectKind.text &&
          edit.replacementText != null) {
        using((arena) {
          final text = edit.replacementText!
              .toNativeUtf16(allocator: arena)
              .cast<pdfium_bindings.FPDF_WCHAR>();
          if (api.FPDFText_SetText(object, text) == 0) {
            throw StateError(
              'The embedded font cannot represent the replacement text.',
            );
          }
        });
      }
      if (edit.kind == PdfContentObjectKind.image &&
          edit.replacementImagePath != null) {
        _setImageBitmap(
          api,
          page,
          object,
          decodedImages[edit.replacementImagePath]!,
        );
      }
      _transformExisting(api, object, edit);
    }

    for (final edit in edits.where((item) => item.isNew && !item.deleted)) {
      switch (edit.kind) {
        case PdfContentObjectKind.text:
          _insertText(api, nativeDocument, page, edit);
        case PdfContentObjectKind.image:
          _insertImage(
            api,
            nativeDocument,
            page,
            edit,
            decodedImages[edit.replacementImagePath]!,
          );
      }
    }
  }

  void _transformExisting(
    pdfium_bindings.PDFium api,
    pdfium_bindings.FPDF_PAGEOBJECT object,
    PdfContentObjectEdit edit,
  ) {
    if (edit.targetBounds == edit.sourceBounds && edit.rotationDegrees == 0) {
      return;
    }
    final matrix = _mappingMatrix(
      source: edit.sourceBounds,
      target: edit.targetBounds,
      rotationDegrees: edit.rotationDegrees,
    );
    api.FPDFPageObj_Transform(
      object,
      matrix.$1,
      matrix.$2,
      matrix.$3,
      matrix.$4,
      matrix.$5,
      matrix.$6,
    );
  }

  void _insertText(
    pdfium_bindings.PDFium api,
    pdfium_bindings.FPDF_DOCUMENT document,
    pdfium_bindings.FPDF_PAGE page,
    PdfContentObjectEdit edit,
  ) {
    using((arena) {
      final font = 'Helvetica'.toNativeUtf8(allocator: arena).cast<ffi.Char>();
      final object = api.FPDFPageObj_NewTextObj(document, font, edit.fontSize);
      if (object == ffi.nullptr) {
        throw StateError('PDFium could not create a text object.');
      }
      var inserted = false;
      try {
        final text = edit.replacementText!
            .toNativeUtf16(allocator: arena)
            .cast<pdfium_bindings.FPDF_WCHAR>();
        if (api.FPDFText_SetText(object, text) == 0 ||
            api.FPDFPageObj_SetFillColor(object, 24, 31, 43, 255) == 0) {
          throw StateError('PDFium could not set the new text.');
        }
        final measured = _readBounds(api, object);
        if (measured != null) {
          final matrix = _mappingMatrix(
            source: measured,
            target: edit.targetBounds,
            rotationDegrees: edit.rotationDegrees,
          );
          api.FPDFPageObj_Transform(
            object,
            matrix.$1,
            matrix.$2,
            matrix.$3,
            matrix.$4,
            matrix.$5,
            matrix.$6,
          );
        } else {
          api.FPDFPageObj_Transform(
            object,
            1,
            0,
            0,
            1,
            edit.targetBounds.left,
            edit.targetBounds.bottom,
          );
        }
        if (api.FPDFPage_InsertObject(page, object) == 0) {
          throw StateError('PDFium could not insert the new text.');
        }
        inserted = true;
      } finally {
        if (!inserted) api.FPDFPageObj_Destroy(object);
      }
    });
  }

  void _insertImage(
    pdfium_bindings.PDFium api,
    pdfium_bindings.FPDF_DOCUMENT document,
    pdfium_bindings.FPDF_PAGE page,
    PdfContentObjectEdit edit,
    _DecodedPdfImage image,
  ) {
    final object = api.FPDFPageObj_NewImageObj(document);
    if (object == ffi.nullptr) {
      throw StateError('PDFium could not create an image object.');
    }
    var inserted = false;
    try {
      _setImageBitmap(api, page, object, image);
      final radians = edit.rotationDegrees * math.pi / 180;
      final cosAngle = math.cos(radians);
      final sinAngle = math.sin(radians);
      final bounds = edit.targetBounds;
      final a = bounds.width * cosAngle;
      final b = bounds.width * sinAngle;
      final c = -bounds.height * sinAngle;
      final d = bounds.height * cosAngle;
      final e = bounds.centerX - (a + c) / 2;
      final f = bounds.centerY - (b + d) / 2;
      if (api.FPDFImageObj_SetMatrix(object, a, b, c, d, e, f) == 0) {
        throw StateError('PDFium could not position the new image.');
      }
      if (api.FPDFPage_InsertObject(page, object) == 0) {
        throw StateError('PDFium could not insert the new image.');
      }
      inserted = true;
    } finally {
      if (!inserted) api.FPDFPageObj_Destroy(object);
    }
  }

  void _setImageBitmap(
    pdfium_bindings.PDFium api,
    pdfium_bindings.FPDF_PAGE page,
    pdfium_bindings.FPDF_PAGEOBJECT object,
    _DecodedPdfImage image,
  ) {
    final bitmap = api.FPDFBitmap_CreateEx(
      image.width,
      image.height,
      pdfium_bindings.FPDFBitmap_BGRA,
      ffi.nullptr,
      0,
    );
    if (bitmap == ffi.nullptr) {
      throw StateError('PDFium could not allocate an image bitmap.');
    }
    try {
      final stride = api.FPDFBitmap_GetStride(bitmap);
      final buffer = api.FPDFBitmap_GetBuffer(
        bitmap,
      ).cast<ffi.Uint8>().asTypedList(stride * image.height);
      for (var y = 0; y < image.height; y++) {
        final sourceRow = y * image.width * 4;
        final destinationRow = y * stride;
        for (var x = 0; x < image.width; x++) {
          final source = sourceRow + x * 4;
          final destination = destinationRow + x * 4;
          buffer[destination] = image.rgba[source + 2];
          buffer[destination + 1] = image.rgba[source + 1];
          buffer[destination + 2] = image.rgba[source];
          buffer[destination + 3] = image.rgba[source + 3];
        }
      }
      using((arena) {
        final pages = arena<pdfium_bindings.FPDF_PAGE>();
        pages.value = page;
        if (api.FPDFImageObj_SetBitmap(pages, 1, object, bitmap) == 0) {
          throw StateError('PDFium could not attach the replacement image.');
        }
      });
    } finally {
      api.FPDFBitmap_Destroy(bitmap);
    }
  }

  Future<_DecodedPdfImage> _decodeImage(String path) async {
    final file = File(path).absolute;
    if (!await file.exists()) {
      throw StateError('The selected replacement image no longer exists.');
    }
    final byteLength = await file.length();
    if (byteLength > maximumImageBytes) {
      throw StateError('The selected image exceeds the 32 MB editing limit.');
    }
    final bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        math.min(
          maximumDecodedDimension / math.max(descriptor.width, 1),
          maximumDecodedDimension / math.max(descriptor.height, 1),
        ),
      );
      final pixelScale = math.sqrt(
        maximumDecodedPixels /
            math.max(1, descriptor.width * descriptor.height),
      );
      final boundedScale = math.min(scale, math.min(1.0, pixelScale));
      final width = math.max(1, (descriptor.width * boundedScale).round());
      final height = math.max(1, (descriptor.height * boundedScale).round());
      codec = await descriptor.instantiateCodec(
        targetWidth: width,
        targetHeight: height,
      );
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      final rgba = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        throw StateError('Flutter could not decode the selected image.');
      }
      return _DecodedPdfImage(
        width: decoded.width,
        height: decoded.height,
        rgba: Uint8List.fromList(rgba.buffer.asUint8List()),
      );
    } finally {
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  PdfContentBounds? _readBounds(
    pdfium_bindings.PDFium api,
    pdfium_bindings.FPDF_PAGEOBJECT object,
  ) => using((arena) {
    final left = arena<ffi.Float>();
    final bottom = arena<ffi.Float>();
    final right = arena<ffi.Float>();
    final top = arena<ffi.Float>();
    if (api.FPDFPageObj_GetBounds(object, left, bottom, right, top) == 0 ||
        right.value <= left.value ||
        top.value <= bottom.value) {
      return null;
    }
    return PdfContentBounds(
      left: left.value,
      bottom: bottom.value,
      right: right.value,
      top: top.value,
    );
  });

  double? _readFontSize(
    pdfium_bindings.PDFium api,
    pdfium_bindings.FPDF_PAGEOBJECT object,
  ) => using((arena) {
    final size = arena<ffi.Float>();
    return api.FPDFTextObj_GetFontSize(object, size) == 0 ? null : size.value;
  });

  String _readText(
    pdfium_bindings.PDFium api,
    pdfium_bindings.FPDF_PAGEOBJECT object,
    pdfium_bindings.FPDF_TEXTPAGE textPage,
  ) {
    final required = api.FPDFTextObj_GetText(object, textPage, ffi.nullptr, 0);
    if (required <= 1) return '';
    final buffer = calloc<ffi.Uint16>(required);
    try {
      final written = api.FPDFTextObj_GetText(
        object,
        textPage,
        buffer.cast<pdfium_bindings.FPDF_WCHAR>(),
        required,
      );
      if (written == 0) return '';
      final units = buffer.asTypedList(required);
      final terminator = units.indexOf(0);
      return String.fromCharCodes(
        terminator < 0 ? units : units.take(terminator),
      );
    } finally {
      calloc.free(buffer);
    }
  }

  (double, double, double, double, double, double) _mappingMatrix({
    required PdfContentBounds source,
    required PdfContentBounds target,
    required double rotationDegrees,
  }) {
    final radians = rotationDegrees * math.pi / 180;
    final cosAngle = math.cos(radians);
    final sinAngle = math.sin(radians);
    final scaleX = target.width / source.width;
    final scaleY = target.height / source.height;
    final a = cosAngle * scaleX;
    final b = sinAngle * scaleX;
    final c = -sinAngle * scaleY;
    final d = cosAngle * scaleY;
    final e = target.centerX - a * source.centerX - c * source.centerY;
    final f = target.centerY - b * source.centerX - d * source.centerY;
    return (a, b, c, d, e, f);
  }
}

final class _DecodedPdfImage {
  _DecodedPdfImage({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  void dispose() {}
}
