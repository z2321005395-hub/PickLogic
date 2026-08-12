import 'dart:convert';

import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:sqlite3/sqlite3.dart';

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
      CREATE TABLE IF NOT EXISTS scan_state (
        root_key TEXT PRIMARY KEY,
        cursor TEXT,
        scanned_count INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('PRAGMA user_version = 1');
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

  @override
  Future<List<FileRecord>> search(String query, {int limit = 100}) async {
    _ensureOpen();
    if (limit <= 0) return const [];
    final normalized = query.trim().toLowerCase();
    final rows = normalized.isEmpty
        ? _database.select(
            'SELECT * FROM file_records ORDER BY modified_at_ms DESC LIMIT ?',
            [limit],
          )
        : _database.select(
            '''
            SELECT * FROM file_records
            WHERE lower(display_name) LIKE ?
               OR lower(extension) LIKE ?
               OR lower(mime_type) LIKE ?
               OR lower(category) LIKE ?
               OR lower(tags_json) LIKE ?
            ORDER BY modified_at_ms DESC
            LIMIT ?
            ''',
            <Object?>[
              for (var index = 0; index < 5; index++) '%$normalized%',
              limit,
            ],
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
