import 'dart:async';
import 'dart:collection';

import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';

typedef MobileIndexBatchLoader =
    Future<AndroidMediaPage> Function(AndroidMediaQuery query);

final class MobileIndexQueueSnapshot {
  const MobileIndexQueueSnapshot({
    required this.pendingBatches,
    required this.isRunning,
    required this.completedBatches,
    required this.failedBatches,
    required this.pageSize,
    required this.maxPendingBatches,
    this.indexedItems = 0,
    this.persistsAcrossRestarts = false,
    this.isPaused = false,
  });

  final int pendingBatches;
  final bool isRunning;
  final int completedBatches;
  final int failedBatches;
  final int pageSize;
  final int maxPendingBatches;
  final int indexedItems;
  final bool persistsAcrossRestarts;
  final bool isPaused;

  bool get schedulesOcr => false;
}

final class MobileIndexCheckpoint {
  const MobileIndexCheckpoint({
    required this.offset,
    required this.modifiedAfterEpochSeconds,
    required this.passLatestEpochSeconds,
    required this.indexedItems,
  });

  final int offset;
  final int? modifiedAfterEpochSeconds;
  final int? passLatestEpochSeconds;
  final int indexedItems;
}

abstract interface class MobileIndexCheckpointStore {
  bool get persistsAcrossRestarts;

  Future<MobileIndexCheckpoint?> loadCheckpoint(AndroidMediaKind kind);

  Future<void> saveCheckpoint(
    AndroidMediaKind kind,
    MobileIndexCheckpoint checkpoint,
  );
}

/// Bounded incremental metadata work with an optional durable checkpoint.
///
/// It intentionally processes one MediaStore page at a time. By default,
/// collections with more data return to the end of the queue so other
/// authorized kinds get a fair turn. Once a pass reaches the end, later work
/// resumes strictly after the latest observed modification timestamp. The
/// checkpoint is saved only after the page loader completes. Cancellation
/// finishes the current bounded page and prevents another one. The queue never
/// schedules OCR.
final class MobileIncrementalIndexQueue {
  MobileIncrementalIndexQueue({
    required this.loader,
    this.checkpointStore,
    this.autoContinue = true,
    this.pageSize = 40,
    this.maxPendingBatches = 4,
  }) {
    if (pageSize < 1 || pageSize > 100) {
      throw RangeError.range(pageSize, 1, 100, 'pageSize');
    }
    if (maxPendingBatches < 1 || maxPendingBatches > 8) {
      throw RangeError.range(maxPendingBatches, 1, 8, 'maxPendingBatches');
    }
  }

  final MobileIndexBatchLoader loader;
  final MobileIndexCheckpointStore? checkpointStore;
  final bool autoContinue;
  final int pageSize;
  final int maxPendingBatches;
  final Queue<AndroidMediaKind> _pending = Queue<AndroidMediaKind>();
  final Set<AndroidMediaKind> _scheduled = <AndroidMediaKind>{};
  final Map<AndroidMediaKind, int> _modifiedAfter = <AndroidMediaKind, int>{};
  final Map<AndroidMediaKind, int> _offsets = <AndroidMediaKind, int>{};
  final Map<AndroidMediaKind, int> _passLatest = <AndroidMediaKind, int>{};
  final Map<AndroidMediaKind, int> _indexedItems = <AndroidMediaKind, int>{};
  final Set<AndroidMediaKind> _hydrated = <AndroidMediaKind>{};
  bool _isRunning = false;
  bool _cancelRequested = false;
  int _completedBatches = 0;
  int _failedBatches = 0;
  Completer<void>? _idleCompleter;

  MobileIndexQueueSnapshot get snapshot => MobileIndexQueueSnapshot(
    pendingBatches: _pending.length,
    isRunning: _isRunning,
    completedBatches: _completedBatches,
    failedBatches: _failedBatches,
    pageSize: pageSize,
    maxPendingBatches: maxPendingBatches,
    indexedItems: _indexedItems.values.fold(0, (total, value) => total + value),
    persistsAcrossRestarts: checkpointStore?.persistsAcrossRestarts ?? false,
    isPaused: _cancelRequested,
  );

