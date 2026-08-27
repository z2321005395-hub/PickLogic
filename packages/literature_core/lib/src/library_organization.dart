import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'library_catalog.dart';

enum LiteratureCollectionKind { regular, smart }

enum LiteratureSortMode {
  addedNewest,
  title,
  firstAuthor,
  yearNewest,
  rating,
  readingProgress,
}

/// App-owned library organization. Collections never move source files.
final class LiteratureCollection {
  LiteratureCollection({
    required this.id,
    required this.name,
    required this.createdAt,
    this.parentId,
    this.kind = LiteratureCollectionKind.regular,
    this.query = '',
    this.requiredTags = const <String>[],
    this.minimumRating = 0,
    this.unreadOnly = false,
    this.starredOnly = false,
  }) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw ArgumentError('Collection ID and name must not be empty.');
    }
    if (parentId == id) {
      throw ArgumentError('A collection cannot be its own parent.');
    }
    if (minimumRating < 0 || minimumRating > 5) {
      throw RangeError.range(minimumRating, 0, 5, 'minimumRating');
    }
  }

  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;
  final LiteratureCollectionKind kind;
  final String query;
  final List<String> requiredTags;
  final int minimumRating;
  final bool unreadOnly;
  final bool starredOnly;

  bool matches(LiteratureLibraryEntry entry) {
    if (entry.isTrashed) return false;
    if (kind == LiteratureCollectionKind.regular) {
      return entry.collectionIds.contains(id);
    }
    if (minimumRating > entry.rating) return false;
    if (unreadOnly && entry.record.readingProgress > 0) return false;
    if (starredOnly && !entry.isStarred) return false;
    if (requiredTags.any((tag) => !entry.record.tags.contains(tag))) {
      return false;
    }
    final normalizedQuery = query.trim().toLowerCase();
    return normalizedQuery.isEmpty ||
        LiteratureLibraryOrganizer.searchableText(
          entry,
        ).contains(normalizedQuery);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'parentId': parentId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'kind': kind.name,
    'query': query,
    'requiredTags': requiredTags,
    'minimumRating': minimumRating,
    'unreadOnly': unreadOnly,
    'starredOnly': starredOnly,
  };

  factory LiteratureCollection.fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Collection must be an object.');
    }
    final map = <String, Object?>{
      for (final item in value.entries)
        if (item.key is String) item.key! as String: item.value,
    };
    final id = map['id'];
    final name = map['name'];
    final createdAt = map['createdAt'];
    final kindName = map['kind'];
    if (id is! String ||
        name is! String ||
        createdAt is! String ||
        kindName is! String) {
      throw const FormatException('Collection fields are invalid.');
    }
    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (parsedCreatedAt == null) {
      throw const FormatException('Collection date is invalid.');
    }
    final tags = map['requiredTags'];
    if (tags != null &&
        (tags is! List<Object?> || tags.any((item) => item is! String))) {
      throw const FormatException('Collection tags are invalid.');
    }
    return LiteratureCollection(
      id: id,
      name: name,
      parentId: map['parentId'] as String?,
      createdAt: parsedCreatedAt.toUtc(),
      kind: LiteratureCollectionKind.values.byName(kindName),
      query: map['query'] as String? ?? '',
      requiredTags: tags == null
          ? const <String>[]
          : List<String>.unmodifiable((tags as List<Object?>).cast<String>()),
      minimumRating: map['minimumRating'] as int? ?? 0,
      unreadOnly: map['unreadOnly'] as bool? ?? false,
      starredOnly: map['starredOnly'] as bool? ?? false,
    );
  }

  static String createId(String name, DateTime createdAt) {
    final normalized = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'collection-${normalized.isEmpty ? 'library' : normalized}-${createdAt.microsecondsSinceEpoch}';
  }
}

abstract interface class LiteratureCollectionStore {
  Future<List<LiteratureCollection>> load();

  Future<void> save(List<LiteratureCollection> collections);
}

