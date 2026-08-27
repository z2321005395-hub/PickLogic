import 'dart:convert';
import 'dart:io';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:sqlite3/sqlite3.dart';

import 'pdf_metadata_reader.dart';
import 'reading_progress.dart';

/// One local PDF reference plus app-owned reading state.
///
/// The PDF remains in its original location. Persisting this value only writes
/// PickLogic's private catalog; it never writes to or renames [localPath].
final class LiteratureLibraryEntry {
  LiteratureLibraryEntry({
    required this.record,
    this.localPath,
    required this.fileName,
    required this.addedAt,
    this.currentPage = 1,
    this.totalPages,
    this.collectionIds = const <String>[],
    this.rating = 0,
    this.isStarred = false,
    this.trashedAt,
    this.supplementalPaths = const <String>[],
  }) {
    if (localPath case final String path when path.trim().isEmpty) {
      throw ArgumentError.value(path, 'localPath', 'Must not be empty.');
    }
    if (fileName.trim().isEmpty) {
      throw ArgumentError.value(fileName, 'fileName', 'Must not be empty.');
    }
    if (currentPage <= 0) {
      throw RangeError.value(currentPage, 'currentPage', 'Must be positive.');
    }
    final pageCount = totalPages;
    if (pageCount != null && (pageCount <= 0 || currentPage > pageCount)) {
      throw RangeError.value(
        pageCount,
        'totalPages',
        'Must be positive and include currentPage.',
      );
    }
    if (rating < 0 || rating > 5) {
      throw RangeError.range(rating, 0, 5, 'rating');
    }
    if (collectionIds.any((value) => value.trim().isEmpty)) {
      throw ArgumentError.value(
        collectionIds,
        'collectionIds',
        'Collection IDs must not be empty.',
      );
    }
    if (supplementalPaths.any((value) => value.trim().isEmpty)) {
      throw ArgumentError.value(
        supplementalPaths,
        'supplementalPaths',
        'Attachment paths must not be empty.',
      );
    }
  }

  final LiteratureRecord record;
  final String? localPath;
  final String fileName;
  final DateTime addedAt;
  final int currentPage;
  final int? totalPages;
  final List<String> collectionIds;
  final int rating;
  final bool isStarred;
  final DateTime? trashedAt;
  final List<String> supplementalPaths;

  String get id => record.id;
  bool get hasLocalPdf => localPath?.trim().isNotEmpty == true;
  bool get isTrashed => trashedAt != null;

  List<String> get allAttachmentPaths => List<String>.unmodifiable({
    if (localPath case final String path) path,
    ...supplementalPaths,
  });

  /// Replaces app-owned metadata while preserving the source reference and
  /// reading position. The source PDF is never opened for writing.
  LiteratureLibraryEntry replaceRecord(LiteratureRecord updatedRecord) {
    if (updatedRecord.id != id ||
        updatedRecord.localFileId != record.localFileId) {
      throw ArgumentError(
        'Updated metadata must preserve the literature and local-file IDs.',
      );
    }
    return LiteratureLibraryEntry(
      record: updatedRecord,
      localPath: localPath,
      fileName: fileName,
      addedAt: addedAt,
      currentPage: currentPage,
      totalPages: totalPages,
      collectionIds: collectionIds,
      rating: rating,
      isStarred: isStarred,
      trashedAt: trashedAt,
      supplementalPaths: supplementalPaths,
    );
  }

  LiteratureLibraryEntry recordPosition({
    required int currentPage,
    required int totalPages,
    required DateTime openedAt,
  }) {
    final updatedRecord = const LiteratureReadingTracker().recordPage(
      record,
      currentPage: currentPage,
      totalPages: totalPages,
      openedAt: openedAt,
    );
    return LiteratureLibraryEntry(
      record: updatedRecord,
      localPath: localPath,
      fileName: fileName,
      addedAt: addedAt,
      currentPage: currentPage,
      totalPages: totalPages,
      collectionIds: collectionIds,
      rating: rating,
      isStarred: isStarred,
      trashedAt: trashedAt,
      supplementalPaths: supplementalPaths,
    );
  }

