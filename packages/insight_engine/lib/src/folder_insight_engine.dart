import 'dart:collection';

import 'package:picklogic_core_models/picklogic_core_models.dart';

enum FolderRole {
  driveRoot,
  userHome,
  desktop,
  camera,
  screenshots,
  downloads,
  documents,
  images,
  videos,
  audio,
  recordings,
  appSharedMedia,
  applicationData,
  applicationInstall,
  systemManaged,
  cache,
  thumbnails,
  temporary,
  logs,
  backups,
  trash,
  hidden,
  cloudSync,
  development,
  researchData,
  mixedContent,
  unknown,
}

enum FolderEvidence {
  readOnlyMetadata,
  standardFolderName,
  platformPathConvention,
  packageIdentifier,
  parentContext,
  directChildMetadata,
  hiddenName,
  emptyFolder,
  providerFailure,
  boundedObservation,
}

/// Metadata-only description of one directory. Locators remain opaque and are
/// never interpreted as interchangeable Windows paths and Android URIs.
final class FolderObservation {
  const FolderObservation({
    required this.locator,
    required this.displayName,
    required this.pathSegments,
    required this.platform,
    required this.directFileCount,
    required this.directDirectoryCount,
    required this.directFileBytes,
    required this.mimeFamilyCounts,
    this.accessible = true,
    this.observationComplete = true,
    this.accessError,
  });

  final String locator;
  final String displayName;
  final List<String> pathSegments;
  final PickLogicPlatform platform;
  final int directFileCount;
  final int directDirectoryCount;
  final int directFileBytes;
  final Map<String, int> mimeFamilyCounts;
  final bool accessible;
  final bool observationComplete;
  final String? accessError;

  String get displayPath => pathSegments.join(' / ');
}

final class FolderInsight {
  const FolderInsight({
    required this.observation,
    required this.role,
    required this.riskLevel,
    required this.confidence,
    required this.evidence,
    this.probableOwner,
  }) : assert(confidence >= 0 && confidence <= 1);

  final FolderObservation observation;
  final FolderRole role;
  final RiskLevel riskLevel;
  final double confidence;
  final List<FolderEvidence> evidence;
  final String? probableOwner;

  bool get unresolved => role == FolderRole.unknown;
}

/// Conservative cross-platform rules for explaining folders from local
/// metadata. Unknown remains unknown; no result implies that deletion is safe.
final class FolderInsightEngine {
  const FolderInsightEngine();

  FolderInsight explain(FolderObservation observation) {
    if (!observation.accessible) {
      return FolderInsight(
        observation: observation,
        role: FolderRole.unknown,
        riskLevel: RiskLevel.unknown,
        confidence: 0,
        evidence: const <FolderEvidence>[FolderEvidence.providerFailure],
      );
    }

    final raw = observation.pathSegments
        .map((segment) => segment.trim())
        .toList(growable: false);
    final normalized = raw.map(_normalize).toList(growable: false);
    final name = normalized.lastOrNull ?? _normalize(observation.displayName);
    final evidence = <FolderEvidence>[
      FolderEvidence.readOnlyMetadata,
      if (!observation.observationComplete) FolderEvidence.boundedObservation,
    ];

    final platformResult = switch (observation.platform) {
      PickLogicPlatform.android => _androidPathRole(raw, normalized),
      PickLogicPlatform.windows => _windowsPathRole(raw, normalized),
      _ => null,
    };
    if (platformResult != null) {
      return _result(
        observation,
        platformResult.role,
        platformResult.risk,
        platformResult.confidence,
        <FolderEvidence>[
          ...evidence,
          FolderEvidence.platformPathConvention,
          if (platformResult.owner != null &&
              _looksLikePackage(platformResult.owner!))
            FolderEvidence.packageIdentifier,
          if (platformResult.parentContext) FolderEvidence.parentContext,
        ],
        owner: platformResult.owner,
      );
    }

    final namedRole = _namedRole(
      name,
      raw.lastOrNull ?? observation.displayName,
    );
    if (namedRole != null) {
      return _result(
        observation,
        namedRole,
        _riskForRole(namedRole),
        _nameConfidence(namedRole),
        <FolderEvidence>[
          ...evidence,
          FolderEvidence.standardFolderName,
          if (namedRole == FolderRole.hidden) FolderEvidence.hiddenName,
        ],
      );
    }

    final contentRole = _contentRole(observation);
    if (contentRole != null) {
      return _result(
        observation,
        contentRole,
        RiskLevel.review,
        contentRole == FolderRole.mixedContent ? 0.52 : 0.7,
        <FolderEvidence>[...evidence, FolderEvidence.directChildMetadata],
      );
    }

    return _result(
      observation,
      FolderRole.unknown,
      RiskLevel.unknown,
      observation.directDirectoryCount > 0 ? 0.2 : 0.12,
      <FolderEvidence>[
        ...evidence,
        if (observation.directFileCount == 0) FolderEvidence.emptyFolder,
      ],
    );
  }

