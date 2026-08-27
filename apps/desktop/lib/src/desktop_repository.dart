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

final class BrowseEntry {
  const BrowseEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.category,
    this.record,
  });

  final String id;
  final String path;
  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final VirtualCategory category;
  final FileRecord? record;
}

final class BrowseCrumb {
  const BrowseCrumb({required this.label, required this.path});

  final String label;
  final String path;
}

final class DirectorySnapshot {
  const DirectorySnapshot({
    required this.path,
    required this.parentPath,
    required this.crumbs,
    required this.entries,
    required this.truncated,
  });

  final String path;
  final String? parentPath;
  final List<BrowseCrumb> crumbs;
  final List<BrowseEntry> entries;
  final bool truncated;
}

/// One-pass direct-child summary for read-only Folder Insight traversal.
final class DesktopDirectoryInspection {
  const DesktopDirectoryInspection({
    required this.path,
    required this.displayName,
    required this.directories,
    required this.directFileCount,
    required this.directFileBytes,
    required this.mimeFamilyCounts,
  });

  final String path;
  final String displayName;
  final List<BrowseEntry> directories;
  final int directFileCount;
  final int directFileBytes;
  final Map<String, int> mimeFamilyCounts;

  int get directDirectoryCount => directories.length;
}

abstract interface class DesktopRepository {
  Future<List<WindowsBrowseRoot>> browseRoots();

  Future<DirectorySnapshot> browseDirectory(
    String path, {
    int maxEntries = 1000,
  });

  Future<String?> chooseBrowseFolder({required bool chinese});

  Future<bool> openBrowseEntry(BrowseEntry entry);

  Future<bool> revealBrowseEntry(BrowseEntry entry);

  Stream<DesktopScanProgress> indexCommonFolders();

  Stream<DesktopScanProgress> chooseAndScan();

  Future<void> cancelScan();

  Future<bool> open(FileRecord record);

  Future<bool> reveal(FileRecord record);

  Future<List<FileRecord>> search(String query);

  Future<ExactDuplicateScanResult> findExactDuplicates(
    Iterable<FileRecord> records,
  );

  Future<DesktopDirectoryInspection> inspectDirectory(String path);

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
  Set<String> _activeRecordIds = <String>{};

  @override
  Future<List<WindowsBrowseRoot>> browseRoots() => bridge.getBrowseRoots();

