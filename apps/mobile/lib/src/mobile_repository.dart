import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

final class MobileBootstrapState {
  const MobileBootstrapState({
    required this.permissions,
    required this.storage,
    required this.synthetic,
  });

  final AndroidMediaPermissionState permissions;
  final AndroidStorageSnapshot storage;
  final bool synthetic;
}

abstract interface class MobileRepository {
  Future<MobileBootstrapState> loadBootstrap();

  Future<MobileBootstrapState> requestMediaAccess();

  Future<List<FileRecord>> loadMedia(
    AndroidMediaKind kind, {
    int limit = 60,
    int offset = 0,
  });

  Future<String?> chooseDocumentTree();

  Future<bool> open(FileRecord record);

  Future<List<FileRecord>> search(String query);
}

final class AndroidMobileRepository implements MobileRepository {
  AndroidMobileRepository({this.bridge = const PicklogicAndroidBridge()});

  final PicklogicAndroidBridge bridge;
  final Map<String, FileRecord> _metadataCache = <String, FileRecord>{};

  @override
  Future<MobileBootstrapState> loadBootstrap() async => MobileBootstrapState(
    permissions: await bridge.getMediaPermissionState(),
    storage: await bridge.getStorageSnapshot(),
    synthetic: false,
  );

  @override
  Future<MobileBootstrapState> requestMediaAccess() async {
    final permissions = await bridge.requestMediaPermissions();
    return MobileBootstrapState(
      permissions: permissions,
      storage: await bridge.getStorageSnapshot(),
      synthetic: false,
    );
  }

  @override
  Future<List<FileRecord>> loadMedia(
    AndroidMediaKind kind, {
    int limit = 60,
    int offset = 0,
  }) async {
    final page = await bridge.queryMediaPage(
      AndroidMediaQuery(kind: kind, limit: limit, offset: offset),
    );
    final records = page.items
        .map((entry) => _recordFromAndroid(entry, kind))
        .toList(growable: false);
    for (final record in records) {
      _metadataCache[record.id] = record;
    }
    return records;
  }

  @override
  Future<String?> chooseDocumentTree() => bridge.pickDocumentTree();

  @override
  Future<bool> open(FileRecord record) =>
      bridge.openContentUri(record.locator.value);

  @override
  Future<List<FileRecord>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const <FileRecord>[];
    if (_metadataCache.isEmpty) {
      for (final kind in const [
        AndroidMediaKind.screenshots,
        AndroidMediaKind.photos,
        AndroidMediaKind.documents,
      ]) {
        try {
          await loadMedia(kind, limit: 60);
        } catch (_) {
          // A denied collection remains absent and visible as a permission gate.
        }
      }
    }
    return _metadataCache.values
        .where(
          (record) =>
              record.displayName.toLowerCase().contains(normalized) ||
              record.mimeType.toLowerCase().contains(normalized) ||
              record.category.name.toLowerCase().contains(normalized),
        )
        .take(100)
        .toList(growable: false);
  }
}

final class SyntheticMobileRepository implements MobileRepository {
  const SyntheticMobileRepository();

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
      );

  @override
  Future<MobileBootstrapState> requestMediaAccess() => loadBootstrap();

  @override
  Future<List<FileRecord>> loadMedia(
    AndroidMediaKind kind, {
    int limit = 60,
    int offset = 0,
  }) async => List<FileRecord>.generate(
    switch (kind) {
      AndroidMediaKind.screenshots => 3,
      AndroidMediaKind.photos || AndroidMediaKind.images => 12,
      _ => 3,
    },
    (index) => syntheticMobileRecord(switch (kind) {
      AndroidMediaKind.screenshots => 'Screenshot_${index + 1}.png',
      AndroidMediaKind.photos ||
      AndroidMediaKind.images => 'Photo_${index + 1}.jpg',
      AndroidMediaKind.downloads => 'Download_${index + 1}.pdf',
      AndroidMediaKind.documents => 'Document_${index + 1}.txt',
      AndroidMediaKind.videos => 'Video_${index + 1}.mp4',
      AndroidMediaKind.audio => 'Audio_${index + 1}.mp3',
    }),
    growable: false,
  );

  @override
  Future<String?> chooseDocumentTree() async => 'synthetic://document-tree';

  @override
  Future<bool> open(FileRecord record) async => true;

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
}

FileRecord syntheticMobileRecord(String name) => FileRecord(
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
  createdAt: DateTime.utc(2026, 8, 12),
  modifiedAt: DateTime.utc(2026, 8, 12),
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
    },
    tags: entry.relativePath == null
        ? const <String>[]
        : const <String>['platform-metadata'],
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
