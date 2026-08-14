import 'dart:typed_data';

enum AndroidMediaKind {
  images,
  videos,
  audio,
  screenshots,
  photos,
  downloads,
  documents,
  applications,
  archives,
}

final class AndroidMediaQuery {
  const AndroidMediaQuery({
    required this.kind,
    this.limit = 100,
    this.offset = 0,
    this.modifiedAfterEpochSeconds,
  }) : assert(limit > 0 && limit <= 250),
       assert(offset >= 0);

  final AndroidMediaKind kind;
  final int limit;
  final int offset;
  final int? modifiedAfterEpochSeconds;

  Map<String, Object?> toMap() {
    final result = <String, Object?>{
      'kind': kind.name,
      'limit': limit,
      'offset': offset,
    };
    if (modifiedAfterEpochSeconds case final value?) {
      result['modifiedAfterEpochSeconds'] = value;
    }
    return result;
  }
}

final class AndroidMediaEntry {
  const AndroidMediaEntry({
    required this.id,
    required this.contentUri,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    required this.modifiedAt,
    this.relativePath,
    this.sourceHint,
    this.durationMillis,
  });

  factory AndroidMediaEntry.fromMap(Map<Object?, Object?> map) =>
      AndroidMediaEntry(
        id: map['id']! as String,
        contentUri: map['contentUri']! as String,
        displayName: map['displayName']! as String,
        mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: map['sizeBytes']! as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAtEpochSeconds']! as int) * 1000,
          isUtc: true,
        ),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['modifiedAtEpochSeconds']! as int) * 1000,
          isUtc: true,
        ),
        relativePath: map['relativePath'] as String?,
        sourceHint: map['sourceHint'] as String?,
        durationMillis: map['durationMillis'] as int?,
      );

  final String id;
  final String contentUri;
  final String displayName;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? relativePath;
  final String? sourceHint;
  final int? durationMillis;
}

final class AndroidThumbnailRequest {
  const AndroidThumbnailRequest({
    required this.contentUri,
    required this.maxWidth,
    required this.maxHeight,
    this.maxBytes = defaultMaxBytes,
  });

  static const int maxDimension = 512;
  static const int defaultMaxBytes = 256 * 1024;
  static const int absoluteMaxBytes = 512 * 1024;

  final String contentUri;
  final int maxWidth;
  final int maxHeight;
  final int maxBytes;

  Map<String, Object> toMap() {
    if (!contentUri.startsWith('content://')) {
      throw ArgumentError.value(
        contentUri,
        'contentUri',
        'Must be a content URI.',
      );
    }
    if (maxWidth < 1 || maxWidth > maxDimension) {
      throw RangeError.range(maxWidth, 1, maxDimension, 'maxWidth');
    }
    if (maxHeight < 1 || maxHeight > maxDimension) {
      throw RangeError.range(maxHeight, 1, maxDimension, 'maxHeight');
    }
    if (maxBytes < 1024 || maxBytes > absoluteMaxBytes) {
      throw RangeError.range(maxBytes, 1024, absoluteMaxBytes, 'maxBytes');
    }
    return <String, Object>{
      'contentUri': contentUri,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
      'maxBytes': maxBytes,
    };
  }
}

final class AndroidThumbnail {
  const AndroidThumbnail({required this.bytes});

  factory AndroidThumbnail.fromBytes(Uint8List bytes, {required int maxBytes}) {
    if (bytes.isEmpty || bytes.lengthInBytes > maxBytes) {
      throw const FormatException(
        'Android returned an invalid bounded thumbnail.',
      );
    }
    return AndroidThumbnail(bytes: bytes);
  }

  final Uint8List bytes;
}

final class AndroidPreviewImage {
  const AndroidPreviewImage({required this.bytes});

  factory AndroidPreviewImage.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty || bytes.lengthInBytes > 8 * 1024 * 1024) {
      throw const FormatException('Android returned an invalid preview image.');
    }
    return AndroidPreviewImage(bytes: bytes);
  }

  final Uint8List bytes;
}

final class AndroidTextPreview {
  const AndroidTextPreview({required this.text, required this.truncated});