  LiteratureLibraryEntry replaceOrganization({
    List<String>? collectionIds,
    int? rating,
    bool? isStarred,
  }) => LiteratureLibraryEntry(
    record: record,
    localPath: localPath,
    fileName: fileName,
    addedAt: addedAt,
    currentPage: currentPage,
    totalPages: totalPages,
    collectionIds: List<String>.unmodifiable(
      collectionIds ?? this.collectionIds,
    ),
    rating: rating ?? this.rating,
    isStarred: isStarred ?? this.isStarred,
    trashedAt: trashedAt,
    supplementalPaths: supplementalPaths,
  );

  LiteratureLibraryEntry attachPdf({
    required String path,
    required String fileName,
  }) {
    final existingPrimary = localPath;
    return LiteratureLibraryEntry(
      record: record,
      localPath: path,
      fileName: fileName,
      addedAt: addedAt,
      currentPage: 1,
      collectionIds: collectionIds,
      rating: rating,
      isStarred: isStarred,
      trashedAt: trashedAt,
      supplementalPaths: List<String>.unmodifiable({
        if (existingPrimary != null &&
            existingPrimary.toLowerCase() != path.toLowerCase())
          existingPrimary,
        ...supplementalPaths.where(
          (candidate) => candidate.toLowerCase() != path.toLowerCase(),
        ),
      }),
    );
  }

  LiteratureLibraryEntry replaceAttachments({
    String? primaryPdfPath,
    String? primaryFileName,
    List<String>? supplementalPaths,
  }) => LiteratureLibraryEntry(
    record: record,
    localPath: primaryPdfPath ?? localPath,
    fileName: primaryFileName ?? fileName,
    addedAt: addedAt,
    currentPage: currentPage,
    totalPages: totalPages,
    collectionIds: collectionIds,
    rating: rating,
    isStarred: isStarred,
    trashedAt: trashedAt,
    supplementalPaths: List<String>.unmodifiable(
      supplementalPaths ?? this.supplementalPaths,
    ),
  );

  LiteratureLibraryEntry moveToTrash(DateTime changedAt) =>
      LiteratureLibraryEntry(
        record: record,
        localPath: localPath,
        fileName: fileName,
        addedAt: addedAt,
        currentPage: currentPage,
        totalPages: totalPages,
        collectionIds: collectionIds,
        rating: rating,
        isStarred: isStarred,
        trashedAt: changedAt.toUtc(),
        supplementalPaths: supplementalPaths,
      );

  LiteratureLibraryEntry restoreFromTrash() => LiteratureLibraryEntry(
    record: record,
    localPath: localPath,
    fileName: fileName,
    addedAt: addedAt,
    currentPage: currentPage,
    totalPages: totalPages,
    collectionIds: collectionIds,
    rating: rating,
    isStarred: isStarred,
    supplementalPaths: supplementalPaths,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'localPath': localPath,
    'fileName': fileName,
    'addedAt': addedAt.toUtc().toIso8601String(),
    'currentPage': currentPage,
    'totalPages': totalPages,
    'collectionIds': collectionIds,
    'rating': rating,
    'isStarred': isStarred,
    'trashedAt': trashedAt?.toUtc().toIso8601String(),
    'supplementalPaths': supplementalPaths,
    'record': <String, Object?>{
      'id': record.id,
      'localFileId': record.localFileId,
      'doi': record.doi,
      'title': record.title,
      'authors': record.authors,
      'journal': record.journal,
      'year': record.year,
      'volume': record.volume,
      'issue': record.issue,
      'pages': record.pages,
      'abstractText': record.abstractText,
      'keywords': record.keywords,
      'tags': record.tags,
      'readingProgress': record.readingProgress,
      'lastOpenedAt': record.lastOpenedAt?.toUtc().toIso8601String(),
      'metadataSource': record.metadataSource,
      'metadataConfidence': record.metadataConfidence,
    },
  };