final class InMemoryLiteratureCollectionStore
    implements LiteratureCollectionStore {
  InMemoryLiteratureCollectionStore([
    Iterable<LiteratureCollection> initial = const <LiteratureCollection>[],
  ]) : _collections = List<LiteratureCollection>.of(initial);

  List<LiteratureCollection> _collections;

  @override
  Future<List<LiteratureCollection>> load() async =>
      List<LiteratureCollection>.unmodifiable(_collections);

  @override
  Future<void> save(List<LiteratureCollection> collections) async {
    _collections = List<LiteratureCollection>.of(collections);
  }
}

final class SqliteLiteratureCollectionStore
    implements LiteratureCollectionStore {
  const SqliteLiteratureCollectionStore(this.catalogPath);

  final String catalogPath;

  @override
  Future<List<LiteratureCollection>> load() async {
    final database = _open();
    try {
      return List<LiteratureCollection>.unmodifiable(
        database
            .select(
              'SELECT payload_json FROM literature_collections '
              'ORDER BY sort_index',
            )
            .map(
              (row) => LiteratureCollection.fromJson(
                jsonDecode(row['payload_json']! as String),
              ),
            ),
      );
    } finally {
      database.close();
    }
  }

  @override
  Future<void> save(List<LiteratureCollection> collections) async {
    final database = _open();
    PreparedStatement? insert;
    try {
      database.execute('BEGIN IMMEDIATE');
      database.execute('DELETE FROM literature_collections');
      insert = database.prepare(
        'INSERT INTO literature_collections '
        '(collection_id, sort_index, payload_json) VALUES (?, ?, ?)',
      );
      for (var index = 0; index < collections.length; index++) {
        final collection = collections[index];
        insert.execute(<Object?>[
          collection.id,
          index,
          jsonEncode(collection.toJson()),
        ]);
      }
      database.execute('COMMIT');
    } on Object {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    } finally {
      insert?.close();
      database.close();
    }
  }

  Database _open() {
    final file = File(catalogPath);
    file.parent.createSync(recursive: true);
    final database = sqlite3.open(catalogPath);
    database.execute('''
      CREATE TABLE IF NOT EXISTS literature_collections (
        collection_id TEXT PRIMARY KEY NOT NULL,
        sort_index INTEGER NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');
    return database;
  }
}

final class LiteratureLibraryOrganizer {
  const LiteratureLibraryOrganizer();

  List<LiteratureLibraryEntry> apply({
    required Iterable<LiteratureLibraryEntry> entries,
    String query = '',
    LiteratureCollection? collection,
    LiteratureSortMode sortMode = LiteratureSortMode.addedNewest,
    bool trash = false,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final result = entries
        .where((entry) {
          if (entry.isTrashed != trash) return false;
          if (collection != null && !collection.matches(entry)) return false;
          return normalizedQuery.isEmpty ||
              searchableText(entry).contains(normalizedQuery);
        })
        .toList(growable: false);
    result.sort((left, right) => _compare(left, right, sortMode));
    return List<LiteratureLibraryEntry>.unmodifiable(result);
  }

  static String searchableText(LiteratureLibraryEntry entry) => <String>[
    entry.record.title,
    ...entry.record.authors,
    entry.record.journal,
    entry.record.doi ?? '',
    ...entry.record.tags,
    ...entry.record.keywords,
    entry.fileName,
  ].join('\n').toLowerCase();

  static int _compare(
    LiteratureLibraryEntry left,
    LiteratureLibraryEntry right,
    LiteratureSortMode mode,
  ) {
    final result = switch (mode) {
      LiteratureSortMode.addedNewest => right.addedAt.compareTo(left.addedAt),
      LiteratureSortMode.title => _text(
        left.record.title,
      ).compareTo(_text(right.record.title)),
      LiteratureSortMode.firstAuthor => _text(
        left.record.authors.firstOrNull ?? '',
      ).compareTo(_text(right.record.authors.firstOrNull ?? '')),
      LiteratureSortMode.yearNewest => (right.record.year ?? -1).compareTo(
        left.record.year ?? -1,
      ),
      LiteratureSortMode.rating => right.rating.compareTo(left.rating),
      LiteratureSortMode.readingProgress =>
        right.record.readingProgress.compareTo(left.record.readingProgress),
    };
    return result != 0 ? result : left.id.compareTo(right.id);
  }

  static String _text(String value) => value.trim().toLowerCase();
}