  factory AndroidTextPreview.fromMap(Map<Object?, Object?> map) =>
      AndroidTextPreview(
        text: map['text']! as String,
        truncated: map['truncated']! as bool,
      );

  final String text;
  final bool truncated;
}

final class AndroidArchiveEntry {
  const AndroidArchiveEntry({
    required this.name,
    required this.directory,
    required this.sizeBytes,
    required this.compressedBytes,
  });

  factory AndroidArchiveEntry.fromMap(Map<Object?, Object?> map) =>
      AndroidArchiveEntry(
        name: map['name']! as String,
        directory: map['directory']! as bool,
        sizeBytes: map['sizeBytes']! as int,
        compressedBytes: map['compressedBytes']! as int,
      );

  final String name;
  final bool directory;
  final int sizeBytes;
  final int compressedBytes;
}

final class AndroidArchiveListing {
  const AndroidArchiveListing({
    required this.entries,
    required this.totalEntries,
    required this.truncated,
  });

  factory AndroidArchiveListing.fromMap(Map<Object?, Object?> map) =>
      AndroidArchiveListing(
        entries: (map['entries']! as List<Object?>)
            .cast<Map<Object?, Object?>>()
            .map(AndroidArchiveEntry.fromMap)
            .toList(growable: false),
        totalEntries: map['totalEntries']! as int,
        truncated: map['truncated']! as bool,
      );

  final List<AndroidArchiveEntry> entries;
  final int totalEntries;
  final bool truncated;
}

final class AndroidApkDetails {
  const AndroidApkDetails({
    required this.applicationName,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.signed,
    required this.installed,
    this.iconBytes,
  });

  factory AndroidApkDetails.fromMap(Map<Object?, Object?> map) =>
      AndroidApkDetails(
        applicationName: map['applicationName']! as String,
        packageName: map['packageName']! as String,
        versionName: map['versionName']! as String,
        versionCode: map['versionCode']! as int,
        signed: map['signed']! as bool,
        installed: map['installed']! as bool,
        iconBytes: map['iconBytes'] as Uint8List?,
      );

  final String applicationName;
  final String packageName;
  final String versionName;
  final int versionCode;
  final bool signed;
  final bool installed;
  final Uint8List? iconBytes;
}

final class AndroidPdfInfo {
  const AndroidPdfInfo({required this.pageCount});

  factory AndroidPdfInfo.fromMap(Map<Object?, Object?> map) =>
      AndroidPdfInfo(pageCount: map['pageCount']! as int);

  final int pageCount;
}

final class AndroidOfficePreview {
  const AndroidOfficePreview({
    required this.kind,
    required this.title,
    required this.sections,
    required this.gridRows,
    required this.imageCount,
    required this.itemCount,
    required this.truncated,
  });

  factory AndroidOfficePreview.fromMap(Map<Object?, Object?> map) =>
      AndroidOfficePreview(
        kind: map['kind']! as String,
        title: map['title']! as String,
        sections: (map['sections']! as List<Object?>).cast<String>(),
        gridRows: (map['gridRows']! as List<Object?>)
            .map((row) => (row! as List<Object?>).cast<String>())
            .toList(growable: false),
        imageCount: map['imageCount']! as int,
        itemCount: map['itemCount']! as int,
        truncated: map['truncated']! as bool,
      );

  final String kind;
  final String title;
  final List<String> sections;
  final List<List<String>> gridRows;
  final int imageCount;
  final int itemCount;
  final bool truncated;
}

final class AndroidWorkspaceEntry {
  const AndroidWorkspaceEntry({
    required this.documentUri,
    required this.parentUri,
    required this.displayName,
    required this.mimeType,
    required this.directory,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.depth,
  });

