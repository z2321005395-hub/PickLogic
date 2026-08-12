import 'enums.dart';
import 'locator.dart';

final class FileRecord {
  const FileRecord({
    required this.id,
    required this.locator,
    required this.displayName,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    required this.modifiedAt,
    required this.parentLocator,
    required this.sourceKind,
    required this.platform,
    required this.isHidden,
    required this.isSystem,
    required this.isAccessible,
    required this.isProtected,
    required this.category,
    this.tags = const <String>[],
    required this.hashState,
    this.sha256,
    this.perceptualHash,
    required this.ocrState,
  }) : assert(id != ''),
       assert(displayName != ''),
       assert(sizeBytes >= 0);

  final String id;
  final FileLocator locator;
  final String displayName;
  final String extension;
  final String mimeType;
  final int sizeBytes;
  final DateTime? createdAt;
  final DateTime modifiedAt;
  final FileLocator? parentLocator;
  final SourceKind sourceKind;
  final PickLogicPlatform platform;
  final bool isHidden;
  final bool isSystem;
  final bool isAccessible;
  final bool isProtected;
  final VirtualCategory category;
  final List<String> tags;
  final HashState hashState;
  final String? sha256;
  final String? perceptualHash;
  final OcrState ocrState;

  FileRecord copyWith({
    VirtualCategory? category,
    List<String>? tags,
    HashState? hashState,
    String? sha256,
    String? perceptualHash,
    OcrState? ocrState,
  }) => FileRecord(
    id: id,
    locator: locator,
    displayName: displayName,
    extension: extension,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    parentLocator: parentLocator,
    sourceKind: sourceKind,
    platform: platform,
    isHidden: isHidden,
    isSystem: isSystem,
    isAccessible: isAccessible,
    isProtected: isProtected,
    category: category ?? this.category,
    tags: List<String>.unmodifiable(tags ?? this.tags),
    hashState: hashState ?? this.hashState,
    sha256: sha256 ?? this.sha256,
    perceptualHash: perceptualHash ?? this.perceptualHash,
    ocrState: ocrState ?? this.ocrState,
  );
}

final class InsightEvidence {
  const InsightEvidence({
    required this.kind,
    required this.statement,
    required this.source,
  });

  final EvidenceKind kind;
  final String statement;
  final String source;
}

final class InsightRecord {
  const InsightRecord({
    required this.summary,
    required this.fileType,
    this.probableOwner,
    this.probableOrigin,
    this.whyItExists,
    this.relatedApplication,
    this.spaceUsageBytes,
    this.runningOrActiveState,
    required this.riskLevel,
    required this.confidence,
    this.evidence = const <InsightEvidence>[],
    this.recommendedActions = const <String>[],
    this.limitations = const <String>[],
  }) : assert(confidence >= 0 && confidence <= 1);

  final String summary;
  final String fileType;
  final String? probableOwner;
  final String? probableOrigin;
  final String? whyItExists;
  final String? relatedApplication;
  final int? spaceUsageBytes;
  final String? runningOrActiveState;
  final RiskLevel riskLevel;
  final double confidence;
  final List<InsightEvidence> evidence;
  final List<String> recommendedActions;
  final List<String> limitations;
}

final class LiteratureRecord {
  const LiteratureRecord({
    required this.id,
    required this.localFileId,
    this.doi,
    required this.title,
    this.authors = const <String>[],
    this.journal = '',
    this.year,
    this.volume = '',
    this.issue = '',
    this.pages = '',
    this.abstractText = '',
    this.keywords = const <String>[],
    this.tags = const <String>[],
    this.readingProgress = 0,
    this.lastOpenedAt,
    this.metadataSource = 'local',
    this.metadataConfidence = 0,
  }) : assert(id != ''),
       assert(localFileId != ''),
       assert(readingProgress >= 0 && readingProgress <= 1),
       assert(metadataConfidence >= 0 && metadataConfidence <= 1);

  final String id;
  final String localFileId;
  final String? doi;
  final String title;
  final List<String> authors;
  final String journal;
  final int? year;
  final String volume;
  final String issue;
  final String pages;
  final String abstractText;
  final List<String> keywords;
  final List<String> tags;
  final double readingProgress;
  final DateTime? lastOpenedAt;
  final String metadataSource;
  final double metadataConfidence;
}

final class ScreenshotGroup {
  const ScreenshotGroup({
    required this.groupId,
    required this.sourceHint,
    required this.startedAt,
    required this.endedAt,
    required this.memberIds,
    required this.duplicateConfidence,
    required this.contentHint,
    required this.ocrState,
    required this.reviewState,
    required this.protectedCount,
  }) : assert(duplicateConfidence >= 0 && duplicateConfidence <= 1),
       assert(protectedCount >= 0);

  final String groupId;
  final String sourceHint;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<String> memberIds;
  final double duplicateConfidence;
  final String contentHint;
  final OcrState ocrState;
  final ScreenshotReviewState reviewState;
  final int protectedCount;
}

final class StorageBreakdown {
  const StorageBreakdown({
    required this.category,
    required this.bytes,
    required this.accessibleBytes,
    this.estimatedBytes,
    required this.confidence,
    this.evidence = const <InsightEvidence>[],
    required this.canInspect,
    required this.canClean,
    this.systemRestriction,
  }) : assert(bytes >= 0),
       assert(accessibleBytes >= 0),
       assert(confidence >= 0 && confidence <= 1);

  final String category;
  final int bytes;
  final int accessibleBytes;
  final int? estimatedBytes;
  final double confidence;
  final List<InsightEvidence> evidence;
  final bool canInspect;
  final bool canClean;
  final String? systemRestriction;
}
