import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

enum LiteratureAnnotationKind { highlight, underline, strikethrough, note }

/// One annotation rectangle in PDF page coordinates (origin at bottom-left).
final class LiteratureAnnotationBox {
  LiteratureAnnotationBox({
    required this.pageNumber,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) {
    if (pageNumber < 1 ||
        !left.isFinite ||
        !top.isFinite ||
        !right.isFinite ||
        !bottom.isFinite ||
        left > right ||
        bottom > top) {
      throw ArgumentError('Annotation box coordinates are invalid.');
    }
  }

  final int pageNumber;
  final double left;
  final double top;
  final double right;
  final double bottom;

  Map<String, Object> toJson() => <String, Object>{
    'pageNumber': pageNumber,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory LiteratureAnnotationBox.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Annotation box must be an object.');
    }
    final pageNumber = value['pageNumber'];
    final left = value['left'];
    final top = value['top'];
    final right = value['right'];
    final bottom = value['bottom'];
    if (pageNumber is! int ||
        left is! num ||
        top is! num ||
        right is! num ||
        bottom is! num) {
      throw const FormatException('Annotation box fields are invalid.');
    }
    return LiteratureAnnotationBox(
      pageNumber: pageNumber,
      left: left.toDouble(),
      top: top.toDouble(),
      right: right.toDouble(),
      bottom: bottom.toDouble(),
    );
  }
}

/// App-owned PDF annotation. The source PDF remains read-only.
final class LiteratureAnnotation {
  LiteratureAnnotation({
    required this.id,
    required this.literatureId,
    required this.pageNumber,
    required this.kind,
    required this.selectedText,
    required this.note,
    required this.colorName,
    required this.createdAt,
    required this.updatedAt,
    this.boxes = const <LiteratureAnnotationBox>[],
  }) {
    if (id.trim().isEmpty || literatureId.trim().isEmpty) {
      throw ArgumentError('Annotation and literature IDs must not be empty.');
    }
    if (pageNumber < 1) {
      throw RangeError.value(pageNumber, 'pageNumber', 'Must be positive.');
    }
    if (selectedText.trim().isEmpty && note.trim().isEmpty) {
      throw ArgumentError('An annotation needs selected text or a note.');
    }
  }

  final String id;
  final String literatureId;
  final int pageNumber;
  final LiteratureAnnotationKind kind;
  final String selectedText;
  final String note;
  final String colorName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<LiteratureAnnotationBox> boxes;

  LiteratureAnnotation replaceNote(String value, DateTime changedAt) =>
      LiteratureAnnotation(
        id: id,
        literatureId: literatureId,
        pageNumber: pageNumber,
        kind: kind,
        selectedText: selectedText,
        note: value,
        colorName: colorName,
        createdAt: createdAt,
        updatedAt: changedAt.toUtc(),
        boxes: boxes,
      );
}

abstract interface class LiteratureAnnotationStore {
  Future<List<LiteratureAnnotation>> loadFor(String literatureId);

  Future<void> upsert(LiteratureAnnotation annotation);

  Future<void> delete(String annotationId);
}

final class InMemoryLiteratureAnnotationStore
    implements LiteratureAnnotationStore {
  final Map<String, LiteratureAnnotation> _annotations = {};

  @override
  Future<List<LiteratureAnnotation>> loadFor(String literatureId) async =>
      _annotations.values
          .where((item) => item.literatureId == literatureId)
          .toList(growable: false)
        ..sort(_annotationOrder);

  @override
  Future<void> upsert(LiteratureAnnotation annotation) async {
    _annotations[annotation.id] = annotation;
  }

  @override
  Future<void> delete(String annotationId) async {
    _annotations.remove(annotationId);
  }
}

/// SQLite annotation storage can share the Pro catalog database. It changes
/// only PickLogic-owned state and never writes into the PDF.
final class SqliteLiteratureAnnotationStore
    implements LiteratureAnnotationStore {
  const SqliteLiteratureAnnotationStore(this.catalogPath);

  final String catalogPath;

  @override
  Future<List<LiteratureAnnotation>> loadFor(String literatureId) async {
    final database = await _open();
    try {
      final rows = database.select(
        'SELECT annotation_id, literature_id, page_number, kind, '
        'selected_text, note, color_name, created_at, updated_at, geometry_json '
        'FROM literature_annotations WHERE literature_id = ? '
        'ORDER BY page_number, created_at',
        <Object?>[literatureId],
      );
      return List<LiteratureAnnotation>.unmodifiable(rows.map(_fromRow));
    } finally {
      database.close();
    }
  }

  @override
  Future<void> upsert(LiteratureAnnotation annotation) async {
    final database = await _open();
    try {
      database.execute(
        'INSERT OR REPLACE INTO literature_annotations '
        '(annotation_id, literature_id, page_number, kind, selected_text, '
        'note, color_name, created_at, updated_at, geometry_json) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          annotation.id,
          annotation.literatureId,
          annotation.pageNumber,
          annotation.kind.name,
          annotation.selectedText,
          annotation.note,
          annotation.colorName,
          annotation.createdAt.toUtc().toIso8601String(),
          annotation.updatedAt.toUtc().toIso8601String(),
          jsonEncode(annotation.boxes.map((box) => box.toJson()).toList()),
        ],
      );
    } finally {
      database.close();
    }
  }

  @override
  Future<void> delete(String annotationId) async {
    final database = await _open();
    try {
      database.execute(
        'DELETE FROM literature_annotations WHERE annotation_id = ?',
        <Object?>[annotationId],
      );
    } finally {
      database.close();
    }
  }

  Future<Database> _open() async {
    final file = File(catalogPath);
    await file.parent.create(recursive: true);
    final database = sqlite3.open(catalogPath);
    database.execute('''
      CREATE TABLE IF NOT EXISTS literature_annotations (
        annotation_id TEXT PRIMARY KEY NOT NULL,
        literature_id TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        kind TEXT NOT NULL,
        selected_text TEXT NOT NULL,
        note TEXT NOT NULL,
        color_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        geometry_json TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    final columns = database
        .select('PRAGMA table_info(literature_annotations)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!columns.contains('geometry_json')) {
      database.execute(
        "ALTER TABLE literature_annotations ADD COLUMN geometry_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    database.execute(
      'CREATE INDEX IF NOT EXISTS literature_annotations_by_item '
      'ON literature_annotations(literature_id, page_number)',
    );
    return database;
  }

  static LiteratureAnnotation _fromRow(Row row) => LiteratureAnnotation(
    id: row['annotation_id']! as String,
    literatureId: row['literature_id']! as String,
    pageNumber: row['page_number']! as int,
    kind: LiteratureAnnotationKind.values.byName(row['kind']! as String),
    selectedText: row['selected_text']! as String,
    note: row['note']! as String,
    colorName: row['color_name']! as String,
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    boxes: List<LiteratureAnnotationBox>.unmodifiable(
      (jsonDecode(row['geometry_json']! as String) as List<Object?>).map(
        LiteratureAnnotationBox.fromJson,
      ),
    ),
  );
}

int _annotationOrder(LiteratureAnnotation left, LiteratureAnnotation right) {
  final pageOrder = left.pageNumber.compareTo(right.pageNumber);
  return pageOrder != 0 ? pageOrder : left.createdAt.compareTo(right.createdAt);
}