  factory AndroidWorkspaceEntry.fromMap(Map<Object?, Object?> map) =>
      AndroidWorkspaceEntry(
        documentUri: map['documentUri']! as String,
        parentUri: map['parentUri']! as String,
        displayName: map['displayName']! as String,
        mimeType: map['mimeType']! as String,
        directory: map['directory']! as bool,
        sizeBytes: map['sizeBytes']! as int,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          map['modifiedAtMillis']! as int,
        ),
        depth: map['depth']! as int,
      );

  final String documentUri;
  final String parentUri;
  final String displayName;
  final String mimeType;
  final bool directory;
  final int sizeBytes;
  final DateTime modifiedAt;
  final int depth;
}

final class AndroidWorkspaceState {
  const AndroidWorkspaceState({
    required this.authorized,
    required this.treeUri,
    required this.entries,
    required this.undoAvailable,
    this.operationId,
  });

  factory AndroidWorkspaceState.fromMap(Map<Object?, Object?> map) =>
      AndroidWorkspaceState(
        authorized: map['authorized']! as bool,
        treeUri: map['treeUri'] as String?,
        entries: (map['entries']! as List<Object?>)
            .cast<Map<Object?, Object?>>()
            .map(AndroidWorkspaceEntry.fromMap)
            .toList(growable: false),
        undoAvailable: map['undoAvailable']! as bool,
        operationId: map['operationId'] as String?,
      );

  final bool authorized;
  final String? treeUri;
  final List<AndroidWorkspaceEntry> entries;
  final bool undoAvailable;
  final String? operationId;
}

final class AndroidMediaPage {
  const AndroidMediaPage({
    required this.items,
    required this.offset,
    required this.hasMore,
  });

  factory AndroidMediaPage.fromMap(Map<Object?, Object?> map) {
    final rawItems = map['items']! as List<Object?>;
    return AndroidMediaPage(
      items: rawItems
          .cast<Map<Object?, Object?>>()
          .map(AndroidMediaEntry.fromMap)
          .toList(growable: false),
      offset: map['offset']! as int,
      hasMore: map['hasMore']! as bool,
    );
  }

  final List<AndroidMediaEntry> items;
  final int offset;
  final bool hasMore;
}

final class AndroidMediaPermissionState {
  const AndroidMediaPermissionState({
    required this.images,
    required this.videos,
    required this.audio,
    required this.partialVisualAccess,
  });

  factory AndroidMediaPermissionState.fromMap(Map<Object?, Object?> map) =>
      AndroidMediaPermissionState(
        images: map['images']! as bool,
        videos: map['videos']! as bool,
        audio: map['audio']! as bool,
        partialVisualAccess: map['partialVisualAccess']! as bool,
      );

  final bool images;
  final bool videos;
  final bool audio;
  final bool partialVisualAccess;

  bool get canReadImages => images || partialVisualAccess;
  bool get canReadVisualMedia => canReadImages || videos;
}

final class AndroidStorageSnapshot {
  const AndroidStorageSnapshot({
    required this.totalBytes,
    required this.availableBytes,
    required this.canInspectSharedMedia,
    required this.canInspectOtherAppPrivateData,
    required this.systemRestriction,
    this.canInspectDownloads = false,
    this.isAggregateOnly = true,
    this.canClean = false,
    this.limitations = const <String>[],
  });

  factory AndroidStorageSnapshot.fromMap(Map<Object?, Object?> map) =>
      AndroidStorageSnapshot(
        totalBytes: map['totalBytes']! as int,
        availableBytes: map['availableBytes']! as int,
        canInspectSharedMedia: map['canInspectSharedMedia']! as bool,
        canInspectOtherAppPrivateData:
            map['canInspectOtherAppPrivateData']! as bool,
        systemRestriction: map['systemRestriction']! as String,
        canInspectDownloads: map['canInspectDownloads'] as bool? ?? false,
        isAggregateOnly: map['isAggregateOnly'] as bool? ?? true,
        canClean: map['canClean'] as bool? ?? false,
        limitations:
            (map['limitations'] as List<Object?>?)?.cast<String>() ??
            const <String>[],
      );

  final int totalBytes;
  final int availableBytes;
  final bool canInspectSharedMedia;
  final bool canInspectOtherAppPrivateData;
  final String systemRestriction;
  final bool canInspectDownloads;
  final bool isAggregateOnly;
  final bool canClean;
  final List<String> limitations;
}