  @override
  Future<DirectorySnapshot> browseDirectory(
    String path, {
    int maxEntries = 1000,
  }) async {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
    }
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw FileSystemException('The directory is unavailable.', path);
    }
    final entries = <BrowseEntry>[];
    var truncated = false;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File && entity is! Directory) continue;
        if (entries.length >= maxEntries) {
          truncated = true;
          break;
        }
        final entry = await _browseEntry(entity);
        if (entry != null) entries.add(entry);
      }
    } on FileSystemException {
      rethrow;
    }
    entries.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return DirectorySnapshot(
      path: directory.absolute.path,
      parentPath: _parentPath(directory.absolute.path),
      crumbs: _crumbs(directory.absolute.path),
      entries: List<BrowseEntry>.unmodifiable(entries),
      truncated: truncated,
    );
  }

  @override
  Future<DesktopDirectoryInspection> inspectDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw FileSystemException('The directory is unavailable.', path);
    }
    final directories = <BrowseEntry>[];
    final families = <String, int>{};
    var directFileCount = 0;
    var directFileBytes = 0;
    await for (final entity in directory.list(followLinks: false)) {
      final entry = await _browseEntry(entity);
      if (entry == null) continue;
      if (entry.isDirectory) {
        directories.add(entry);
        continue;
      }
      directFileCount++;
      directFileBytes += entry.sizeBytes;
      final family = _desktopMimeFamily(entry.category);
      families.update(family, (count) => count + 1, ifAbsent: () => 1);
    }
    directories.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return DesktopDirectoryInspection(
      path: directory.absolute.path,
      displayName: _basename(directory.absolute.path),
      directories: List<BrowseEntry>.unmodifiable(directories),
      directFileCount: directFileCount,
      directFileBytes: directFileBytes,
      mimeFamilyCounts: Map<String, int>.unmodifiable(families),
    );
  }

  @override
  Future<String?> chooseBrowseFolder({required bool chinese}) =>
      bridge.pickDirectory(
        title: chinese ? '选择要添加的只读文件夹' : 'Choose a read-only folder to add',
      );

  @override
  Future<bool> openBrowseEntry(BrowseEntry entry) =>
      bridge.openItem(entry.path);

  @override
  Future<bool> revealBrowseEntry(BrowseEntry entry) =>
      bridge.revealItem(entry.path);

  @override
  Stream<DesktopScanProgress> indexCommonFolders() async* {
    final roots = await browseRoots();
    final commonRoots = roots.where(
      (root) =>
          root.kind == WindowsBrowseRootKind.desktop ||
          root.kind == WindowsBrowseRootKind.documents ||
          root.kind == WindowsBrowseRootKind.downloads,
    );
    final index = await _openIndex();
    for (final commonRoot in commonRoots) {
      final root = FileLocator(
        value: commonRoot.path,
        sourceKind: SourceKind.fileSystem,
        platform: PickLogicPlatform.windows,
      );
      final session = index.beginIncrementalScan(
        rootKey: _rootKey(commonRoot.path),
      );
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
          rootLabel: _basename(commonRoot.path),
          removedIds: completion?.removedIds ?? const <String>[],
        );
      }
    }
  }

  @override
  Stream<DesktopScanProgress> chooseAndScan() async* {
    final rootPath = await bridge.pickDirectory(
      title: 'Choose a folder for read-only indexing',
    );
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

  Future<BrowseEntry?> _browseEntry(FileSystemEntity entity) async {
    try {
      final stat = await entity.stat();
      final name = _basename(entity.path);
      if (entity is Directory) {
        return BrowseEntry(
          id: 'directory:${_normalizedPath(entity.path)}',
          path: entity.path,
          name: name,
          isDirectory: true,
          sizeBytes: 0,
          modifiedAt: stat.modified,
          category: VirtualCategory.unknown,
        );
      }
      final extension = _extension(name);
      final record = _classifier.classify(
        FileRecord(
          id: 'windows:${_normalizedPath(entity.path)}',
          locator: FileLocator(
            value: entity.path,
            sourceKind: SourceKind.fileSystem,
            platform: PickLogicPlatform.windows,
          ),
          displayName: name,
          extension: extension,
          mimeType: _mimeType(extension),
          sizeBytes: stat.size,
          createdAt: stat.changed,
          modifiedAt: stat.modified,
          parentLocator: FileLocator(
            value: entity.parent.path,
            sourceKind: SourceKind.fileSystem,
            platform: PickLogicPlatform.windows,
          ),
          sourceKind: SourceKind.fileSystem,
          platform: PickLogicPlatform.windows,
          isHidden: name.startsWith('.'),
          isSystem: false,
          isAccessible: true,
          isProtected: false,
          category: VirtualCategory.unknown,
          hashState: HashState.notRequested,
          ocrState: OcrState.notRequested,
        ),
      );
      return BrowseEntry(
        id: record.id,
        path: entity.path,
        name: name,
        isDirectory: false,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
        category: record.category,
        record: record,
      );
    } on FileSystemException {
      return null;
    }
  }
}

final class SyntheticDesktopRepository implements DesktopRepository {
  const SyntheticDesktopRepository();

  static const _drivePath = 'synthetic:/drive';
  static const _documentsPath = 'synthetic:/drive/Documents';

  @override
  Future<List<WindowsBrowseRoot>> browseRoots() async => const [
    WindowsBrowseRoot(
      id: 'drive:synthetic',
      path: _drivePath,
      kind: WindowsBrowseRootKind.drive,
    ),
    WindowsBrowseRoot(
      id: 'documents',
      path: _documentsPath,
      kind: WindowsBrowseRootKind.documents,
    ),
  ];

  @override
  Future<DirectorySnapshot> browseDirectory(
    String path, {
    int maxEntries = 1000,
  }) async {
    final records = syntheticDesktopRecords();
    if (path == _drivePath) {
      return const DirectorySnapshot(
        path: _drivePath,
        parentPath: null,
        crumbs: [BrowseCrumb(label: 'S:', path: _drivePath)],
        entries: [
          BrowseEntry(
            id: 'directory:documents',
            path: _documentsPath,
            name: 'Documents',
            isDirectory: true,
            sizeBytes: 0,
            modifiedAt: null,
            category: VirtualCategory.unknown,
          ),
        ],
        truncated: false,
      );
    }
    if (path == _documentsPath) {
      return DirectorySnapshot(
        path: _documentsPath,
        parentPath: _drivePath,
        crumbs: const [
          BrowseCrumb(label: 'S:', path: _drivePath),
          BrowseCrumb(label: 'Documents', path: _documentsPath),
        ],
        entries: records
            .map(
              (record) => BrowseEntry(
                id: record.id,
                path: record.locator.value,
                name: record.displayName,
                isDirectory: false,
                sizeBytes: record.sizeBytes,
                modifiedAt: record.modifiedAt,
                category: record.category,
                record: record,
              ),
            )
            .toList(growable: false),
        truncated: false,
      );
    }
    throw FileSystemException('Synthetic directory is unavailable.', path);
  }

