import 'dart:convert';

import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_file_index/picklogic_file_index.dart';

import 'incremental_index_queue.dart';

abstract interface class MobileIndexPersistence
    implements MobileIndexCheckpointStore {
  Future<void> upsertRecords(List<FileRecord> records);

  Future<void> removeRecords(Iterable<String> ids);

  Future<List<FileRecord>> search(String query, {int limit = 100});

  Future<void> close();
}

final class SqliteMobileIndexPersistence implements MobileIndexPersistence {
  factory SqliteMobileIndexPersistence.open(String path) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(
        path,
        'path',
        'A private index path is required.',
      );
    }
    return SqliteMobileIndexPersistence._(
      SqliteFileIndex.open(path),
      persistsAcrossRestarts: true,
    );
  }

  factory SqliteMobileIndexPersistence.inMemory() =>
      SqliteMobileIndexPersistence._(
        SqliteFileIndex.inMemory(),
        persistsAcrossRestarts: false,
      );

  SqliteMobileIndexPersistence._(
    this._index, {
    required this.persistsAcrossRestarts,
  });

  static const int _checkpointVersion = 1;
  final SqliteFileIndex _index;

  @override
  final bool persistsAcrossRestarts;

  @override
  Future<MobileIndexCheckpoint?> loadCheckpoint(AndroidMediaKind kind) async {
    final state = _index.loadScanState(_rootKey(kind));
    final cursor = state?.cursor;
    if (state == null || cursor == null) return null;
    try {
      final decoded = jsonDecode(cursor);
      if (decoded is! Map<String, Object?> ||
          decoded['version'] != _checkpointVersion) {
        return null;
      }
      final offset = decoded['offset'];
      final modifiedAfter = decoded['modifiedAfterEpochSeconds'];
      final passLatest = decoded['passLatestEpochSeconds'];
      if (offset is! int ||
          offset < 0 ||
          (modifiedAfter != null && modifiedAfter is! int) ||
          (passLatest != null && passLatest is! int) ||
          state.scannedCount < 0) {
        return null;
      }
      return MobileIndexCheckpoint(
        offset: offset,
        modifiedAfterEpochSeconds: modifiedAfter as int?,
        passLatestEpochSeconds: passLatest as int?,
        indexedItems: state.scannedCount,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveCheckpoint(
    AndroidMediaKind kind,
    MobileIndexCheckpoint checkpoint,
  ) => _index.saveScanState(
    rootKey: _rootKey(kind),
    cursor: jsonEncode(<String, Object?>{
      'version': _checkpointVersion,
      'offset': checkpoint.offset,
      'modifiedAfterEpochSeconds': checkpoint.modifiedAfterEpochSeconds,
      'passLatestEpochSeconds': checkpoint.passLatestEpochSeconds,
    }),
    scannedCount: checkpoint.indexedItems,
  );

  @override
  Future<void> upsertRecords(List<FileRecord> records) =>
      _index.upsertBatch(records);

  @override
  Future<void> removeRecords(Iterable<String> ids) => _index.removeByIds(ids);

  @override
  Future<List<FileRecord>> search(String query, {int limit = 100}) =>
      _index.search(query, limit: limit);

  @override
  Future<void> close() async => _index.close();

  static String _rootKey(AndroidMediaKind kind) =>
      'android-mediastore:${kind.name}';
}

typedef MobileIndexPersistenceFactory =
    Future<MobileIndexPersistence> Function();

final class LazyMobileIndexPersistence implements MobileIndexPersistence {
  LazyMobileIndexPersistence(
    this._factory, {
    required this.persistsAcrossRestarts,
  });

  final MobileIndexPersistenceFactory _factory;
  Future<MobileIndexPersistence>? _delegate;

  @override
  final bool persistsAcrossRestarts;

  Future<MobileIndexPersistence> get _ready {
    final existing = _delegate;
    if (existing != null) return existing;
    final created = _createDelegate();
    _delegate = created;
    return created;
  }

  Future<MobileIndexPersistence> _createDelegate() async {
    try {
      return await _factory();
    } catch (_) {
      _delegate = null;
      rethrow;
    }
  }

  @override
  Future<MobileIndexCheckpoint?> loadCheckpoint(AndroidMediaKind kind) async =>
      (await _ready).loadCheckpoint(kind);

  @override
  Future<void> saveCheckpoint(
    AndroidMediaKind kind,
    MobileIndexCheckpoint checkpoint,
  ) async => (await _ready).saveCheckpoint(kind, checkpoint);

  @override
  Future<void> upsertRecords(List<FileRecord> records) async =>
      (await _ready).upsertRecords(records);

  @override
  Future<void> removeRecords(Iterable<String> ids) async =>
      (await _ready).removeRecords(ids);

  @override
  Future<List<FileRecord>> search(String query, {int limit = 100}) async =>
      (await _ready).search(query, limit: limit);

  @override
  Future<void> close() async {
    final delegate = _delegate;
    if (delegate == null) return;
    late final MobileIndexPersistence instance;
    try {
      instance = await delegate;
    } catch (_) {
      return;
    }
    await instance.close();
  }
}
