enum AndroidMediaKind {
  images,
  videos,
  audio,
  screenshots,
  photos,
  downloads,
  documents,
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
      );

  final String id;
  final String contentUri;
  final String displayName;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? relativePath;
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

  bool get canReadVisualMedia => images || videos || partialVisualAccess;
}

final class AndroidStorageSnapshot {
  const AndroidStorageSnapshot({
    required this.totalBytes,
    required this.availableBytes,
    required this.canInspectSharedMedia,
    required this.canInspectOtherAppPrivateData,
    required this.systemRestriction,
  });

  factory AndroidStorageSnapshot.fromMap(Map<Object?, Object?> map) =>
      AndroidStorageSnapshot(
        totalBytes: map['totalBytes']! as int,
        availableBytes: map['availableBytes']! as int,
        canInspectSharedMedia: map['canInspectSharedMedia']! as bool,
        canInspectOtherAppPrivateData:
            map['canInspectOtherAppPrivateData']! as bool,
        systemRestriction: map['systemRestriction']! as String,
      );

  final int totalBytes;
  final int availableBytes;
  final bool canInspectSharedMedia;
  final bool canInspectOtherAppPrivateData;
  final String systemRestriction;
}
