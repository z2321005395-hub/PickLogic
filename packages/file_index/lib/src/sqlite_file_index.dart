import 'dart:convert';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:sqlite3/sqlite3.dart';

final class IncrementalScanSession {
  const IncrementalScanSession({
    required this.rootKey,
    required this.generation,
  });

  final String rootKey;
  final int generation;
}

final class IncrementalBatchResult {
  const IncrementalBatchResult({
    required this.insertedCount,
    required this.updatedCount,
    required this.unchangedCount,
  });

  final int insertedCount;
  final int updatedCount;
  final int unchangedCount;

  int get changedCount => insertedCount + updatedCount;
}

final class IncrementalScanCompletion {
  IncrementalScanCompletion({required Iterable<String> removedIds})
    : removedIds = List<String>.unmodifiable(removedIds);

  final List<String> removedIds;
}

final class SqliteFileIndex implements SearchIndexer {
  factory SqliteFileIndex.open(String path) =>
      SqliteFileIndex._(sqlite3.open(path));

  factory SqliteFileIndex.inMemory() =>
      SqliteFileIndex._(sqlite3.openInMemory());

  SqliteFileIndex._(this._database) {
    _migrate();
  }

  final Database _database;
  bool _closed = false;

  void _migrate() {
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS file_records (
        id TEXT PRIMARY KEY,
        locator_value TEXT NOT NULL,
        locator_source_kind TEXT NOT NULL,
        locator_platform TEXT NOT NULL,
        display_name TEXT NOT NULL,
        extension TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        created_at_ms INTEGER,
        modified_at_ms INTEGER NOT NULL,
        parent_value TEXT,
        parent_source_kind TEXT,
        parent_platform TEXT,
        source_kind TEXT NOT NULL,
        platform TEXT NOT NULL,
        is_hidden INTEGER NOT NULL,
        is_system INTEGER NOT NULL,
        is_accessible INTEGER NOT NULL,
        is_protected INTEGER NOT NULL,
        category TEXT NOT NULL,
        tags_json TEXT NOT NULL,
        hash_state TEXT NOT NULL,
        sha256 TEXT,
        perceptual_hash TEXT,
        ocr_state TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE INDEX IF NOT EXISTS idx_file_records_modified
      ON file_records(modified_at_ms)
    ''');
    _database.execute('''
      CREATE INDEX IF NOT EXISTS idx_file_records_hash
      ON file_records(size_bytes, sha256)
    ''');
    _database.execute('''
      CREATE INDEX IF NOT EXISTS idx_file_records_name
      ON file_records(display_name)
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS scan_state (
        root_key TEXT PRIMARY KEY,
        cursor TEXT,
        scanned_count INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        generation INTEGER NOT NULL DEFAULT 0,
        is_complete INTEGER NOT NULL DEFAULT 1
      )
    ''');
    final scanStateColumns = _database
        .select('PRAGMA table_info(scan_state)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!scanStateColumns.contains('generation')) {
      _database.execute(
        'ALTER TABLE scan_state '
        'ADD COLUMN generation INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!scanStateColumns.contains('is_complete')) {
      _database.execute(
        'ALTER TABLE scan_state '
        'ADD COLUMN is_complete INTEGER NOT NULL DEFAULT 1',
      );
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS scan_membership (
        root_key TEXT NOT NULL,
        file_id TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        seen_generation INTEGER NOT NULL,
        PRIMARY KEY(root_key, file_id),
        FOREIGN KEY(file_id) REFERENCES file_records(id) ON DELETE CASCADE
      )
    ''');
    _database.execute('''
      CREATE INDEX IF NOT EXISTS idx_scan_membership_file
      ON scan_membership(file_id)
    ''');
    _database.execute('PRAGMA user_version = 2');
  }

