import 'dart:io';

import 'package:picklogic_classification_rules/picklogic_classification_rules.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_duplicate_engine/picklogic_duplicate_engine.dart';
import 'package:picklogic_file_index/picklogic_file_index.dart';
import 'package:picklogic_search_index/picklogic_search_index.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

import 'demo_records.dart';

final class DesktopScanProgress {
  const DesktopScanProgress({
    required this.records,
    required this.scannedCount,
    required this.complete,
    required this.rootLabel,
    this.removedIds = const <String>[],
  });

  final List<FileRecord> records;
  final int scannedCount;
  final bool complete;
  final String rootLabel;
  final List<String> removedIds;
}

abstract interface class DesktopRepository {
  Stream<DesktopScanProgress> chooseAndScan();

  Future<void> cancelScan();

  Future<bool> open(FileRecord record);

  Future<bool> reveal(FileRecord record);

  Future<List<FileRecord>> search(String query);

  Future<ExactDuplicateScanResult> findExactDuplicates(
    Iterable<FileRecord> records,
  );

  Future<WindowsStorageSummary?> systemDriveSummary();
}

final class WindowsDesktopRepository implements DesktopRepository {
  WindowsDesktopRepository({
    this.bridge = const PicklogicWindowsBridge(),
    StreamingDirectoryScanner? scanner,
    RuleClassificationEngine? classifier,
    Sha256DuplicateDetector? duplicateDetector,
    SqliteFileIndex Function()? indexFactory,
  }) : _scanner = scanner ?? StreamingDirectoryScanner(),
       _classifier = classifier ?? RuleClassificationEngine(),
       _duplicateDetector = duplicateDetector ?? Sha256DuplicateDetector(),
       _index = indexFactory?.call();

  final PicklogicWindowsBridge bridge;
  final StreamingDirectoryScanner _scanner;
  final RuleClassificationEngine _classifier;
  final Sha256DuplicateDetector _duplicateDetector;
  SqliteFileIndex? _index;
  Set<String> _activeRecordIds = const <String>{};

  @override
  Stream<DesktopScanProgress> chooseAndScan() async* {
    final rootPath = await bridge.pickDirectory(title: 'PickLogic · 选择只读扫描目录');
    if (rootPath == null) return;
    _activeRecordIds = <String>{};
    final root = FileLocator(
      value: rootPath,
      sourceKind: SourceKind.fileSystem,
      platform: PickLogicPlatform.windows,
    );
    final index = await _openIndex();
    final rootLabel = _basename(rootPath);
    final session = index.beginIncrementalScan(rootKey: _rootKey(rootPath));
    await for (final batch in _scanner.scan(ScanRequest(root: root))) {
      final records = batch.records
          .map(_classifier.classify)
          .toList(growable: false);
      _activeRecordIds.addAll(records.map((record) => record.id));
      await index.upsertIncrementalBatch(
        session: session,
        records: records,
        cursor: batch.cursor,
        scannedCount: batch.scannedCount,
      );
      final completion = batch.isComplete
          ? index.completeIncrementalScan(session)
          : null;
      if (completion != null) {
        _activeRecordIds.removeAll(completion.removedIds);
      }
      yield DesktopScanProgress(
        records: records,
        scannedCount: batch.scannedCount,
        complete: batch.isComplete,
        rootLabel: rootLabel,
        removedIds: completion?.removedIds ?? const <String>[],
      );
    }
  }

  @override
  Future<void> cancelScan() => _scanner.cancel();

  @override
  Future<bool> open(FileRecord record) => bridge.openItem(record.locator.value);

  @override
  Future<bool> reveal(FileRecord record) =>
      bridge.revealItem(record.locator.value);

  @override
  Future<List<FileRecord>> search(String query) async {
    final index = await _openIndex();
    final results = await index.search(query);
    return results
        .where((record) => _activeRecordIds.contains(record.id))
        .toList(growable: false);
  }

  @override
  Future<ExactDuplicateScanResult> findExactDuplicates(
    Iterable<FileRecord> records,
  ) => _duplicateDetector.findExactFiles(records);

  @override
  Future<WindowsStorageSummary?> systemDriveSummary() async =>
      bridge.getSystemDriveSummary();

  Future<SqliteFileIndex> _openIndex() async {
    final existing = _index;
    if (existing != null) return existing;
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      _index = SqliteFileIndex.inMemory();
      return _index!;
    }
    final directory = Directory(
      '$localAppData${Platform.pathSeparator}PickLogic',
    );
    await directory.create(recursive: true);
    _index = SqliteFileIndex.open(
      '${directory.path}${Platform.pathSeparator}index-v1.sqlite3',
    );
    return _index!;
  }
}

final class SyntheticDesktopRepository implements DesktopRepository {
  const SyntheticDesktopRepository();

  @override
  Stream<DesktopScanProgress> chooseAndScan() async* {
    final records = syntheticDesktopRecords();
    yield DesktopScanProgress(
      records: records,
      scannedCount: records.length,
      complete: true,
      rootLabel: 'Synthetic fixtures',
    );
  }

  @override
  Future<void> cancelScan() async {}

  @override
  Future<bool> open(FileRecord record) async => true;

  @override
  Future<bool> reveal(FileRecord record) async => true;

  @override
  Future<List<FileRecord>> search(String query) async {
    final index = InMemorySearchIndex();
    await index.upsertBatch(syntheticDesktopRecords());
    return index.search(query);
  }

  @override
  Future<ExactDuplicateScanResult> findExactDuplicates(
    Iterable<FileRecord> records,
  ) async {
    final source = records.toList(growable: false);
    return ExactDuplicateScanResult(
      records: source,
      groups: const <List<FileRecord>>[],
      hashedCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<WindowsStorageSummary?> systemDriveSummary() async =>
      const WindowsStorageSummary(
        root: 'synthetic',
        totalBytes: 1000000,
        availableBytes: 420000,
      );
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _rootKey(String path) {
  final normalized = Directory(path).absolute.path.replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
