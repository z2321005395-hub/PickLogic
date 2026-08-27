import 'dart:async';
import 'dart:typed_data';

import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_preview_core/picklogic_preview_core.dart';

import 'incremental_index_queue.dart';
import 'mobile_index_persistence.dart';
import 'screenshot_grouping.dart';

final class MobileBootstrapState {
  const MobileBootstrapState({
    required this.permissions,
    required this.storage,
    required this.synthetic,
    required this.indexQueue,
  });

  final AndroidMediaPermissionState permissions;
  final AndroidStorageSnapshot storage;
  final bool synthetic;
  final MobileIndexQueueSnapshot indexQueue;
}

abstract interface class MobileRepository {
  Future<MobileBootstrapState> loadBootstrap();

  Future<MobileBootstrapState> requestMediaAccess();

  Future<List<FileRecord>> loadMedia(
    AndroidMediaKind kind, {
    int limit = 120,
    int offset = 0,
  });

  Future<List<MobileScreenshotGroup>> loadScreenshotGroups({
    int limit = 120,
    int offset = 0,
  });

  Future<List<MobileScreenshotCandidate>> loadScreenshotCandidates({
    int limit = 120,
    int offset = 0,
  });

  Future<int> countMedia(AndroidMediaKind kind);

  Future<Uint8List?> loadThumbnail(
    FileRecord record, {
    required int maxWidth,
    required int maxHeight,
  });

  MobileIndexQueueSnapshot get indexQueueSnapshot;

  void scheduleIncrementalIndexing();

  void cancelIncrementalIndexing();

  Future<String?> chooseDocumentTree();

  Future<bool> open(FileRecord record);

  /// Requests Android's own recoverable MediaStore trash flow.
  ///
  /// Implementations must never silently delete files and must return `false`
  /// when the platform confirmation is cancelled or unavailable.
  Future<bool> requestSystemTrash(List<FileRecord> records);

  Future<List<FileRecord>> search(String query);

  Future<void> close();
}

/// Optional viewer capabilities stay out of [MobileRepository] so test doubles
/// and alternate metadata repositories do not need to implement platform I/O.
extension MobileRepositoryViewerCapabilities on MobileRepository {
  PicklogicAndroidBridge? get _viewerBridge => this is AndroidMobileRepository
      ? (this as AndroidMobileRepository).bridge
      : null;

  Future<AndroidPreviewImage?> loadPreviewImage(FileRecord record) async =>
      _viewerBridge?.loadPreviewImage(record.locator.value);

  Future<AndroidTextPreview> loadTextPreview(FileRecord record) async =>
      await _viewerBridge?.loadTextPreview(record.locator.value) ??
      AndroidTextPreview(
        text: 'Synthetic read-only preview for ${record.displayName}',
        truncated: false,
      );

  Future<AndroidArchiveListing> listArchive(FileRecord record) async =>
      await _viewerBridge?.listArchive(record.locator.value) ??
      const AndroidArchiveListing(
        entries: <AndroidArchiveEntry>[],
        totalEntries: 0,
        truncated: false,
      );

  Future<AndroidApkDetails?> inspectApk(FileRecord record) async =>
      _viewerBridge?.inspectApk(record.locator.value);

  Future<AndroidPdfInfo?> getPdfInfo(FileRecord record) async =>
      _viewerBridge?.getPdfInfo(record.locator.value);

  Future<AndroidOfficePreview?> inspectOffice(FileRecord record) async =>
      _viewerBridge?.inspectOffice(
        record.locator.value,
        extension: record.extension.toLowerCase(),
      );

  Future<AndroidPreviewImage?> renderPdfPage(
    FileRecord record, {
    required int pageIndex,
    required int maxWidth,
    required int maxHeight,
  }) async => _viewerBridge?.renderPdfPage(
    record.locator.value,
    pageIndex: pageIndex,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );

  Future<int> loadGridColumns(String key, {int fallback = 3}) async =>
      ((await _viewerBridge?.readIntPreference(key)) ?? fallback).clamp(2, 6);

  Future<void> saveGridColumns(String key, int value) async {
    await _viewerBridge?.writeIntPreference(key, value.clamp(2, 6));
  }

