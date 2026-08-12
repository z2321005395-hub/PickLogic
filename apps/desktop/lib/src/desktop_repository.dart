import 'dart:io';

import 'package:picklogic_classification_rules/picklogic_classification_rules.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_file_index/picklogic_file_index.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

import 'demo_records.dart';

final class DesktopScanProgress {
  const DesktopScanProgress({
    required this.records,
    required this.scannedCount,
    required this.complete,
    required this.rootLabel,
  });

  final List<FileRecord> records;
  final int scannedCount;
  final bool complete;
  final String rootLabel;
}

abstract interface class DesktopRepository {
  Stream<DesktopScanProgress> chooseAndScan();

  Future<void> cancelScan();

  Future<bool> open(FileRecord record);

  Future<bool> reveal(FileRecord record);

  Future<List<FileRecord>> search(String query);

  Future<WindowsStorageSummary?> systemDriveSummary();
}

final class WindowsDesktopRepository implements DesktopRepository {
  WindowsDesktopRepository({
    this.bridge = const PicklogicWindowsBridge(),
    StreamingDirectoryScanner? scanner,
    RuleClassificationEngine? classifier,
  }) : _scanner = scanner ?? StreamingDirectoryScanner(),
       _classifier = classifier ?? RuleClassificationEngine();

  final PicklogicWindowsBridge bridge;
  final StreamingDirectoryScanner _scanner;
  final RuleClassificationEngine _classifier;
  SqliteFileIndex? _index;

  @override
  Stream<DesktopScanProgress> chooseAndScan() async* {
    final rootPath = await bridge.pickDirectory(title: 'PickLogic · 选择只读扫描目录');
    if (rootPath == null) return;
    final root = FileLocator(
      value: rootPath,
      sourceKind: SourceKind.fileSystem,
      platform: PickLogicPlatform.windows,
    );
    final index = await _openIndex();
    final rootLabel = _basename(rootPath);
    await for (final batch in _scanner.scan(ScanRequest(root: root))) {
      final records = batch.records
          .map(_classifier.classify)
          .toList(growable: false);
      await index.upsertBatch(records);
      await index.saveScanState(
        rootKey: _rootKey(rootPath),
        cursor: batch.cursor,
        scannedCount: batch.scannedCount,
      );
      yield DesktopScanProgress(
        records: records,
        scannedCount: batch.scannedCount,
        complete: batch.isComplete,
        rootLabel: rootLabel,
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
    final index = _index;
    return index == null ? const <FileRecord>[] : index.search(query);
  }

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
    final normalized = query.trim().toLowerCase();
    return syntheticDesktopRecords()
        .where(
          (record) => record.displayName.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
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