  factory LiteratureLibraryEntry.fromJson(Object? value) {
    final map = _stringMap(value, 'library entry');
    final recordMap = _stringMap(map['record'], 'literature record');
    return LiteratureLibraryEntry(
      record: LiteratureRecord(
        id: _requiredString(recordMap, 'id'),
        localFileId: _requiredString(recordMap, 'localFileId'),
        doi: _optionalString(recordMap['doi']),
        title: _requiredString(recordMap, 'title', allowEmpty: true),
        authors: _stringList(recordMap['authors'], 'authors'),
        journal: _optionalString(recordMap['journal']) ?? '',
        year: _optionalInt(recordMap['year'], 'year'),
        volume: _optionalString(recordMap['volume']) ?? '',
        issue: _optionalString(recordMap['issue']) ?? '',
        pages: _optionalString(recordMap['pages']) ?? '',
        abstractText: _optionalString(recordMap['abstractText']) ?? '',
        keywords: _stringList(recordMap['keywords'], 'keywords'),
        tags: _stringList(recordMap['tags'], 'tags'),
        readingProgress: _doubleInRange(
          recordMap['readingProgress'],
          'readingProgress',
        ),
        lastOpenedAt: _optionalDateTime(
          recordMap['lastOpenedAt'],
          'lastOpenedAt',
        ),
        metadataSource: _optionalString(recordMap['metadataSource']) ?? 'local',
        metadataConfidence: _doubleInRange(
          recordMap['metadataConfidence'],
          'metadataConfidence',
        ),
      ),
      localPath: _optionalString(map['localPath']),
      fileName: _requiredString(map, 'fileName'),
      addedAt: _requiredDateTime(map['addedAt'], 'addedAt'),
      currentPage: _optionalInt(map['currentPage'], 'currentPage') ?? 1,
      totalPages: _optionalInt(map['totalPages'], 'totalPages'),
      collectionIds: _stringList(map['collectionIds'], 'collectionIds'),
      rating: _optionalInt(map['rating'], 'rating') ?? 0,
      isStarred: _optionalBool(map['isStarred'], 'isStarred') ?? false,
      trashedAt: _optionalDateTime(map['trashedAt'], 'trashedAt'),
      supplementalPaths: _stringList(
        map['supplementalPaths'],
        'supplementalPaths',
      ),
    );
  }

  static LiteratureLibraryEntry fromProbe({
    required String localPath,
    required String fileName,
    required PdfMetadataProbe probe,
    required DateTime addedAt,
  }) {
    final id = stableIdForPath(localPath);
    final stem = fileName.toLowerCase().endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    final knownFields = <bool>[
      probe.title != null,
      probe.authors.isNotEmpty,
      probe.doiCandidates.isNotEmpty,
      probe.year != null,
    ].where((value) => value).length;
    return LiteratureLibraryEntry(
      record: LiteratureRecord(
        id: id,
        localFileId: 'local-$id',
        doi: probe.doiCandidates.firstOrNull,
        title: probe.title?.trim().isNotEmpty == true ? probe.title! : stem,
        authors: probe.authors,
        year: probe.year,
        keywords: probe.keywords,
        metadataSource: 'bounded local PDF metadata',
        metadataConfidence: probe.hasPdfHeader ? 0.5 + knownFields * 0.125 : 0,
      ),
      localPath: localPath,
      fileName: fileName,
      addedAt: addedAt,
    );
  }

  static LiteratureLibraryEntry fromImportedRecord({
    required LiteratureRecord record,
    required DateTime addedAt,
    String sourceFileName = 'Imported reference',
  }) => LiteratureLibraryEntry(
    record: record,
    fileName: sourceFileName,
    addedAt: addedAt,
  );

  /// Stable local identifier without persisting the path inside the ID.
  static String stableIdForPath(String path) {
    return _stableId('path:${path.toLowerCase()}');
  }

  static String stableIdForReference({
    String? doi,
    required String title,
    List<String> authors = const <String>[],
    int? year,
  }) {
    final normalizedDoi = doi?.trim().toLowerCase();
    final seed = normalizedDoi?.isNotEmpty == true
        ? 'doi:$normalizedDoi'
        : 'reference:${_identityText(title)}|${authors.map(_identityText).join('|')}|${year ?? ''}';
    return _stableId(seed);
  }

  static String _stableId(String seed) {
    const offsetBasis = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    var hash = offsetBasis;
    for (final byte in utf8.encode(seed)) {
      hash ^= byte;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return 'lit-${hash.toRadixString(16).padLeft(16, '0')}';
  }

  static String _identityText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ')
      .trim();
}

abstract interface class LiteratureLibraryStore {
  Future<List<LiteratureLibraryEntry>> load();

  Future<void> save(List<LiteratureLibraryEntry> entries);
}

/// JSON persistence for app-owned literature catalog state.
final class JsonFileLiteratureLibraryStore implements LiteratureLibraryStore {
  const JsonFileLiteratureLibraryStore(this.catalogPath);