  Future<int> loadPdfRecentPage(FileRecord record) async =>
      (await _viewerBridge?.readIntPreference(
        _pdfPagePreferenceKey(record.id),
      ))?.clamp(0, 100000) ??
      0;

  Future<void> savePdfRecentPage(FileRecord record, int page) async {
    await _viewerBridge?.writeIntPreference(
      _pdfPagePreferenceKey(record.id),
      page.clamp(0, 100000),
    );
  }

  Future<AndroidWorkspaceState> loadTestWorkspace() async =>
      await _viewerBridge?.getTestWorkspaceState() ??
      const AndroidWorkspaceState(
        authorized: false,
        treeUri: null,
        entries: <AndroidWorkspaceEntry>[],
        undoAvailable: false,
      );

  Future<AndroidWorkspaceState?> chooseTestWorkspace() =>
      _viewerBridge?.pickTestWorkspaceTree() ??
      Future<AndroidWorkspaceState?>.value();

  Future<AndroidWorkspaceState?> importTestCopies() =>
      _viewerBridge?.importTestWorkspaceCopies() ??
      Future<AndroidWorkspaceState?>.value();

  Future<AndroidWorkspaceState> createTestFolder(
    String name, {
    String? parentUri,
  }) async =>
      await _viewerBridge?.createTestWorkspaceFolder(
        parentUri: parentUri,
        name: name,
      ) ??
      await loadTestWorkspace();

  Future<AndroidWorkspaceState> renameTestItem(
    AndroidWorkspaceEntry entry,
    String name,
  ) async =>
      await _viewerBridge?.renameTestWorkspaceItem(
        documentUri: entry.documentUri,
        name: name,
      ) ??
      await loadTestWorkspace();

  Future<AndroidWorkspaceState> moveTestItem(
    AndroidWorkspaceEntry entry,
    String targetParentUri,
  ) async =>
      await _viewerBridge?.moveTestWorkspaceItem(
        documentUri: entry.documentUri,
        sourceParentUri: entry.parentUri,
        targetParentUri: targetParentUri,
      ) ??
      await loadTestWorkspace();

  Future<AndroidWorkspaceState> trashTestItem(
    AndroidWorkspaceEntry entry,
  ) async =>
      await _viewerBridge?.trashTestWorkspaceItem(
        documentUri: entry.documentUri,
        sourceParentUri: entry.parentUri,
      ) ??
      await loadTestWorkspace();

  Future<AndroidWorkspaceState> undoTestOperation([
    String? operationId,
  ]) async =>
      await _viewerBridge?.undoTestWorkspaceOperation(
        operationId: operationId,
      ) ??
      await loadTestWorkspace();

  Future<List<AndroidBrowseRoot>> loadBrowseRoots() async =>
      await _viewerBridge?.getBrowseRoots() ?? const <AndroidBrowseRoot>[];

  Future<AndroidBrowsePage?> loadBrowseDirectory({
    required String treeUri,
    String? directoryUri,
    int offset = 0,
    int limit = 200,
  }) =>
      _viewerBridge?.listBrowseDirectory(
        treeUri: treeUri,
        directoryUri: directoryUri,
        offset: offset,
        limit: limit,
      ) ??
      Future<AndroidBrowsePage?>.value();
}

String _pdfPagePreferenceKey(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return 'pdfRecentPage-${hash.toRadixString(16)}';
}

final class AndroidMobileRepository implements MobileRepository {
  AndroidMobileRepository({
    PicklogicAndroidBridge bridge = const PicklogicAndroidBridge(),
    this.bootstrapTimeout = const Duration(seconds: 8),
    MobileIndexPersistence? indexPersistence,
  }) : bridge = bridge,
       _indexPersistence =
           indexPersistence ??
           LazyMobileIndexPersistence(
             () async => SqliteMobileIndexPersistence.open(
               await bridge.getPrivateIndexDatabasePath(),
             ),
             persistsAcrossRestarts: true,
           );

