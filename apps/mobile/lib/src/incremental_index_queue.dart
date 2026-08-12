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
  });

  final int pendingBatches;
  final bool isRunning;
  final int completedBatches;
  final int failedBatches;
  final int pageSize;
  final int maxPendingBatches;

  bool get schedulesOcr => false;
  bool get persistsAcrossRestarts => false;
}

/// A process-local skeleton for bounded incremental metadata work.
///
/// It intentionally processes one MediaStore page per queued collection. A
/// subsequent enqueue continues the next bounded page; after that bounded pass
/// reaches the end, later work resumes strictly after the latest observed
/// modification timestamp. It never follows [AndroidMediaPage.hasMore]
/// automatically and it never schedules OCR.
final class MobileIncrementalIndexQueue {
  MobileIncrementalIndexQueue({
    required this.loader,
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
  final int pageSize;
  final int maxPendingBatches;
  final Queue<AndroidMediaKind> _pending = Queue<AndroidMediaKind>();
  final Set<AndroidMediaKind> _scheduled = <AndroidMediaKind>{};
  final Map<AndroidMediaKind, int> _modifiedAfter = <AndroidMediaKind, int>{};
  final Map<AndroidMediaKind, int> _offsets = <AndroidMediaKind, int>{};
  final Map<AndroidMediaKind, int> _passLatest = <AndroidMediaKind, int>{};
  bool _isRunning = false;
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
  );

  bool enqueue(AndroidMediaKind kind) {
    if (_scheduled.contains(kind) || _pending.length >= maxPendingBatches) {
      return false;
    }
    _pending.addLast(kind);
    _scheduled.add(kind);
    _idleCompleter ??= Completer<void>();
    if (!_isRunning) scheduleMicrotask(_drain);
    return true;
  }

  Future<void> get idle => _idleCompleter?.future ?? Future<void>.value();

  Future<void> _drain() async {
    if (_isRunning) return;
    _isRunning = true;
    while (_pending.isNotEmpty) {
      final kind = _pending.removeFirst();
      try {
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
        if (latestEpoch > 0) _passLatest[kind] = latestEpoch;
        if (page.hasMore && page.items.isNotEmpty) {
          _offsets[kind] = (_offsets[kind] ?? 0) + page.items.length;
        } else {
          _offsets.remove(kind);
          final completedPassLatest = _passLatest.remove(kind);
          if (completedPassLatest != null) {
            _modifiedAfter[kind] = completedPassLatest;
          }
        }
        _completedBatches += 1;
      } catch (_) {
        _failedBatches += 1;
      } finally {
        _scheduled.remove(kind);
      }
    }
    _isRunning = false;
    _idleCompleter?.complete();
    _idleCompleter = null;
  }
}