  @override
  Future<void> upsertBatch(List<FileRecord> records) async {
    _ensureOpen();
    if (records.isEmpty) return;
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final record in records) {
        _database.execute(_upsertSql, _recordParameters(record));
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> removeByIds(Iterable<String> ids) async {
    _ensureOpen();
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final id in ids) {
        _database.execute('DELETE FROM file_records WHERE id = ?', [id]);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  IncrementalScanSession beginIncrementalScan({required String rootKey}) {
    _ensureOpen();
    if (rootKey.trim().isEmpty) {
      throw ArgumentError.value(rootKey, 'rootKey', 'A root key is required.');
    }
    _database.execute('BEGIN IMMEDIATE');
    try {
      final existing = _database.select(
        'SELECT generation FROM scan_state WHERE root_key = ?',
        [rootKey],
      );
      final generation = existing.isEmpty
          ? 1
          : (existing.single['generation'] as int) + 1;
      _database.execute(
        '''
        INSERT INTO scan_state(
          root_key, cursor, scanned_count, updated_at_ms,
          generation, is_complete
        ) VALUES (?, NULL, 0, ?, ?, 0)
        ON CONFLICT(root_key) DO UPDATE SET
          cursor = NULL,
          scanned_count = 0,
          updated_at_ms = excluded.updated_at_ms,
          generation = excluded.generation,
          is_complete = 0
        ''',
        [rootKey, DateTime.now().toUtc().millisecondsSinceEpoch, generation],
      );
      _database.execute('COMMIT');
      return IncrementalScanSession(rootKey: rootKey, generation: generation);
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<IncrementalBatchResult> upsertIncrementalBatch({
    required IncrementalScanSession session,
    required List<FileRecord> records,
    required String? cursor,
    required int scannedCount,
  }) async {
    _ensureOpen();
    if (scannedCount < 0) {
      throw ArgumentError.value(
        scannedCount,
        'scannedCount',
        'The scanned count cannot be negative.',
      );
    }
    _database.execute('BEGIN IMMEDIATE');
    try {
      final state = _requireActiveSession(session);
      if (scannedCount < (state['scanned_count'] as int)) {
        throw StateError('The scan count cannot move backwards.');
      }
      var insertedCount = 0;
      var updatedCount = 0;
      var unchangedCount = 0;
      for (final record in records) {
        final fingerprint = _scanFingerprint(record);
        final membership = _database.select(
          '''
          SELECT fingerprint FROM scan_membership
          WHERE root_key = ? AND file_id = ?
          ''',
          [session.rootKey, record.id],
        );
        if (membership.isNotEmpty &&
            membership.single['fingerprint'] == fingerprint) {
          _database.execute(
            '''
            UPDATE scan_membership SET seen_generation = ?
            WHERE root_key = ? AND file_id = ?
            ''',
            [session.generation, session.rootKey, record.id],
          );
          unchangedCount += 1;
          continue;
        }

        final existed = _database.select(
          'SELECT 1 FROM file_records WHERE id = ? LIMIT 1',
          [record.id],
        ).isNotEmpty;
        _database.execute(_upsertSql, _recordParameters(record));
        _database.execute(
          '''
          INSERT INTO scan_membership(
            root_key, file_id, fingerprint, seen_generation
          ) VALUES (?, ?, ?, ?)
          ON CONFLICT(root_key, file_id) DO UPDATE SET
            fingerprint = excluded.fingerprint,
            seen_generation = excluded.seen_generation
          ''',
          [session.rootKey, record.id, fingerprint, session.generation],
        );
        if (existed) {
          updatedCount += 1;
        } else {
          insertedCount += 1;
        }
      }
      _database.execute(
        '''
        UPDATE scan_state SET
          cursor = ?, scanned_count = ?, updated_at_ms = ?
        WHERE root_key = ? AND generation = ?
        ''',
        [
          cursor,
          scannedCount,
          DateTime.now().toUtc().millisecondsSinceEpoch,
          session.rootKey,
          session.generation,
        ],
      );
      _database.execute('COMMIT');
      return IncrementalBatchResult(
        insertedCount: insertedCount,
        updatedCount: updatedCount,
        unchangedCount: unchangedCount,
      );
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  IncrementalScanCompletion completeIncrementalScan(
    IncrementalScanSession session,
  ) {
    _ensureOpen();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _requireActiveSession(session);
      final staleIds = _database
          .select(
            '''
            SELECT file_id FROM scan_membership
            WHERE root_key = ? AND seen_generation <> ?
            ORDER BY file_id
            ''',
            [session.rootKey, session.generation],
          )
          .map((row) => row['file_id'] as String)
          .toList(growable: false);
      _database.execute(
        '''
        DELETE FROM scan_membership
        WHERE root_key = ? AND seen_generation <> ?
        ''',
        [session.rootKey, session.generation],
      );
      final removedIds = <String>[];
      for (final id in staleIds) {
        final stillOwned = _database.select(
          'SELECT 1 FROM scan_membership WHERE file_id = ? LIMIT 1',
          [id],
        ).isNotEmpty;
        if (!stillOwned) {
          _database.execute('DELETE FROM file_records WHERE id = ?', [id]);
          removedIds.add(id);
        }
      }
      _database.execute(
        '''
        UPDATE scan_state SET is_complete = 1, updated_at_ms = ?
        WHERE root_key = ? AND generation = ?
        ''',
        [
          DateTime.now().toUtc().millisecondsSinceEpoch,
          session.rootKey,
          session.generation,
        ],
      );
      _database.execute('COMMIT');
      return IncrementalScanCompletion(removedIds: removedIds);
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<List<FileRecord>> search(String query, {int limit = 100}) async {
    _ensureOpen();
    if (limit <= 0) return const [];
    final terms = _searchTerms(query);
    if (terms.isEmpty) {
      final rows = _database.select(
        '''
        SELECT * FROM file_records
        ORDER BY modified_at_ms DESC, id ASC
        LIMIT ?
        ''',
        [limit],
      );
      return rows.map(_recordFromRow).toList(growable: false);
    }

    final scoreParts = <String>[];
    final whereParts = <String>[];
    final scoreParameters = <Object?>[];
    final whereParameters = <Object?>[];
    for (final term in terms) {
      final escaped = _escapeLike(term);
      final contains = '%$escaped%';
      final prefix = '$escaped%';
      scoreParts.add('''
        CASE
          WHEN lower(display_name) = ? THEN 100
          WHEN lower(display_name) LIKE ? ESCAPE '\\' THEN 60
          WHEN lower(display_name) LIKE ? ESCAPE '\\' THEN 40
          WHEN lower(extension) = ? OR lower(category) = ? THEN 25
          ELSE 10
        END
      ''');
      scoreParameters.addAll([term, prefix, contains, term, term]);
      whereParts.add('''
        (
          lower(display_name) LIKE ? ESCAPE '\\'
          OR lower(extension) LIKE ? ESCAPE '\\'
          OR lower(mime_type) LIKE ? ESCAPE '\\'
          OR lower(category) LIKE ? ESCAPE '\\'
          OR lower(tags_json) LIKE ? ESCAPE '\\'
        )
      ''');
      whereParameters.addAll(List<Object?>.filled(5, contains));
    }
    final rows = _database.select(
      '''
      SELECT *, (${scoreParts.join(' + ')}) AS rank_score
      FROM file_records
      WHERE ${whereParts.join(' AND ')}
      ORDER BY rank_score DESC, modified_at_ms DESC, id ASC
      LIMIT ?
      ''',
      [...scoreParameters, ...whereParameters, limit],
    );
    return rows.map(_recordFromRow).toList(growable: false);
  }

  Future<void> saveScanState({
    required String rootKey,
    required String? cursor,
    required int scannedCount,
  }) async {
    _ensureOpen();
    _database.execute(
      '''
      INSERT INTO scan_state(root_key, cursor, scanned_count, updated_at_ms)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(root_key) DO UPDATE SET
        cursor = excluded.cursor,
        scanned_count = excluded.scanned_count,
        updated_at_ms = excluded.updated_at_ms
    ''',
      [
        rootKey,
        cursor,
        scannedCount,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  ({String? cursor, int scannedCount})? loadScanState(String rootKey) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT cursor, scanned_count FROM scan_state WHERE root_key = ?',
      [rootKey],
    );
    if (rows.isEmpty) return null;
    return (
      cursor: rows.single['cursor'] as String?,
      scannedCount: rows.single['scanned_count'] as int,
    );
  }

  Row _requireActiveSession(IncrementalScanSession session) {
    final rows = _database.select(
      '''
      SELECT generation, is_complete, scanned_count
      FROM scan_state WHERE root_key = ?
      ''',
      [session.rootKey],
    );
    if (rows.isEmpty ||
        rows.single['generation'] != session.generation ||
        rows.single['is_complete'] == 1) {
      throw StateError('The incremental scan session is not active.');
    }
    return rows.single;
  }

  int get count {
    _ensureOpen();
    return _database
            .select('SELECT COUNT(*) AS count FROM file_records')
            .single['count']
        as int;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _database.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('The file index is closed.');
  }

  static const String _upsertSql = '''
    INSERT INTO file_records(
      id, locator_value, locator_source_kind, locator_platform,
      display_name, extension, mime_type, size_bytes,
      created_at_ms, modified_at_ms,
      parent_value, parent_source_kind, parent_platform,
      source_kind, platform, is_hidden, is_system, is_accessible,
      is_protected, category, tags_json, hash_state, sha256,
      perceptual_hash, ocr_state
    ) VALUES (
      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
    )
    ON CONFLICT(id) DO UPDATE SET
      locator_value=excluded.locator_value,
      locator_source_kind=excluded.locator_source_kind,
      locator_platform=excluded.locator_platform,
      display_name=excluded.display_name,
      extension=excluded.extension,
      mime_type=excluded.mime_type,
      size_bytes=excluded.size_bytes,
      created_at_ms=excluded.created_at_ms,
      modified_at_ms=excluded.modified_at_ms,
      parent_value=excluded.parent_value,
      parent_source_kind=excluded.parent_source_kind,
      parent_platform=excluded.parent_platform,
      source_kind=excluded.source_kind,
      platform=excluded.platform,
      is_hidden=excluded.is_hidden,
      is_system=excluded.is_system,
      is_accessible=excluded.is_accessible,
      is_protected=excluded.is_protected,
      category=excluded.category,
      tags_json=excluded.tags_json,
      hash_state=excluded.hash_state,
      sha256=excluded.sha256,
      perceptual_hash=excluded.perceptual_hash,
      ocr_state=excluded.ocr_state
  ''';

  List<Object?> _recordParameters(FileRecord record) => [
    record.id,
    record.locator.value,
    record.locator.sourceKind.name,
    record.locator.platform.name,
    record.displayName,
    record.extension,
    record.mimeType,
    record.sizeBytes,
    record.createdAt?.millisecondsSinceEpoch,
    record.modifiedAt.millisecondsSinceEpoch,
    record.parentLocator?.value,
    record.parentLocator?.sourceKind.name,
    record.parentLocator?.platform.name,
    record.sourceKind.name,
    record.platform.name,
    record.isHidden ? 1 : 0,
    record.isSystem ? 1 : 0,
    record.isAccessible ? 1 : 0,
    record.isProtected ? 1 : 0,
    record.category.name,
    jsonEncode(record.tags),
    record.hashState.name,
    record.sha256,
    record.perceptualHash,
    record.ocrState.name,
  ];

  FileRecord _recordFromRow(Row row) {
    final parentValue = row['parent_value'] as String?;
    return FileRecord(
      id: row['id'] as String,
      locator: FileLocator(
        value: row['locator_value'] as String,
        sourceKind: SourceKind.values.byName(
          row['locator_source_kind'] as String,
        ),
        platform: PickLogicPlatform.values.byName(
          row['locator_platform'] as String,
        ),
      ),
      displayName: row['display_name'] as String,
      extension: row['extension'] as String,
      mimeType: row['mime_type'] as String,
      sizeBytes: row['size_bytes'] as int,
      createdAt: _dateTime(row['created_at_ms'] as int?),
      modifiedAt: _dateTime(row['modified_at_ms'] as int)!,
      parentLocator: parentValue == null
          ? null
          : FileLocator(
              value: parentValue,
              sourceKind: SourceKind.values.byName(
                row['parent_source_kind'] as String,
              ),
              platform: PickLogicPlatform.values.byName(
                row['parent_platform'] as String,
              ),
            ),
      sourceKind: SourceKind.values.byName(row['source_kind'] as String),
      platform: PickLogicPlatform.values.byName(row['platform'] as String),
      isHidden: row['is_hidden'] == 1,
      isSystem: row['is_system'] == 1,
      isAccessible: row['is_accessible'] == 1,
      isProtected: row['is_protected'] == 1,
      category: VirtualCategory.values.byName(row['category'] as String),
      tags: List<String>.from(jsonDecode(row['tags_json'] as String) as List),
      hashState: HashState.values.byName(row['hash_state'] as String),
      sha256: row['sha256'] as String?,
      perceptualHash: row['perceptual_hash'] as String?,
      ocrState: OcrState.values.byName(row['ocr_state'] as String),
    );
  }

  DateTime? _dateTime(int? milliseconds) => milliseconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

String _scanFingerprint(FileRecord record) => jsonEncode([
  record.locator.value,
  record.locator.sourceKind.name,
  record.locator.platform.name,
  record.displayName,
  record.extension,
  record.mimeType,
  record.sizeBytes,
  record.createdAt?.toUtc().millisecondsSinceEpoch,
  record.modifiedAt.toUtc().millisecondsSinceEpoch,
  record.parentLocator?.value,
  record.parentLocator?.sourceKind.name,
  record.parentLocator?.platform.name,
  record.sourceKind.name,
  record.platform.name,
  record.isHidden,
  record.isSystem,
  record.isAccessible,
  record.isProtected,
  record.category.name,
  record.tags,
]);

List<String> _searchTerms(String query) {
  final seen = <String>{};
  return query
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true))
      .where((term) => term.isNotEmpty && seen.add(term))
      .toList(growable: false);
}

String _escapeLike(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