  final PicklogicAndroidBridge bridge;
  final Duration bootstrapTimeout;
  final MobileIndexPersistence _indexPersistence;
  final Map<String, FileRecord> _metadataCache = <String, FileRecord>{};
  final BoundedCache<String, Uint8List> _thumbnailCache =
      BoundedCache<String, Uint8List>(
        maxEntries: 48,
        maxWeight: 8 * 1024 * 1024,
      );
  final Map<String, Future<Uint8List?>> _thumbnailLoads =
      <String, Future<Uint8List?>>{};
  AndroidMediaPermissionState? _lastPermissions;
  late final MobileIncrementalIndexQueue _indexQueue =
      MobileIncrementalIndexQueue(
        loader: _loadIndexPage,
        checkpointStore: _indexPersistence,
      );

  @override
  MobileIndexQueueSnapshot get indexQueueSnapshot => _indexQueue.snapshot;

  @override
  Future<MobileBootstrapState> loadBootstrap() async {
    final platformState = await Future.wait<Object>([
      bridge.getMediaPermissionState(),
      bridge.getStorageSnapshot(),
    ]).timeout(bootstrapTimeout);
    final permissions = platformState[0] as AndroidMediaPermissionState;
    final storage = platformState[1] as AndroidStorageSnapshot;
    _lastPermissions = permissions;
    if (permissions.canReadVisualMedia || permissions.audio) {
      scheduleIncrementalIndexing();
    }
    return MobileBootstrapState(
      permissions: permissions,
      storage: storage,
      synthetic: false,
      indexQueue: indexQueueSnapshot,
    );
  }

  @override
  Future<MobileBootstrapState> requestMediaAccess() async {
    final permissions = await bridge.requestMediaPermissions();
    _lastPermissions = permissions;
    if (permissions.canReadVisualMedia || permissions.audio) {
      scheduleIncrementalIndexing();
    }
    return MobileBootstrapState(
      permissions: permissions,
      storage: await bridge.getStorageSnapshot().timeout(bootstrapTimeout),
      synthetic: false,
      indexQueue: indexQueueSnapshot,
    );
  }

  @override
  Future<List<FileRecord>> loadMedia(
    AndroidMediaKind kind, {
    int limit = 120,
    int offset = 0,
  }) async {
    final page = await _loadAndCachePage(
      AndroidMediaQuery(kind: kind, limit: limit, offset: offset),
    );
    return page.items
        .map((entry) => _recordFromAndroid(entry, kind))
        .toList(growable: false);
  }

  @override
  Future<List<MobileScreenshotGroup>> loadScreenshotGroups({
    int limit = 120,
    int offset = 0,
  }) async {
    return buildScreenshotGroups(
      await loadScreenshotCandidates(limit: limit, offset: offset),
    );
  }