  FolderInsight _result(
    FolderObservation observation,
    FolderRole role,
    RiskLevel risk,
    double confidence,
    List<FolderEvidence> evidence, {
    String? owner,
  }) => FolderInsight(
    observation: observation,
    role: role,
    riskLevel: risk,
    confidence: confidence,
    evidence: List<FolderEvidence>.unmodifiable(evidence),
    probableOwner: owner,
  );

  _PathRole? _androidPathRole(List<String> raw, List<String> normalized) {
    final androidIndex = normalized.indexOf('android');
    if (androidIndex < 0 || androidIndex + 1 >= normalized.length) return null;
    final area = normalized[androidIndex + 1];
    if (area == 'data' || area == 'obb') {
      return const _PathRole(
        FolderRole.systemManaged,
        RiskLevel.protected,
        0.97,
      );
    }
    if (area == 'media' && androidIndex + 2 < raw.length) {
      final owner = raw[androidIndex + 2];
      return _PathRole(
        FolderRole.appSharedMedia,
        RiskLevel.review,
        _looksLikePackage(owner) ? 0.92 : 0.74,
        owner: owner,
        parentContext: true,
      );
    }
    return null;
  }

  _PathRole? _windowsPathRole(List<String> raw, List<String> normalized) {
    if (raw.length == 1 && RegExp(r'^[a-zA-Z]:[\\/]?$').hasMatch(raw.first)) {
      return const _PathRole(FolderRole.driveRoot, RiskLevel.review, 1);
    }
    if (normalized.any(
      (segment) => const <String>{
        'systemvolumeinformation',
        'windowsapps',
        'winsxs',
        'system32',
      }.contains(segment),
    )) {
      return const _PathRole(
        FolderRole.systemManaged,
        RiskLevel.protected,
        0.96,
        parentContext: true,
      );
    }
    if (normalized.any(
      (segment) => segment == r'$recyclebin' || segment == 'recycler',
    )) {
      return const _PathRole(
        FolderRole.trash,
        RiskLevel.protected,
        0.98,
        parentContext: true,
      );
    }
    final windowsIndex = normalized.indexOf('windows');
    if (windowsIndex >= 0) {
      return const _PathRole(
        FolderRole.systemManaged,
        RiskLevel.protected,
        0.92,
        parentContext: true,
      );
    }
    final programIndex = normalized.indexWhere(
      (segment) => segment == 'programfiles' || segment == 'programfilesx86',
    );
    if (programIndex >= 0) {
      return _PathRole(
        FolderRole.applicationInstall,
        RiskLevel.protected,
        0.9,
        owner: _nextMeaningful(raw, programIndex),
        parentContext: true,
      );
    }
    final appDataIndex = normalized.indexOf('appdata');
    final programDataIndex = normalized.indexOf('programdata');
    if (appDataIndex >= 0 || programDataIndex >= 0) {
      final base = appDataIndex >= 0 ? appDataIndex : programDataIndex;
      var ownerIndex = base;
      if (base + 1 < normalized.length &&
          const {
            'local',
            'locallow',
            'roaming',
          }.contains(normalized[base + 1])) {
        ownerIndex++;
      }
      return _PathRole(
        FolderRole.applicationData,
        RiskLevel.review,
        0.86,
        owner: _nextMeaningful(raw, ownerIndex),
        parentContext: true,
      );
    }
    if (normalized.any(
      (segment) =>
          const {'onedrive', 'dropbox', 'googledrive'}.contains(segment),
    )) {
      return const _PathRole(
        FolderRole.cloudSync,
        RiskLevel.review,
        0.88,
        parentContext: true,
      );
    }
    return null;
  }