  final String catalogPath;

  @override
  Future<List<LiteratureLibraryEntry>> load() async {
    final file = File(catalogPath);
    if (!await file.exists()) return const <LiteratureLibraryEntry>[];
    final decoded = jsonDecode(await file.readAsString());
    final root = _stringMap(decoded, 'catalog root');
    if (root['version'] != 1) {
      throw const FormatException('Unsupported literature catalog version.');
    }
    final rawEntries = root['entries'];
    if (rawEntries is! List<Object?>) {
      throw const FormatException('Catalog entries must be a list.');
    }
    return List<LiteratureLibraryEntry>.unmodifiable(
      rawEntries.map(LiteratureLibraryEntry.fromJson),
    );
  }

  @override
  Future<void> save(List<LiteratureLibraryEntry> entries) async {
    final file = File(catalogPath);
    await file.parent.create(recursive: true);
    final payload = jsonEncode(<String, Object?>{
      'version': 1,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    });
    await file.writeAsString(payload, flush: true);
  }
}

/// SQLite persistence for the app-owned Pro literature catalog.
///
/// Each entry remains a compact, versioned JSON payload inside SQLite. This
/// keeps the stable model serializer authoritative while providing atomic
/// catalog replacement and durable ordering without touching source PDFs.
final class SqliteLiteratureLibraryStore implements LiteratureLibraryStore {
  const SqliteLiteratureLibraryStore(this.catalogPath);

  final String catalogPath;

  @override
  Future<List<LiteratureLibraryEntry>> load() async {
    final database = await _open();
    try {
      final rows = database.select(
        'SELECT payload_json FROM literature_catalog ORDER BY sort_index',
      );
      return List<LiteratureLibraryEntry>.unmodifiable(
        rows.map(
          (row) => LiteratureLibraryEntry.fromJson(
            jsonDecode(row['payload_json']! as String),
          ),
        ),
      );
    } finally {
      database.close();
    }
  }

  @override
  Future<void> save(List<LiteratureLibraryEntry> entries) async {
    final database = await _open();
    PreparedStatement? insert;
    try {
      database.execute('BEGIN IMMEDIATE');
      database.execute('DELETE FROM literature_catalog');
      insert = database.prepare(
        'INSERT INTO literature_catalog '
        '(entry_id, sort_index, payload_json) VALUES (?, ?, ?)',
      );
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        insert.execute(<Object?>[entry.id, index, jsonEncode(entry.toJson())]);
      }
      database.execute('COMMIT');
    } on Object {
      if (database.autocommit == false) database.execute('ROLLBACK');
      rethrow;
    } finally {
      insert?.close();
      database.close();
    }
  }

  Future<Database> _open() async {
    final file = File(catalogPath);
    await file.parent.create(recursive: true);
    final database = sqlite3.open(catalogPath);
    database.execute('''
      CREATE TABLE IF NOT EXISTS literature_catalog (
        entry_id TEXT PRIMARY KEY NOT NULL,
        sort_index INTEGER NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');
    database.execute('PRAGMA user_version = 1');
    return database;
  }
}

Map<String, Object?> _stringMap(Object? value, String label) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$label must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String _requiredString(
  Map<String, Object?> map,
  String key, {
  bool allowEmpty = false,
}) {
  final value = map[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException(
      '$key must be a ${allowEmpty ? '' : 'non-empty '}string.',
    );
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Expected a string.');
  return value;
}

List<String> _stringList(Object? value, String label) {
  if (value == null) return const <String>[];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$label must contain only strings.');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

int? _optionalInt(Object? value, String label) {
  if (value == null) return null;
  if (value is! int) throw FormatException('$label must be an integer.');
  return value;
}

bool? _optionalBool(Object? value, String label) {
  if (value == null) return null;
  if (value is! bool) throw FormatException('$label must be a boolean.');
  return value;
}

double _doubleInRange(Object? value, String label) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) {
    throw FormatException('$label must be between 0 and 1.');
  }
  return value.toDouble();
}

DateTime _requiredDateTime(Object? value, String label) {
  final parsed = _optionalDateTime(value, label);
  if (parsed == null) throw FormatException('$label must not be null.');
  return parsed;
}

DateTime? _optionalDateTime(Object? value, String label) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$label must be a date string.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$label is not a valid date.');
  return parsed.toUtc();
}
