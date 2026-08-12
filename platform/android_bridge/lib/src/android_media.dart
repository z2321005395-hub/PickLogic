import 'dart:typed_data';

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
    this.sourceHint,
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