  @override
  Future<DesktopDirectoryInspection> inspectDirectory(String path) async {
    if (path == _drivePath) {
      return const DesktopDirectoryInspection(
        path: _drivePath,
        displayName: 'drive',
        directories: <BrowseEntry>[
          BrowseEntry(
            id: 'directory:documents',
            path: _documentsPath,
            name: 'Documents',
            isDirectory: true,
            sizeBytes: 0,
            modifiedAt: null,
            category: VirtualCategory.unknown,
          ),
        ],
        directFileCount: 0,
        directFileBytes: 0,
        mimeFamilyCounts: <String, int>{},
      );
    }
    if (path == _documentsPath) {
      return const DesktopDirectoryInspection(
        path: _documentsPath,
        displayName: 'Documents',
        directories: <BrowseEntry>[],
        directFileCount: 2,
        directFileBytes: 7168,
        mimeFamilyCounts: <String, int>{'document': 2},
      );
    }
    throw FileSystemException('Synthetic directory is unavailable.', path);
  }

  @override
  Future<String?> chooseBrowseFolder({required bool chinese}) async =>
      _documentsPath;

  @override
  Future<bool> openBrowseEntry(BrowseEntry entry) async => !entry.isDirectory;

  @override
  Future<bool> revealBrowseEntry(BrowseEntry entry) async => true;

  @override
  Stream<DesktopScanProgress> indexCommonFolders() async* {
    final records = syntheticDesktopRecords();
    yield DesktopScanProgress(
      records: records,
      scannedCount: records.length,
      complete: true,
      rootLabel: 'Documents',
    );
  }

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

String _desktopMimeFamily(VirtualCategory category) => switch (category) {
  VirtualCategory.images || VirtualCategory.screenshots => 'image',
  VirtualCategory.videos => 'video',
  VirtualCategory.audio => 'audio',
  VirtualCategory.documents ||
  VirtualCategory.spreadsheets ||
  VirtualCategory.presentations ||
  VirtualCategory.pdf ||
  VirtualCategory.academicPapers => 'document',
  VirtualCategory.code => 'development',
  VirtualCategory.archives => 'archive',
  VirtualCategory.installers => 'application',
  _ => 'other',
};

String _rootKey(String path) {
  final normalized = Directory(path).absolute.path.replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

String _normalizedPath(String path) {
  final normalized = File(path).absolute.path.replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

String? _parentPath(String path) {
  final directory = Directory(path);
  final parent = directory.parent.absolute.path;
  return _normalizedPath(parent) == _normalizedPath(path) ? null : parent;
}

List<BrowseCrumb> _crumbs(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final drive = RegExp(r'^[A-Za-z]:').firstMatch(normalized)?.group(0);
  final segments = normalized.split('/').where((segment) => segment.isNotEmpty);
  final crumbs = <BrowseCrumb>[];
  var current = drive == null ? '' : '$drive${Platform.pathSeparator}';
  for (final segment in segments) {
    if (drive != null && segment.toLowerCase() == drive.toLowerCase()) {
      crumbs.add(BrowseCrumb(label: drive, path: current));
      continue;
    }
    current = current.isEmpty
        ? '${Platform.pathSeparator}$segment'
        : '$current${current.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$segment';
    crumbs.add(BrowseCrumb(label: segment, path: current));
  }
  return List<BrowseCrumb>.unmodifiable(crumbs);
}

String _extension(String name) {
  final index = name.lastIndexOf('.');
  return index <= 0 || index == name.length - 1
      ? ''
      : name.substring(index + 1).toLowerCase();
}

String _mimeType(String extension) => switch (extension) {
  'pdf' => 'application/pdf',
  'txt' || 'md' => 'text/plain',
  'csv' => 'text/csv',
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'mp4' => 'video/mp4',
  'mp3' => 'audio/mpeg',
  'zip' => 'application/zip',
  _ => 'application/octet-stream',
};