  bool enqueue(AndroidMediaKind kind) {
    if (_scheduled.contains(kind) || _pending.length >= maxPendingBatches) {
      return false;
    }
    _cancelRequested = false;
    _pending.addLast(kind);
    _scheduled.add(kind);
    _idleCompleter ??= Completer<void>();
    if (!_isRunning) scheduleMicrotask(_drain);
    return true;
  }

  Future<void> get idle => _idleCompleter?.future ?? Future<void>.value();

  void cancel() {
    _cancelRequested = true;
    _pending.clear();
    _scheduled.clear();
    if (!_isRunning) {
      _idleCompleter?.complete();
      _idleCompleter = null;
    }
  }

  Future<void> _drain() async {
    if (_isRunning) return;
    _isRunning = true;
    while (_pending.isNotEmpty) {
      final kind = _pending.removeFirst();
      var shouldContinue = false;
      try {
        await _hydrate(kind);
        final page = await loader(
          AndroidMediaQuery(
            kind: kind,
            limit: pageSize,
            offset: _offsets[kind] ?? 0,
            modifiedAfterEpochSeconds: _modifiedAfter[kind],
          ),
        );
        final latestEpoch = page.items.fold<int>(
          _passLatest[kind] ?? _modifiedAfter[kind] ?? 0,
          (latest, item) {
            final candidate = item.modifiedAt.millisecondsSinceEpoch ~/ 1000;
            return candidate > latest ? candidate : latest;
          },
        );
        var nextOffset = 0;
        var nextModifiedAfter = _modifiedAfter[kind];
        int? nextPassLatest = latestEpoch > 0 ? latestEpoch : null;
        if (page.hasMore && page.items.isNotEmpty) {
          nextOffset = (_offsets[kind] ?? 0) + page.items.length;
        } else {
          final completedPassLatest = nextPassLatest;
          if (completedPassLatest != null) {
            nextModifiedAfter = completedPassLatest;
          }
          nextPassLatest = null;
        }

        final nextIndexedItems = (_indexedItems[kind] ?? 0) + page.items.length;
        final checkpoint = MobileIndexCheckpoint(
          offset: nextOffset,
          modifiedAfterEpochSeconds: nextModifiedAfter,
          passLatestEpochSeconds: nextPassLatest,
          indexedItems: nextIndexedItems,
        );
        await checkpointStore?.saveCheckpoint(kind, checkpoint);
        _applyCheckpoint(kind, checkpoint);
        shouldContinue = autoContinue && page.hasMore && page.items.isNotEmpty;
        _completedBatches += 1;
      } catch (_) {
        _failedBatches += 1;
      } finally {
        _scheduled.remove(kind);
      }
      if (shouldContinue && !_cancelRequested) {
        _pending.addLast(kind);
        _scheduled.add(kind);
      }
    }
    _isRunning = false;
    _idleCompleter?.complete();
    _idleCompleter = null;
  }

  Future<void> _hydrate(AndroidMediaKind kind) async {
    if (_hydrated.contains(kind)) return;
    try {
      final checkpoint = await checkpointStore?.loadCheckpoint(kind);
      if (checkpoint != null) _applyCheckpoint(kind, checkpoint);
      _hydrated.add(kind);
    } catch (_) {
      _hydrated.remove(kind);
      rethrow;
    }
  }

  void _applyCheckpoint(
    AndroidMediaKind kind,
    MobileIndexCheckpoint checkpoint,
  ) {
    if (checkpoint.offset < 0 ||
        checkpoint.indexedItems < 0 ||
        (checkpoint.modifiedAfterEpochSeconds ?? 0) < 0 ||
        (checkpoint.passLatestEpochSeconds ?? 0) < 0) {
      throw const FormatException('The Mobile index checkpoint is invalid.');
    }
    if (checkpoint.offset > 0) {
      _offsets[kind] = checkpoint.offset;
    } else {
      _offsets.remove(kind);
    }
    if (checkpoint.modifiedAfterEpochSeconds case final value?) {
      _modifiedAfter[kind] = value;
    } else {
      _modifiedAfter.remove(kind);
    }
    if (checkpoint.passLatestEpochSeconds case final value?) {
      _passLatest[kind] = value;
    } else {
      _passLatest.remove(kind);
    }
    _indexedItems[kind] = checkpoint.indexedItems;
  }
}