  String? _nextMeaningful(List<String> raw, int index) {
    for (var cursor = index + 1; cursor < raw.length; cursor++) {
      final value = raw[cursor].trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  FolderRole? _namedRole(String name, String rawName) {
    if (rawName.startsWith('.')) {
      if (name.contains('thumbnail')) return FolderRole.thumbnails;
      if (name.contains('trash')) return FolderRole.trash;
      if (const {
        'git',
        'darttool',
        'gradle',
        'idea',
        'vscode',
      }.contains(name)) {
        return FolderRole.development;
      }
      return FolderRole.hidden;
    }
    if (_oneOf(name, const {'desktop', '桌面'})) return FolderRole.desktop;
    if (_oneOf(name, const {'dcim', 'camera', '相机'})) {
      return FolderRole.camera;
    }
    if (_oneOf(name, const {'screenshot', 'screenshots', '截屏', '截图'})) {
      return FolderRole.screenshots;
    }
    if (_oneOf(name, const {'download', 'downloads', '下载'})) {
      return FolderRole.downloads;
    }
    if (_oneOf(name, const {'document', 'documents', '文档'})) {
      return FolderRole.documents;
    }
    if (_oneOf(name, const {'picture', 'pictures', 'image', 'images', '图片'})) {
      return FolderRole.images;
    }
    if (_oneOf(name, const {'movie', 'movies', 'video', 'videos', '视频'})) {
      return FolderRole.videos;
    }
    if (_oneOf(name, const {'music', 'audio', '音乐'})) {
      return FolderRole.audio;
    }
    if (_oneOf(name, const {'recording', 'recordings', 'recorder', '录音'})) {
      return FolderRole.recordings;
    }
    if (name.contains('thumbnail')) return FolderRole.thumbnails;
    if (_oneOf(name, const {'cache', 'caches'})) return FolderRole.cache;
    if (_oneOf(name, const {'tmp', 'temp', 'temporary'})) {
      return FolderRole.temporary;
    }
    if (_oneOf(name, const {'log', 'logs'})) return FolderRole.logs;
    if (_oneOf(name, const {'backup', 'backups'})) return FolderRole.backups;
    if (_oneOf(name, const {'trash', 'recyclebin', '回收站'})) {
      return FolderRole.trash;
    }
    if (_oneOf(name, const {
      'src',
      'source',
      'scripts',
      'code',
      'build',
      'node_modules',
      'packages',
    })) {
      return FolderRole.development;
    }
    if (_oneOf(name, const {
      'research',
      'rawdata',
      'processeddata',
      'figures',
      'manuscripts',
      'literature',
      'references',
    })) {
      return FolderRole.researchData;
    }
    return null;
  }

  FolderRole? _contentRole(FolderObservation observation) {
    final files = observation.directFileCount;
    if (files == 0) return null;
    final ordered = observation.mimeFamilyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ordered.isEmpty) return FolderRole.mixedContent;
    final dominant = ordered.first;
    if (files >= 2 && dominant.value / files >= 0.7) {
      return switch (dominant.key) {
        'image' => FolderRole.images,
        'video' => FolderRole.videos,
        'audio' => FolderRole.audio,
        'document' => FolderRole.documents,
        'development' => FolderRole.development,
        _ => FolderRole.mixedContent,
      };
    }
    return FolderRole.mixedContent;
  }

  RiskLevel _riskForRole(FolderRole role) => switch (role) {
    FolderRole.systemManaged ||
    FolderRole.applicationInstall ||
    FolderRole.trash => RiskLevel.protected,
    FolderRole.hidden => RiskLevel.unknown,
    _ => RiskLevel.review,
  };

  double _nameConfidence(FolderRole role) => switch (role) {
    FolderRole.desktop ||
    FolderRole.camera ||
    FolderRole.screenshots ||
    FolderRole.downloads ||
    FolderRole.documents ||
    FolderRole.images ||
    FolderRole.videos ||
    FolderRole.audio ||
    FolderRole.recordings => 0.92,
    FolderRole.cache ||
    FolderRole.thumbnails ||
    FolderRole.temporary ||
    FolderRole.logs ||
    FolderRole.backups ||
    FolderRole.development ||
    FolderRole.researchData => 0.78,
    FolderRole.trash => 0.88,
    FolderRole.hidden => 0.44,
    _ => 0.62,
  };
}

final class FolderNode {
  const FolderNode({
    required this.locator,
    required this.displayName,
    required this.pathSegments,
    required this.platform,
  });