  @override
  Future<List<MobileScreenshotCandidate>> loadScreenshotCandidates({
    int limit = 120,
    int offset = 0,
  }) async {
    final page = await _loadAndCachePage(
      AndroidMediaQuery(
        kind: AndroidMediaKind.screenshots,
        limit: limit,
        offset: offset,
      ),
    );
    return page.items
        .map(
          (entry) => MobileScreenshotCandidate(
            record: _recordFromAndroid(entry, AndroidMediaKind.screenshots),
            metadata: entry,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<int> countMedia(AndroidMediaKind kind) => bridge.countMedia(kind);

  @override
  Future<Uint8List?> loadThumbnail(
    FileRecord record, {
    required int maxWidth,
    required int maxHeight,
  }) {
    final request = AndroidThumbnailRequest(
      contentUri: record.locator.value,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    final key = '${request.contentUri}|$maxWidth|$maxHeight';
    final cached = _thumbnailCache.get(key);
    if (cached != null) return Future<Uint8List?>.value(cached);
    return _thumbnailLoads.putIfAbsent(key, () async {
      try {
        final thumbnail = await bridge.loadThumbnail(request);
        final bytes = thumbnail?.bytes;
        if (bytes != null) {
          _thumbnailCache.put(key, bytes, weight: bytes.lengthInBytes);
        }
        return bytes;
      } finally {
        _thumbnailLoads.remove(key);
      }
    });
  }

  @override
  void scheduleIncrementalIndexing() {
    final permissions = _lastPermissions;
    if (permissions == null) return;
    if (permissions.canReadImages) {
      _indexQueue.enqueue(AndroidMediaKind.screenshots);
      _indexQueue.enqueue(AndroidMediaKind.photos);
    }
    if (permissions.videos) _indexQueue.enqueue(AndroidMediaKind.videos);
    if (permissions.audio) _indexQueue.enqueue(AndroidMediaKind.audio);
  }

  @override
  void cancelIncrementalIndexing() => _indexQueue.cancel();

  Future<AndroidMediaPage> _loadIndexPage(AndroidMediaQuery query) =>
      _loadAndCachePage(query, requirePersistence: true);

  Future<AndroidMediaPage> _loadAndCachePage(
    AndroidMediaQuery query, {
    bool requirePersistence = false,
  }) async {
    final page = await bridge.queryMediaPage(query);
    final records = <FileRecord>[];
    for (final entry in page.items) {
      final record = _recordFromAndroid(entry, query.kind);
      _metadataCache[record.id] = record;
      records.add(record);
    }
    try {
      await _indexPersistence.upsertRecords(records);
    } catch (_) {
      if (requirePersistence) rethrow;
    }
    return page;
  }

  @override
  Future<String?> chooseDocumentTree() => bridge.pickDocumentTree();

  @override
  Future<bool> open(FileRecord record) =>
      bridge.openContentUri(record.locator.value);

  @override
  Future<bool> requestSystemTrash(List<FileRecord> records) async {
    if (records.isEmpty || records.length > 100) return false;
    final uris = <String>[];
    for (final record in records) {
      final uri = Uri.tryParse(record.locator.value);
      if (record.platform != PickLogicPlatform.android ||
          !record.isAccessible ||
          record.isProtected ||
          record.isSystem ||
          record.category == VirtualCategory.unknown ||
          (record.sourceKind != SourceKind.mediaStore &&
              record.sourceKind != SourceKind.downloads) ||
          uri == null ||
          uri.scheme != 'content') {
        return false;
      }
      uris.add(record.locator.value);
    }
    final accepted = await bridge.requestSystemTrash(uris);
    if (!accepted) return false;
    final ids = records.map((record) => record.id).toSet();
    _metadataCache.removeWhere((id, _) => ids.contains(id));
    try {
      await _indexPersistence.removeRecords(ids);
    } on Object {
      // The system operation succeeded. A later incremental pass repairs a
      // stale local index if removing its rows fails.
    }
    return true;
  }

  @override
  Future<List<FileRecord>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const <FileRecord>[];
    if (_metadataCache.isEmpty) scheduleIncrementalIndexing();
    final cached = _metadataCache.values
        .where(
          (record) =>
              record.displayName.toLowerCase().contains(normalized) ||
              record.mimeType.toLowerCase().contains(normalized) ||
              record.category.name.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
    try {
      final persisted = await _indexPersistence.search(normalized, limit: 100);
      final merged = <String, FileRecord>{
        for (final record in persisted) record.id: record,
        for (final record in cached) record.id: record,
      };
      return merged.values.take(100).toList(growable: false);
    } catch (_) {
      return cached.take(100).toList(growable: false);
    }
  }

  @override
  Future<void> close() async {
    _indexQueue.cancel();
    await _indexQueue.idle;
    await _indexPersistence.close();
  }
}

final class SyntheticMobileRepository implements MobileRepository {
  const SyntheticMobileRepository({this.systemTrashResult = false});

  final bool systemTrashResult;

  @override
  MobileIndexQueueSnapshot get indexQueueSnapshot =>
      const MobileIndexQueueSnapshot(
        pendingBatches: 0,
        isRunning: false,
        completedBatches: 0,
        failedBatches: 0,
        pageSize: 40,
        maxPendingBatches: 4,
      );

  @override
  Future<MobileBootstrapState> loadBootstrap() async =>
      const MobileBootstrapState(
        permissions: AndroidMediaPermissionState(
          images: true,
          videos: true,
          audio: true,
          partialVisualAccess: false,
        ),
        storage: AndroidStorageSnapshot(
          totalBytes: 1000000000,
          availableBytes: 420000000,
          canInspectSharedMedia: true,
          canInspectOtherAppPrivateData: false,
          systemRestriction: '当前Android权限不允许第三方应用直接检查该部分。',
        ),
        synthetic: true,
        indexQueue: MobileIndexQueueSnapshot(
          pendingBatches: 0,
          isRunning: false,
          completedBatches: 0,
          failedBatches: 0,
          pageSize: 40,
          maxPendingBatches: 4,
        ),
      );

  @override
  Future<MobileBootstrapState> requestMediaAccess() => loadBootstrap();

  @override
  Future<List<FileRecord>> loadMedia(
    AndroidMediaKind kind, {
    int limit = 120,
    int offset = 0,
  }) async {
    final count = switch (kind) {
      AndroidMediaKind.screenshots => 4,
      AndroidMediaKind.photos || AndroidMediaKind.images => 12,
      _ => 3,
    };
    return Iterable<FileRecord>.generate(
      count,
      (index) => syntheticMobileRecord(switch (kind) {
        AndroidMediaKind.screenshots => 'Screenshot_${index + 1}.png',
        AndroidMediaKind.photos ||
        AndroidMediaKind.images => 'Photo_${index + 1}.jpg',
        AndroidMediaKind.downloads => 'Download_${index + 1}.pdf',
        AndroidMediaKind.documents => 'Document_${index + 1}.txt',
        AndroidMediaKind.videos => 'Video_${index + 1}.mp4',
        AndroidMediaKind.audio => 'Audio_${index + 1}.mp3',
        AndroidMediaKind.applications => 'Application_${index + 1}.apk',
        AndroidMediaKind.archives => 'Archive_${index + 1}.zip',
      }),
    ).skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<List<MobileScreenshotGroup>> loadScreenshotGroups({
    int limit = 120,
    int offset = 0,
  }) async {
    return buildScreenshotGroups(
      await loadScreenshotCandidates(limit: limit, offset: offset),
    );
  }

  @override
  Future<List<MobileScreenshotCandidate>> loadScreenshotCandidates({
    int limit = 120,
    int offset = 0,
  }) async {
    final times = <DateTime>[
      DateTime.utc(2026, 8, 12, 10, 2),
      DateTime.utc(2026, 8, 12, 10),
      DateTime.utc(2026, 8, 12, 8),
      DateTime.utc(2026, 7, 28, 16),
    ];
    final sources = <String>[
      'synthetic.notes',
      'synthetic.notes',
      'synthetic.browser',
      'synthetic.reader',
    ];
    final candidates = <MobileScreenshotCandidate>[
      for (var index = 0; index < times.length; index++)
        MobileScreenshotCandidate(
          record: syntheticMobileRecord(
            'Screenshot_${index + 1}.png',
            createdAt: times[index],
            modifiedAt: times[index],
          ),
          metadata: AndroidMediaEntry(
            id: 'synthetic:${index + 1}',
            contentUri: 'content://synthetic/screenshots/${index + 1}',
            displayName: 'Screenshot_${index + 1}.png',
            mimeType: 'image/png',
            sizeBytes: 1024,
            createdAt: times[index],
            modifiedAt: times[index],
            relativePath: 'Pictures/Screenshots/',
            sourceHint: sources[index],
          ),
        ),
    ];
    return candidates.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<int> countMedia(AndroidMediaKind kind) async => switch (kind) {
    AndroidMediaKind.screenshots => 4,
    AndroidMediaKind.photos || AndroidMediaKind.images => 12,
    _ => 3,
  };

  @override
  Future<Uint8List?> loadThumbnail(
    FileRecord record, {
    required int maxWidth,
    required int maxHeight,
  }) async => null;

  @override
  void scheduleIncrementalIndexing() {}

  @override
  void cancelIncrementalIndexing() {}

  @override
  Future<String?> chooseDocumentTree() async => 'synthetic://document-tree';

  @override
  Future<bool> open(FileRecord record) async => true;

  @override
  Future<bool> requestSystemTrash(List<FileRecord> records) async =>
      systemTrashResult;

  @override
  Future<List<FileRecord>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    final records = <FileRecord>[];
    for (final kind in const [
      AndroidMediaKind.documents,
      AndroidMediaKind.screenshots,
      AndroidMediaKind.photos,
    ]) {
      records.addAll(await loadMedia(kind));
    }
    return records
        .where(
          (record) => record.displayName.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  @override
  Future<void> close() async {}
}

FileRecord syntheticMobileRecord(
  String name, {
  DateTime? createdAt,
  DateTime? modifiedAt,
}) => FileRecord(
  id: name,
  locator: FileLocator(
    value: 'synthetic://mobile/$name',
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
  ),
  displayName: name,
  extension: _extensionOf(name),
  mimeType: _mimeForExtension(_extensionOf(name)),
  sizeBytes: 1024,
  createdAt: createdAt ?? DateTime.utc(2026, 8, 12),
  modifiedAt: modifiedAt ?? createdAt ?? DateTime.utc(2026, 8, 12),
  parentLocator: null,
  sourceKind: SourceKind.synthetic,
  platform: PickLogicPlatform.synthetic,
  isHidden: false,
  isSystem: false,
  isAccessible: true,
  isProtected: false,
  category: name.startsWith('Screenshot')
      ? VirtualCategory.screenshots
      : _categoryForExtension(_extensionOf(name)),
  tags: const ['synthetic'],
  hashState: HashState.notRequested,
  ocrState: OcrState.notRequested,
);

FileRecord _recordFromAndroid(AndroidMediaEntry entry, AndroidMediaKind kind) {
  final extension = _extensionOf(entry.displayName);
  final sourceKind = kind == AndroidMediaKind.downloads
      ? SourceKind.downloads
      : SourceKind.mediaStore;
  return FileRecord(
    id: entry.id,
    locator: FileLocator(
      value: entry.contentUri,
      sourceKind: sourceKind,
      platform: PickLogicPlatform.android,
    ),
    displayName: entry.displayName,
    extension: extension,
    mimeType: entry.mimeType,
    sizeBytes: entry.sizeBytes,
    createdAt: entry.createdAt.millisecondsSinceEpoch == 0
        ? null
        : entry.createdAt,
    modifiedAt: entry.modifiedAt,
    parentLocator: null,
    sourceKind: sourceKind,
    platform: PickLogicPlatform.android,
    isHidden: entry.displayName.startsWith('.'),
    isSystem: false,
    isAccessible: true,
    isProtected: false,
    category: switch (kind) {
      AndroidMediaKind.screenshots => VirtualCategory.screenshots,
      AndroidMediaKind.photos ||
      AndroidMediaKind.images => VirtualCategory.images,
      AndroidMediaKind.videos => VirtualCategory.videos,
      AndroidMediaKind.audio => VirtualCategory.audio,
      AndroidMediaKind.downloads => VirtualCategory.downloads,
      AndroidMediaKind.documents => _categoryForExtension(extension),
      AndroidMediaKind.applications => VirtualCategory.installers,
      AndroidMediaKind.archives => VirtualCategory.archives,
    },
    tags: <String>[
      'platform-metadata',
      if (entry.relativePath?.trim() case final path? when path.isNotEmpty)
        'relative-path:$path',
      if (entry.sourceHint?.trim() case final hint? when hint.isNotEmpty)
        'source-hint:$hint',
      if (entry.durationMillis case final duration? when duration > 0)
        'duration-ms:$duration',
    ],
    hashState: HashState.notRequested,
    ocrState: OcrState.notRequested,
  );
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 || dot == name.length - 1
      ? ''
      : name.substring(dot + 1).toLowerCase();
}

VirtualCategory _categoryForExtension(String extension) => switch (extension) {
  'pdf' => VirtualCategory.pdf,
  'xls' || 'xlsx' || 'csv' => VirtualCategory.spreadsheets,
  'ppt' || 'pptx' => VirtualCategory.presentations,
  'png' || 'jpg' || 'jpeg' || 'webp' => VirtualCategory.images,
  'mp4' || 'mkv' || 'webm' => VirtualCategory.videos,
  'mp3' || 'wav' || 'flac' => VirtualCategory.audio,
  'apk' => VirtualCategory.installers,
  'zip' || '7z' || 'rar' => VirtualCategory.archives,
  'txt' || 'doc' || 'docx' || 'md' => VirtualCategory.documents,
  _ => VirtualCategory.unknown,
};

String _mimeForExtension(String extension) => switch (extension) {
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'pdf' => 'application/pdf',
  'txt' => 'text/plain',
  'mp4' => 'video/mp4',
  'mp3' => 'audio/mpeg',
  _ => 'application/octet-stream',
};
