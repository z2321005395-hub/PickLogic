enum PdfContentObjectKind { text, image }

/// Axis-aligned PDF user-space bounds. PDF coordinates start at the page's
/// bottom-left corner and are measured in points.
final class PdfContentBounds {
  const PdfContentBounds({
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
  }) : assert(right > left),
       assert(top > bottom);

  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => right - left;
  double get height => top - bottom;
  double get centerX => (left + right) / 2;
  double get centerY => (bottom + top) / 2;

  PdfContentBounds translate(double dx, double dy) => PdfContentBounds(
    left: left + dx,
    bottom: bottom + dy,
    right: right + dx,
    top: top + dy,
  );

  PdfContentBounds resize({required double width, required double height}) =>
      PdfContentBounds(
        left: left,
        bottom: top - height,
        right: left + width,
        top: top,
      );

  PdfContentBounds clampToPage({
    required double pageWidth,
    required double pageHeight,
  }) {
    final boundedWidth = width.clamp(4.0, pageWidth).toDouble();
    final boundedHeight = height.clamp(4.0, pageHeight).toDouble();
    final boundedLeft = left.clamp(0.0, pageWidth - boundedWidth).toDouble();
    final boundedBottom = bottom
        .clamp(0.0, pageHeight - boundedHeight)
        .toDouble();
    return PdfContentBounds(
      left: boundedLeft,
      bottom: boundedBottom,
      right: boundedLeft + boundedWidth,
      top: boundedBottom + boundedHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfContentBounds &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.top == top;

  @override
  int get hashCode => Object.hash(left, bottom, right, top);
}

/// A supported top-level PDF page object discovered by PDFium.
final class PdfContentObjectDescriptor {
  const PdfContentObjectDescriptor({
    required this.pageNumber,
    required this.objectIndex,
    required this.kind,
    required this.bounds,
    this.text = '',
    this.fontSize,
  }) : assert(pageNumber > 0),
       assert(objectIndex >= 0);

  final int pageNumber;
  final int objectIndex;
  final PdfContentObjectKind kind;
  final PdfContentBounds bounds;
  final String text;
  final double? fontSize;

  String get id => 'source:$pageNumber:$objectIndex';
}

/// Desired state for one editable text or image object.
final class PdfContentObjectEdit {
  const PdfContentObjectEdit({
    required this.id,
    required this.pageNumber,
    required this.kind,
    required this.sourceBounds,
    required this.targetBounds,
    this.sourceObjectIndex,
    this.replacementText,
    this.replacementImagePath,
    this.fontSize = 12,
    this.rotationDegrees = 0,
    this.deleted = false,
  }) : assert(pageNumber > 0),
       assert(sourceObjectIndex == null || sourceObjectIndex >= 0),
       assert(fontSize > 0);

  factory PdfContentObjectEdit.fromDescriptor(
    PdfContentObjectDescriptor descriptor,
  ) => PdfContentObjectEdit(
    id: descriptor.id,
    pageNumber: descriptor.pageNumber,
    sourceObjectIndex: descriptor.objectIndex,
    kind: descriptor.kind,
    sourceBounds: descriptor.bounds,
    targetBounds: descriptor.bounds,
    fontSize: descriptor.fontSize ?? 12,
  );

  factory PdfContentObjectEdit.addText({
    required String id,
    required int pageNumber,
    required PdfContentBounds bounds,
    required String text,
    double fontSize = 12,
  }) => PdfContentObjectEdit(
    id: id,
    pageNumber: pageNumber,
    kind: PdfContentObjectKind.text,
    sourceBounds: bounds,
    targetBounds: bounds,
    replacementText: text,
    fontSize: fontSize,
  );

  factory PdfContentObjectEdit.addImage({
    required String id,
    required int pageNumber,
    required PdfContentBounds bounds,
    required String imagePath,
  }) => PdfContentObjectEdit(
    id: id,
    pageNumber: pageNumber,
    kind: PdfContentObjectKind.image,
    sourceBounds: bounds,
    targetBounds: bounds,
    replacementImagePath: imagePath,
  );

  final String id;
  final int pageNumber;
  final int? sourceObjectIndex;
  final PdfContentObjectKind kind;
  final PdfContentBounds sourceBounds;
  final PdfContentBounds targetBounds;
  final String? replacementText;
  final String? replacementImagePath;
  final double fontSize;
  final double rotationDegrees;
  final bool deleted;

  bool get isNew => sourceObjectIndex == null;

  bool get changed =>
      isNew ||
      deleted ||
      replacementText != null ||
      replacementImagePath != null ||
      targetBounds != sourceBounds ||
      rotationDegrees != 0;

  PdfContentObjectEdit copyWith({
    PdfContentBounds? targetBounds,
    String? replacementText,
    bool clearReplacementText = false,
    String? replacementImagePath,
    bool clearReplacementImagePath = false,
    double? fontSize,
    double? rotationDegrees,
    bool? deleted,
  }) => PdfContentObjectEdit(
    id: id,
    pageNumber: pageNumber,
    sourceObjectIndex: sourceObjectIndex,
    kind: kind,
    sourceBounds: sourceBounds,
    targetBounds: targetBounds ?? this.targetBounds,
    replacementText: clearReplacementText
        ? null
        : replacementText ?? this.replacementText,
    replacementImagePath: clearReplacementImagePath
        ? null
        : replacementImagePath ?? this.replacementImagePath,
    fontSize: fontSize ?? this.fontSize,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    deleted: deleted ?? this.deleted,
  );
}

/// Immutable object-edit plan applied before page assembly and annotation
/// embedding. It never names an output path and cannot overwrite the source.
final class PdfContentEditPlan {
  PdfContentEditPlan({required List<PdfContentObjectEdit> edits})
    : edits = List<PdfContentObjectEdit>.unmodifiable(edits) {
    final ids = <String>{};
    for (final edit in edits) {
      if (!ids.add(edit.id)) {
        throw ArgumentError('Duplicate PDF content edit id: ${edit.id}');
      }
      if (edit.kind == PdfContentObjectKind.text &&
          edit.isNew &&
          (edit.replacementText == null || edit.replacementText!.isEmpty)) {
        throw ArgumentError('A new text object must contain text.');
      }
      if (edit.kind == PdfContentObjectKind.image &&
          edit.isNew &&
          (edit.replacementImagePath == null ||
              edit.replacementImagePath!.isEmpty)) {
        throw ArgumentError('A new image object must name a local image.');
      }
    }
  }

  factory PdfContentEditPlan.empty() => PdfContentEditPlan(edits: const []);

  final List<PdfContentObjectEdit> edits;

  bool get changed => edits.any((edit) => edit.changed);

  List<PdfContentObjectEdit> forPage(int pageNumber) => edits
      .where((edit) => edit.pageNumber == pageNumber && edit.changed)
      .toList(growable: false);
}