  final String locator;
  final String displayName;
  final List<String> pathSegments;
  final PickLogicPlatform platform;
}

final class FolderInspection {
  const FolderInspection({required this.observation, required this.children});

  final FolderObservation observation;
  final List<FolderNode> children;
}

final class FolderScanCancellation {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
}

final class FolderScanProgress {
  const FolderScanProgress({
    required this.scanned,
    required this.pending,
    required this.unresolved,
    required this.failures,
    required this.currentPath,
  });

  final int scanned;
  final int pending;
  final int unresolved;
  final int failures;
  final String currentPath;
}

final class FolderScanResult {
  const FolderScanResult({
    required this.insights,
    required this.rootCount,
    required this.failures,
    required this.complete,
  });

  final List<FolderInsight> insights;
  final int rootCount;
  final int failures;
  final bool complete;

  int get unresolvedCount => insights.where((item) => item.unresolved).length;
}

typedef FolderNodeInspector =
    Future<FolderInspection> Function(
      FolderNode node,
      FolderScanCancellation cancellation,
    );
typedef FolderProgressCallback = void Function(FolderScanProgress progress);
typedef FolderInsightCallback = void Function(FolderInsight insight);

/// Shared breadth-first traversal. Platform adapters provide one metadata-only
/// directory inspection; traversal and explanation stay identical on Android
/// and Windows.
final class FolderTreeScanner {
  const FolderTreeScanner({this.engine = const FolderInsightEngine()});

  final FolderInsightEngine engine;

  Future<FolderScanResult> scan({
    required List<FolderNode> roots,
    required FolderNodeInspector inspector,
    FolderScanCancellation? cancellation,
    FolderProgressCallback? onProgress,
    FolderInsightCallback? onInsight,
  }) async {
    final token = cancellation ?? FolderScanCancellation();
    final queue = ListQueue<FolderNode>()..addAll(roots);
    final visited = <String>{};
    final insights = <FolderInsight>[];
    var failures = 0;
    while (queue.isNotEmpty && !token.cancelled) {
      final node = queue.removeFirst();
      if (!visited.add(node.locator)) continue;
      FolderInspection inspection;
      try {
        inspection = await inspector(node, token);
      } on Object catch (error) {
        inspection = FolderInspection(
          observation: FolderObservation(
            locator: node.locator,
            displayName: node.displayName,
            pathSegments: node.pathSegments,
            platform: node.platform,
            directFileCount: 0,
            directDirectoryCount: 0,
            directFileBytes: 0,
            mimeFamilyCounts: const <String, int>{},
            accessible: false,
            accessError: error.runtimeType.toString(),
          ),
          children: const <FolderNode>[],
        );
      }
      final insight = engine.explain(inspection.observation);
      insights.add(insight);
      if (!inspection.observation.accessible) failures++;
      onInsight?.call(insight);
      if (!token.cancelled) {
        for (final child in inspection.children) {
          if (!visited.contains(child.locator)) queue.add(child);
        }
      }
      onProgress?.call(
        FolderScanProgress(
          scanned: insights.length,
          pending: queue.length,
          unresolved: insights.where((item) => item.unresolved).length,
          failures: failures,
          currentPath: node.pathSegments.join(' / '),
        ),
      );
    }
    insights.sort((a, b) {
      if (a.unresolved != b.unresolved) return a.unresolved ? -1 : 1;
      return a.observation.displayPath.toLowerCase().compareTo(
        b.observation.displayPath.toLowerCase(),
      );
    });
    return FolderScanResult(
      insights: List<FolderInsight>.unmodifiable(insights),
      rootCount: roots.length,
      failures: failures,
      complete: !token.cancelled,
    );
  }
}

final class _PathRole {
  const _PathRole(
    this.role,
    this.risk,
    this.confidence, {
    this.owner,
    this.parentContext = false,
  });

  final FolderRole role;
  final RiskLevel risk;
  final double confidence;
  final String? owner;
  final bool parentContext;
}

String _normalize(String value) =>
    value.replaceAll(RegExp(r'[\s._-]+'), '').toLowerCase();

bool _oneOf(String value, Set<String> choices) => choices.contains(value);

bool _looksLikePackage(String value) =>
    RegExp(r'^[a-zA-Z][\w]*(\.[a-zA-Z][\w]*)+$').hasMatch(value);
