import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

import 'mobile_repository.dart';

enum AndroidFolderRole {
  camera,
  screenshots,
  downloads,
  documents,
  images,
  videos,
  audio,
  recordings,
  appSharedMedia,
  cache,
  thumbnails,
  temporary,
  logs,
  backups,
  androidManaged,
  trash,
  hidden,
  mixedContent,
  unknown,
}

enum FolderInsightEvidence {
  authorizedAccess,
  standardFolderName,
  androidPathConvention,
  packageIdentifier,
  directChildMetadata,
  hiddenName,
  emptyFolder,
  providerFailure,
}

/// A metadata-only observation of one user-authorized Android folder.
final class AndroidFolderObservation {
  const AndroidFolderObservation({
    required this.treeUri,
    required this.documentUri,
    required this.displayName,
    required this.pathSegments,
    required this.directFileCount,
    required this.directDirectoryCount,
    required this.directFileBytes,
    required this.mimeFamilyCounts,
    this.accessError,
  });

  final String treeUri;
  final String documentUri;
  final String displayName;
  final List<String> pathSegments;
  final int directFileCount;
  final int directDirectoryCount;
  final int directFileBytes;
  final Map<String, int> mimeFamilyCounts;
  final String? accessError;

  String get displayPath => pathSegments.join(' / ');
  bool get accessible => accessError == null;
}

final class AndroidFolderInsight {
  const AndroidFolderInsight({
    required this.observation,
    required this.role,
    required this.riskLevel,
    required this.confidence,
    required this.evidence,
    this.packageIdentifier,
  }) : assert(confidence >= 0 && confidence <= 1);

  final AndroidFolderObservation observation;
  final AndroidFolderRole role;
  final RiskLevel riskLevel;
  final double confidence;
  final List<FolderInsightEvidence> evidence;
  final String? packageIdentifier;

  bool get unresolved => role == AndroidFolderRole.unknown;
}

/// Conservative, deterministic folder explanations based only on names,
/// platform path conventions, and direct-child metadata.
final class AndroidFolderInsightEngine {
  const AndroidFolderInsightEngine();

  AndroidFolderInsight explain(AndroidFolderObservation observation) {
    if (!observation.accessible) {
      return AndroidFolderInsight(
        observation: observation,
        role: AndroidFolderRole.unknown,
        riskLevel: RiskLevel.unknown,
        confidence: 1,
        evidence: const <FolderInsightEvidence>[
          FolderInsightEvidence.providerFailure,
        ],
      );
    }

    final rawSegments = observation.pathSegments
        .map((segment) => segment.trim().toLowerCase())
        .toList(growable: false);
    final segments = rawSegments.map(_normalize).toList(growable: false);
    final name = segments.isEmpty ? '' : segments.last;
    final evidence = <FolderInsightEvidence>[
      FolderInsightEvidence.authorizedAccess,
    ];

    final androidIndex = segments.indexOf('android');
    if (androidIndex >= 0 && androidIndex + 1 < segments.length) {
      final area = segments[androidIndex + 1];
      if (area == 'data' || area == 'obb') {
        return AndroidFolderInsight(
          observation: observation,
          role: AndroidFolderRole.androidManaged,
          riskLevel: RiskLevel.protected,
          confidence: 0.96,
          evidence: <FolderInsightEvidence>[
            ...evidence,
            FolderInsightEvidence.androidPathConvention,
          ],
        );
      }
      if (area == 'media' && androidIndex + 2 < rawSegments.length) {
        final package = rawSegments[androidIndex + 2];
        return AndroidFolderInsight(
          observation: observation,
          role: AndroidFolderRole.appSharedMedia,
          riskLevel: RiskLevel.review,
          confidence: _looksLikePackage(package) ? 0.9 : 0.74,
          packageIdentifier: package,
          evidence: <FolderInsightEvidence>[
            ...evidence,
            FolderInsightEvidence.androidPathConvention,
            if (_looksLikePackage(package))
              FolderInsightEvidence.packageIdentifier,
          ],
        );
      }
    }

    final namedRole = _namedRole(name, rawSegments.lastOrNull ?? '');
    if (namedRole != null) {
      final risk = switch (namedRole) {
        AndroidFolderRole.androidManaged ||
        AndroidFolderRole.trash => RiskLevel.protected,
        AndroidFolderRole.hidden => RiskLevel.unknown,
        _ => RiskLevel.review,
      };
      return AndroidFolderInsight(
        observation: observation,
        role: namedRole,
        riskLevel: risk,
        confidence: _nameConfidence(namedRole),
        evidence: <FolderInsightEvidence>[
          ...evidence,
          FolderInsightEvidence.standardFolderName,
          if (namedRole == AndroidFolderRole.hidden)
            FolderInsightEvidence.hiddenName,
        ],
      );
    }

    final contentRole = _contentRole(observation);
    if (contentRole != null) {
      return AndroidFolderInsight(
        observation: observation,
        role: contentRole,
        riskLevel: RiskLevel.review,
        confidence: contentRole == AndroidFolderRole.mixedContent ? 0.52 : 0.68,
        evidence: <FolderInsightEvidence>[
          ...evidence,
          FolderInsightEvidence.directChildMetadata,
        ],
      );
    }

    return AndroidFolderInsight(
      observation: observation,
      role: AndroidFolderRole.unknown,
      riskLevel: RiskLevel.unknown,
      confidence: observation.directDirectoryCount > 0 ? 0.32 : 0.22,
      evidence: <FolderInsightEvidence>[
        ...evidence,
        if (observation.directFileCount == 0) FolderInsightEvidence.emptyFolder,
      ],
    );
  }

  AndroidFolderRole? _namedRole(String name, String rawName) {
    if (rawName.startsWith('.')) {
      if (name.contains('thumbnail')) return AndroidFolderRole.thumbnails;
      if (name.contains('trash')) return AndroidFolderRole.trash;
      return AndroidFolderRole.hidden;
    }
    if (_oneOf(name, const {'dcim', 'camera', '相机'})) {
      return AndroidFolderRole.camera;
    }
    if (_oneOf(name, const {'screenshot', 'screenshots', '截屏', '截图'})) {
      return AndroidFolderRole.screenshots;
    }
    if (_oneOf(name, const {'download', 'downloads', '下载'})) {
      return AndroidFolderRole.downloads;
    }
    if (_oneOf(name, const {'document', 'documents', '文档'})) {
      return AndroidFolderRole.documents;
    }
    if (_oneOf(name, const {'picture', 'pictures', 'image', 'images', '图片'})) {
      return AndroidFolderRole.images;
    }
    if (_oneOf(name, const {'movie', 'movies', 'video', 'videos', '视频'})) {
      return AndroidFolderRole.videos;
    }
    if (_oneOf(name, const {'music', 'audio', '音乐'})) {
      return AndroidFolderRole.audio;
    }
    if (_oneOf(name, const {'recording', 'recordings', 'recorder', '录音'})) {
      return AndroidFolderRole.recordings;
    }
    if (name.contains('thumbnail')) return AndroidFolderRole.thumbnails;
    if (_oneOf(name, const {'cache', 'caches'})) {
      return AndroidFolderRole.cache;
    }
    if (_oneOf(name, const {'tmp', 'temp', 'temporary'})) {
      return AndroidFolderRole.temporary;
    }
    if (_oneOf(name, const {'log', 'logs'})) return AndroidFolderRole.logs;
    if (_oneOf(name, const {'backup', 'backups'})) {
      return AndroidFolderRole.backups;
    }
    if (_oneOf(name, const {'trash', 'recyclebin', '回收站'})) {
      return AndroidFolderRole.trash;
    }
    return null;
  }

  AndroidFolderRole? _contentRole(AndroidFolderObservation observation) {
    final files = observation.directFileCount;
    if (files == 0) return null;
    final ordered = observation.mimeFamilyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ordered.isEmpty) return AndroidFolderRole.mixedContent;
    final dominant = ordered.first;
    if (files >= 2 && dominant.value / files >= 0.7) {
      return switch (dominant.key) {
        'image' => AndroidFolderRole.images,
        'video' => AndroidFolderRole.videos,
        'audio' => AndroidFolderRole.audio,
        'document' => AndroidFolderRole.documents,
        _ => AndroidFolderRole.mixedContent,
      };
    }
    return AndroidFolderRole.mixedContent;
  }

  double _nameConfidence(AndroidFolderRole role) => switch (role) {
    AndroidFolderRole.camera ||
    AndroidFolderRole.screenshots ||
    AndroidFolderRole.downloads ||
    AndroidFolderRole.documents ||
    AndroidFolderRole.images ||
    AndroidFolderRole.videos ||
    AndroidFolderRole.audio ||
    AndroidFolderRole.recordings => 0.9,
    AndroidFolderRole.cache ||
    AndroidFolderRole.thumbnails ||
    AndroidFolderRole.temporary ||
    AndroidFolderRole.logs ||
    AndroidFolderRole.backups => 0.76,
    AndroidFolderRole.trash => 0.84,
    AndroidFolderRole.hidden => 0.45,
    _ => 0.6,
  };
}

typedef FolderRootLoader = Future<List<AndroidBrowseRoot>> Function();
typedef FolderPageLoader =
    Future<AndroidBrowsePage?> Function({
      required String treeUri,
      required String directoryUri,
      required int offset,
      required int limit,
    });

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

  final List<AndroidFolderInsight> insights;
  final int rootCount;
  final int failures;
  final bool complete;

  int get unresolvedCount => insights.where((item) => item.unresolved).length;
}

/// Breadth-first, paged traversal of every folder inside persisted SAF roots.
/// No file body, thumbnail, hash, OCR, or mutating API is used.
final class AndroidFolderInsightScanner {
  AndroidFolderInsightScanner({
    required this.loadRoots,
    required this.loadPage,
    this.engine = const AndroidFolderInsightEngine(),
  });

  factory AndroidFolderInsightScanner.fromRepository(
    MobileRepository repository,
  ) => AndroidFolderInsightScanner(
    loadRoots: repository.loadBrowseRoots,
    loadPage:
        ({
          required treeUri,
          required directoryUri,
          required offset,
          required limit,
        }) => repository.loadBrowseDirectory(
          treeUri: treeUri,
          directoryUri: directoryUri,
          offset: offset,
          limit: limit,
        ),
  );

  final FolderRootLoader loadRoots;
  final FolderPageLoader loadPage;
  final AndroidFolderInsightEngine engine;

  Future<FolderScanResult> scan({
    FolderScanCancellation? cancellation,
    ValueChanged<FolderScanProgress>? onProgress,
  }) async {
    final token = cancellation ?? FolderScanCancellation();
    final roots = await loadRoots();
    final queue = ListQueue<_FolderTask>();
    final visited = <String>{};
    for (final root in roots) {
      queue.add(
        _FolderTask(
          root: root,
          directoryUri: root.documentUri,
          displayName: root.displayName,
          pathSegments: <String>[root.displayName],
        ),
      );
    }
    final insights = <AndroidFolderInsight>[];
    var failures = 0;
    while (queue.isNotEmpty && !token.cancelled) {
      final task = queue.removeFirst();
      if (!visited.add(task.directoryUri)) continue;
      final inspected = await _inspect(task);
      insights.add(inspected.insight);
      if (!inspected.insight.observation.accessible) failures++;
      for (final child in inspected.directories) {
        if (!visited.contains(child.documentUri)) {
          queue.add(
            _FolderTask(
              root: task.root,
              directoryUri: child.documentUri,
              displayName: child.displayName,
              pathSegments: <String>[...task.pathSegments, child.displayName],
            ),
          );
        }
      }
      onProgress?.call(
        FolderScanProgress(
          scanned: insights.length,
          pending: queue.length,
          unresolved: insights.where((item) => item.unresolved).length,
          failures: failures,
          currentPath: task.pathSegments.join(' / '),
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
      insights: List<AndroidFolderInsight>.unmodifiable(insights),
      rootCount: roots.length,
      failures: failures,
      complete: !token.cancelled,
    );
  }

  Future<AndroidFolderInsight> inspectFolder({
    required AndroidBrowseRoot root,
    required String directoryUri,
    required String displayName,
    required List<String> pathSegments,
  }) async => (await _inspect(
    _FolderTask(
      root: root,
      directoryUri: directoryUri,
      displayName: displayName,
      pathSegments: pathSegments,
    ),
  )).insight;

  Future<_InspectedFolder> _inspect(_FolderTask task) async {
    final entries = <AndroidBrowseEntry>[];
    try {
      var offset = 0;
      while (true) {
        final page = await loadPage(
          treeUri: task.root.treeUri,
          directoryUri: task.directoryUri,
          offset: offset,
          limit: 250,
        );
        if (page == null) {
          throw StateError('The Android document provider returned no page.');
        }
        entries.addAll(page.items);
        if (!page.hasMore) break;
        if (page.items.isEmpty) {
          throw StateError('The Android document provider did not advance.');
        }
        offset += page.items.length;
      }
      final files = entries.where((entry) => !entry.directory).toList();
      final families = <String, int>{};
      for (final file in files) {
        final family = _mimeFamily(file.mimeType, file.displayName);
        families.update(family, (count) => count + 1, ifAbsent: () => 1);
      }
      final observation = AndroidFolderObservation(
        treeUri: task.root.treeUri,
        documentUri: task.directoryUri,
        displayName: task.displayName,
        pathSegments: List<String>.unmodifiable(task.pathSegments),
        directFileCount: files.length,
        directDirectoryCount: entries.where((entry) => entry.directory).length,
        directFileBytes: files.fold<int>(
          0,
          (total, entry) => total + entry.sizeBytes,
        ),
        mimeFamilyCounts: Map<String, int>.unmodifiable(families),
      );
      return _InspectedFolder(
        insight: engine.explain(observation),
        directories: entries.where((entry) => entry.directory).toList(),
      );
    } on Object catch (error) {
      final observation = AndroidFolderObservation(
        treeUri: task.root.treeUri,
        documentUri: task.directoryUri,
        displayName: task.displayName,
        pathSegments: List<String>.unmodifiable(task.pathSegments),
        directFileCount: 0,
        directDirectoryCount: 0,
        directFileBytes: 0,
        mimeFamilyCounts: const <String, int>{},
        accessError: error.runtimeType.toString(),
      );
      return _InspectedFolder(
        insight: engine.explain(observation),
        directories: const <AndroidBrowseEntry>[],
      );
    }
  }
}

final class AccessibleFolderInsightSection extends StatefulWidget {
  const AccessibleFolderInsightSection({super.key, required this.repository});

  final MobileRepository repository;

  @override
  State<AccessibleFolderInsightSection> createState() =>
      _AccessibleFolderInsightSectionState();
}

final class _AccessibleFolderInsightSectionState
    extends State<AccessibleFolderInsightSection> {
  List<AndroidBrowseRoot> _roots = const <AndroidBrowseRoot>[];
  FolderScanProgress? _progress;
  FolderScanResult? _result;
  FolderScanCancellation? _cancellation;
  bool _loadingRoots = true;
  bool _addingRoot = false;
  bool _scanning = false;
  bool _rootLoadFailed = false;
  bool _scanFailed = false;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  _FolderInsightStrings get _strings => _FolderInsightStrings(_zh);

  @override
  void initState() {
    super.initState();
    unawaited(_refreshRoots());
  }

  @override
  void didUpdateWidget(covariant AccessibleFolderInsightSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) unawaited(_refreshRoots());
  }

  Future<void> _refreshRoots() async {
    if (mounted) setState(() => _loadingRoots = true);
    try {
      final roots = await widget.repository.loadBrowseRoots();
      if (!mounted) return;
      setState(() {
        _roots = roots;
        _rootLoadFailed = false;
      });
    } on Object {
      if (mounted) setState(() => _rootLoadFailed = true);
    } finally {
      if (mounted) setState(() => _loadingRoots = false);
    }
  }

  Future<void> _addRoot() async {
    setState(() => _addingRoot = true);
    try {
      final selected = await widget.repository.chooseDocumentTree();
      if (selected != null) await _refreshRoots();
    } on Object {
      if (mounted) setState(() => _rootLoadFailed = true);
    } finally {
      if (mounted) setState(() => _addingRoot = false);
    }
  }

  Future<void> _scan() async {
    if (_scanning || _roots.isEmpty) return;
    final cancellation = FolderScanCancellation();
    _cancellation = cancellation;
    setState(() {
      _scanning = true;
      _progress = null;
      _scanFailed = false;
    });
    var lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final result =
          await AndroidFolderInsightScanner.fromRepository(
            widget.repository,
          ).scan(
            cancellation: cancellation,
            onProgress: (progress) {
              final now = DateTime.now();
              if (!mounted ||
                  now.difference(lastUiUpdate).inMilliseconds < 100) {
                return;
              }
              lastUiUpdate = now;
              setState(() => _progress = progress);
            },
          );
      if (mounted) setState(() => _result = result);
    } on Object {
      if (mounted) setState(() => _scanFailed = true);
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
          _cancellation = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _strings;
    final result = _result;
    final preview =
        result?.insights.take(6).toList() ?? const <AndroidFolderInsight>[];
    return Card(
      key: const Key('accessible-folder-insight-section'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_special_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.sectionTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(strings.sectionBody),
            const SizedBox(height: 12),
            if (_loadingRoots) const LinearProgressIndicator(),
            if (_rootLoadFailed) Text(strings.rootLoadFailed),
            if (!_loadingRoots)
              Text(
                strings.rootCount(_roots.length),
                key: const Key('folder-root-count'),
              ),
            if (_scanning) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(
                strings.progress(_progress),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (_scanFailed) ...[
              const SizedBox(height: 8),
              Text(strings.scanFailed),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('folder-insight-scan'),
                  onPressed: _roots.isEmpty || _scanning ? null : _scan,
                  icon: const Icon(Icons.manage_search_outlined),
                  label: Text(strings.scan),
                ),
                OutlinedButton.icon(
                  key: const Key('folder-insight-add-root'),
                  onPressed: _addingRoot || _scanning ? null : _addRoot,
                  icon: const Icon(Icons.add),
                  label: Text(strings.addRoot),
                ),
                if (_scanning)
                  TextButton.icon(
                    onPressed: _cancellation?.cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(strings.stop),
                  ),
              ],
            ),
            if (result != null) ...[
              const Divider(height: 24),
              Text(
                strings.summary(result),
                key: const Key('folder-insight-summary'),
              ),
              const SizedBox(height: 6),
              for (final insight in preview)
                _FolderInsightTile(insight: insight, strings: strings),
              if (result.insights.length > preview.length)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('folder-insight-view-all'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (context) =>
                            FolderInsightResultsPage(result: result),
                      ),
                    ),
                    icon: const Icon(Icons.list_alt_outlined),
                    label: Text(strings.viewAll(result.insights.length)),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(strings.safety, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

final class FolderInsightResultsPage extends StatefulWidget {
  const FolderInsightResultsPage({super.key, required this.result});

  final FolderScanResult result;

  @override
  State<FolderInsightResultsPage> createState() =>
      _FolderInsightResultsPageState();
}

final class _FolderInsightResultsPageState
    extends State<FolderInsightResultsPage> {
  final TextEditingController _search = TextEditingController();
  bool _unresolvedOnly = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = _FolderInsightStrings(
      Localizations.localeOf(context).languageCode == 'zh',
    );
    final query = _search.text.trim().toLowerCase();
    final visible = widget.result.insights
        .where((insight) {
          if (_unresolvedOnly && !insight.unresolved) return false;
          return query.isEmpty ||
              insight.observation.displayPath.toLowerCase().contains(query);
        })
        .toList(growable: false);
    return Scaffold(
      key: const Key('folder-insight-results-page'),
      appBar: AppBar(title: Text(strings.sectionTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: strings.search,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: Text(strings.unresolvedOnly),
                  selected: _unresolvedOnly,
                  onSelected: (value) =>
                      setState(() => _unresolvedOnly = value),
                ),
                const SizedBox(width: 8),
                Text(strings.visible(visible.length)),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text(strings.noMatches))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    itemBuilder: (context, index) => _FolderInsightTile(
                      insight: visible[index],
                      strings: strings,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> showAndroidFolderInsightSheet({
  required BuildContext context,
  required MobileRepository repository,
  required AndroidBrowseRoot root,
  required String directoryUri,
  required String displayName,
  required List<String> pathSegments,
}) async {
  final future = AndroidFolderInsightScanner.fromRepository(repository)
      .inspectFolder(
        root: root,
        directoryUri: directoryUri,
        displayName: displayName,
        pathSegments: pathSegments,
      );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.82,
      child: FutureBuilder<AndroidFolderInsight>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return FolderInsightDetails(insight: snapshot.data!);
        },
      ),
    ),
  );
}

final class FolderInsightDetails extends StatelessWidget {
  const FolderInsightDetails({super.key, required this.insight});

  final AndroidFolderInsight insight;

  @override
  Widget build(BuildContext context) {
    final strings = _FolderInsightStrings(
      Localizations.localeOf(context).languageCode == 'zh',
    );
    final observation = insight.observation;
    return ListView(
      key: const Key('folder-insight-details'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Text(
          observation.displayName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        SelectableText(observation.displayPath),
        const SizedBox(height: 16),
        _InsightSection(
          title: strings.whatItIs,
          child: Text(strings.purpose(insight)),
        ),
        _InsightSection(
          title: strings.facts,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.access(observation)),
              Text(strings.children(observation)),
              Text(strings.directSize(observation.directFileBytes)),
            ],
          ),
        ),
        _InsightSection(
          title: strings.inference,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.owner(insight)),
              Text(strings.origin(insight)),
              Text(strings.why(insight)),
              Text(strings.confidence(insight.confidence)),
              Text(strings.risk(insight.riskLevel)),
            ],
          ),
        ),
        _InsightSection(
          title: strings.evidence,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final evidence in insight.evidence)
                Text('• ${strings.evidenceText(evidence)}'),
            ],
          ),
        ),
        _InsightSection(
          title: strings.recommendation,
          child: Text(strings.recommendationText(insight)),
        ),
        _InsightSection(
          title: strings.limitations,
          child: Text(strings.limitationText(insight)),
        ),
      ],
    );
  }
}

final class _FolderInsightTile extends StatelessWidget {
  const _FolderInsightTile({required this.insight, required this.strings});

  final AndroidFolderInsight insight;
  final _FolderInsightStrings strings;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      insight.unresolved ? Icons.help_outline : Icons.folder_special_outlined,
    ),
    title: Text(
      insight.observation.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      '${strings.role(insight.role)} · ${strings.confidence(insight.confidence)}\n'
      '${insight.observation.displayPath}',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
    isThreeLine: true,
    trailing: const Icon(Icons.info_outline),
    onTap: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.82,
        child: FolderInsightDetails(insight: insight),
      ),
    ),
  );
}

final class _InsightSection extends StatelessWidget {
  const _InsightSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

final class _FolderTask {
  const _FolderTask({
    required this.root,
    required this.directoryUri,
    required this.displayName,
    required this.pathSegments,
  });

  final AndroidBrowseRoot root;
  final String directoryUri;
  final String displayName;
  final List<String> pathSegments;
}

final class _InspectedFolder {
  const _InspectedFolder({required this.insight, required this.directories});

  final AndroidFolderInsight insight;
  final List<AndroidBrowseEntry> directories;
}

final class _FolderInsightStrings {
  const _FolderInsightStrings(this.zh);

  final bool zh;

  String get sectionTitle => zh ? '可访问文件夹知件' : 'Accessible folder Insight';
  String get sectionBody => zh
      ? '逐层读取已授权目录的名称和直接子项元数据，解释每个文件夹；未知不等于垃圾。'
      : 'Read authorized folder names and direct-child metadata recursively to explain every folder. Unknown never means junk.';
  String get scan => zh ? '分析全部已授权文件夹' : 'Analyze all authorized folders';
  String get addRoot => zh ? '添加只读目录' : 'Add read-only folder';
  String get stop => zh ? '停止' : 'Stop';
  String get search => zh ? '搜索文件夹名称或路径' : 'Search folder name or path';
  String get unresolvedOnly => zh ? '只看尚未识别' : 'Unresolved only';
  String get noMatches => zh ? '没有匹配的文件夹' : 'No matching folders';
  String get rootLoadFailed => zh
      ? 'Android 文件夹授权状态暂时不可读取；请重试或重新添加目录。'
      : 'Android folder authorization is temporarily unavailable. Retry or add the folder again.';
  String get scanFailed => zh
      ? '目录分析未完成；未修改任何文件，可直接重试。'
      : 'Folder analysis did not finish. No file was modified; you can retry safely.';
  String get whatItIs => zh ? '这是什么' : 'What it is';
  String get facts => zh ? '已验证事实' : 'Verified facts';
  String get inference => zh ? '规则推断' : 'Rule inference';
  String get evidence => zh ? '判断证据' : 'Evidence';
  String get recommendation => zh ? '建议操作' : 'Recommended action';
  String get limitations => zh ? '无法确认的部分' : 'Limitations';
  String get safety => zh
      ? '只读：不打开文件正文，不做 OCR、哈希、移动、重命名或删除。Android 私有目录仍不可访问。'
      : 'Read-only: no file bodies, OCR, hashing, moves, renames, or deletion. Android private directories remain inaccessible.';

  String rootCount(int count) => zh
      ? '已授权 $count 个根目录。可继续添加 Android 选择器允许访问的共享目录；系统可能禁止选择整个存储卷。'
      : '$count authorized root(s). Add any shared folders allowed by Android; the system may block selecting an entire storage volume.';
  String visible(int count) => zh ? '显示 $count 项' : '$count shown';
  String viewAll(int count) =>
      zh ? '查看全部 $count 个文件夹' : 'View all $count folders';
  String progress(FolderScanProgress? progress) {
    if (progress == null) return zh ? '正在准备…' : 'Preparing…';
    return zh
        ? '已分析 ${progress.scanned}，待分析 ${progress.pending}，尚未识别 ${progress.unresolved}：${progress.currentPath}'
        : 'Analyzed ${progress.scanned}; pending ${progress.pending}; unresolved ${progress.unresolved}: ${progress.currentPath}';
  }

  String summary(FolderScanResult result) {
    final state = result.complete
        ? (zh ? '扫描完成' : 'Scan complete')
        : (zh ? '扫描已停止' : 'Scan stopped');
    return zh
        ? '$state：已解释 ${result.insights.length} 个文件夹，其中 ${result.unresolvedCount} 个证据不足，${result.failures} 个无法读取。'
        : '$state: explained ${result.insights.length} folders; ${result.unresolvedCount} remain unresolved and ${result.failures} could not be read.';
  }

  String role(AndroidFolderRole role) => switch (role) {
    AndroidFolderRole.camera => zh ? '相机媒体目录' : 'Camera media',
    AndroidFolderRole.screenshots => zh ? '截图目录' : 'Screenshots',
    AndroidFolderRole.downloads => zh ? '下载目录' : 'Downloads',
    AndroidFolderRole.documents => zh ? '文档集合' : 'Documents',
    AndroidFolderRole.images => zh ? '图片集合' : 'Image collection',
    AndroidFolderRole.videos => zh ? '视频集合' : 'Video collection',
    AndroidFolderRole.audio => zh ? '音频集合' : 'Audio collection',
    AndroidFolderRole.recordings => zh ? '录音目录' : 'Recordings',
    AndroidFolderRole.appSharedMedia => zh ? '应用共享媒体' : 'App shared media',
    AndroidFolderRole.cache => zh ? '缓存线索' : 'Cache clue',
    AndroidFolderRole.thumbnails => zh ? '缩略图缓存线索' : 'Thumbnail cache clue',
    AndroidFolderRole.temporary => zh ? '临时文件线索' : 'Temporary-file clue',
    AndroidFolderRole.logs => zh ? '日志线索' : 'Log clue',
    AndroidFolderRole.backups => zh ? '备份线索' : 'Backup clue',
    AndroidFolderRole.androidManaged =>
      zh ? 'Android 管理目录' : 'Android-managed area',
    AndroidFolderRole.trash => zh ? '系统/应用回收目录' : 'System/app trash area',
    AndroidFolderRole.hidden => zh ? '隐藏目录' : 'Hidden folder',
    AndroidFolderRole.mixedContent => zh ? '混合内容目录' : 'Mixed-content folder',
    AndroidFolderRole.unknown => zh ? '尚未识别' : 'Unresolved',
  };

  String purpose(AndroidFolderInsight insight) {
    if (insight.unresolved) {
      return zh
          ? '现有名称和直接子项元数据不足以确定用途；这不代表它无用或可以删除。'
          : 'Its name and direct-child metadata are insufficient to determine a purpose. This does not mean it is useless or safe to delete.';
    }
    return zh
        ? '最可能是“${role(insight.role)}”。该结论来自下方证据，不是文件内容鉴定。'
        : 'Most likely: ${role(insight.role)}. This is evidence-based metadata inference, not file-content inspection.';
  }

  String owner(AndroidFolderInsight insight) {
    final package = insight.packageIdentifier;
    if (package != null) {
      return zh ? '可能所属应用：$package' : 'Probable app package: $package';
    }
    return switch (insight.role) {
      AndroidFolderRole.androidManaged || AndroidFolderRole.trash =>
        zh
            ? '可能所有者：Android 或创建它的应用'
            : 'Probable owner: Android or the creating app',
      AndroidFolderRole.camera ||
      AndroidFolderRole.screenshots ||
      AndroidFolderRole.downloads ||
      AndroidFolderRole.documents ||
      AndroidFolderRole.images ||
      AndroidFolderRole.videos ||
      AndroidFolderRole.audio ||
      AndroidFolderRole.recordings =>
        zh
            ? '可能所有者：用户或相关系统应用'
            : 'Probable owner: the user or a related system app',
      _ => zh ? '可能所有者：无法确认' : 'Probable owner: not confirmed',
    };
  }

  String origin(AndroidFolderInsight insight) => zh
      ? '来源：用户通过 Android SAF 明确授权的共享存储范围'
      : 'Origin: shared storage explicitly authorized through Android SAF';

  String why(AndroidFolderInsight insight) => switch (insight.role) {
    AndroidFolderRole.appSharedMedia =>
      zh
          ? '存在原因：应用用于保存可共享或可导出的媒体。'
          : 'Why it exists: an app stores shareable or exported media here.',
    AndroidFolderRole.cache ||
    AndroidFolderRole.thumbnails ||
    AndroidFolderRole.temporary =>
      zh
          ? '存在原因：可能用于加速显示或保存临时结果；仅凭名称不能判断是否可清理。'
          : 'Why it exists: it may speed up display or hold temporary results; its name alone cannot prove it is cleanable.',
    AndroidFolderRole.unknown =>
      zh
          ? '存在原因：尚无足够证据。'
          : 'Why it exists: evidence is currently insufficient.',
    _ =>
      zh
          ? '存在原因：用于组织对应类别的本地文件。'
          : 'Why it exists: it organizes the corresponding local content.',
  };

  String access(AndroidFolderObservation observation) => observation.accessible
      ? (zh ? '访问状态：已授权、只读' : 'Access: authorized, read-only')
      : (zh
            ? '访问状态：Android 提供程序未返回内容'
            : 'Access: Android provider did not return content');

  String children(AndroidFolderObservation observation) => zh
      ? '当前层：${observation.directDirectoryCount} 个子目录，${observation.directFileCount} 个文件'
      : 'Direct children: ${observation.directDirectoryCount} folders and ${observation.directFileCount} files';

  String directSize(int bytes) => zh
      ? '当前层文件合计：${_folderBytes(bytes)}'
      : 'Direct-file total: ${_folderBytes(bytes)}';

  String confidence(double value) => zh
      ? '置信度 ${(value * 100).round()}%'
      : '${(value * 100).round()}% confidence';

  String risk(RiskLevel risk) =>
      zh ? '风险：${_riskName(risk)}' : 'Risk: ${_riskName(risk)}';

  String _riskName(RiskLevel risk) => switch (risk) {
    RiskLevel.safe => zh ? '可安全处理' : 'Safe',
    RiskLevel.review => zh ? '需要审查' : 'Review',
    RiskLevel.protected => zh ? '受保护' : 'Protected',
    RiskLevel.unknown => zh ? '未知' : 'Unknown',
  };

  String evidenceText(FolderInsightEvidence evidence) => switch (evidence) {
    FolderInsightEvidence.authorizedAccess =>
      zh
          ? 'Android 文档提供程序确认该目录位于已授权范围。'
          : 'Android confirms this folder is inside an authorized document tree.',
    FolderInsightEvidence.standardFolderName =>
      zh
          ? '目录名称匹配常见 Android/用户文件夹约定。'
          : 'The name matches a common Android or user-folder convention.',
    FolderInsightEvidence.androidPathConvention =>
      zh
          ? '路径匹配 Android 共享存储结构约定。'
          : 'The path matches an Android shared-storage convention.',
    FolderInsightEvidence.packageIdentifier =>
      zh
          ? '路径中出现形如应用包名的标识；未据此断言具体应用身份。'
          : 'A package-like identifier appears in the path; app identity is not asserted.',
    FolderInsightEvidence.directChildMetadata =>
      zh
          ? '直接子项的 MIME 类型构成提供了内容线索。'
          : 'Direct-child MIME families provide a content clue.',
    FolderInsightEvidence.hiddenName =>
      zh
          ? '名称以点开头，只能确认它是隐藏目录。'
          : 'A dot-prefixed name confirms only that this is a hidden folder.',
    FolderInsightEvidence.emptyFolder =>
      zh
          ? '当前层没有可见文件，无法从内容构成推断。'
          : 'No directly visible files are available for a content inference.',
    FolderInsightEvidence.providerFailure =>
      zh
          ? 'Android 文档提供程序拒绝或未能读取该目录。'
          : 'The Android document provider denied or failed this directory read.',
  };

  String recommendationText(AndroidFolderInsight insight) {
    if (insight.riskLevel == RiskLevel.protected) {
      return zh
          ? '保留原状；如需处理，请先在系统或对应应用设置中确认用途。'
          : 'Leave it unchanged. Confirm its purpose in Android or the related app settings before any action.';
    }
    if (insight.unresolved || insight.riskLevel == RiskLevel.unknown) {
      return zh
          ? '先进入目录查看文件类型和来源；在理解用途前不要删除、移动或重命名。'
          : 'Inspect its contents and origin first. Do not delete, move, or rename it until its purpose is understood.';
    }
    return zh
        ? '可继续查看内容并按需分类；当前知件不提供直接清理操作。'
        : 'You may inspect and classify its contents. Insight does not offer direct cleanup here.';
  }

  String limitationText(AndroidFolderInsight insight) {
    if (!insight.observation.accessible) {
      return zh
          ? '当前授权或文档提供程序不允许读取；PickLogic 不会绕过 Android 限制。'
          : 'Current authorization or the document provider blocks the read; PickLogic will not bypass Android restrictions.';
    }
    return zh
        ? '只检查目录名、路径结构和直接子项元数据；不读取文件正文，也不能访问其他应用私有目录。'
        : 'Only the name, path structure, and direct-child metadata were checked. File bodies and other apps’ private directories remain inaccessible.';
  }
}

String _normalize(String value) =>
    value.replaceAll(RegExp(r'[\s._-]+'), '').toLowerCase();

bool _oneOf(String value, Set<String> choices) => choices.contains(value);

bool _looksLikePackage(String value) =>
    RegExp(r'^[a-zA-Z][\w]*(\.[a-zA-Z][\w]*)+$').hasMatch(value);

String _mimeFamily(String mimeType, String displayName) {
  final mime = mimeType.toLowerCase();
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  if (mime.startsWith('audio/')) return 'audio';
  if (mime.startsWith('text/') ||
      mime == 'application/pdf' ||
      mime.contains('document') ||
      mime.contains('sheet') ||
      mime.contains('presentation')) {
    return 'document';
  }
  if (mime.contains('zip') ||
      mime.contains('archive') ||
      RegExp(
        r'\.(zip|7z|rar|tar|gz)$',
        caseSensitive: false,
      ).hasMatch(displayName)) {
    return 'archive';
  }
  if (mime == 'application/vnd.android.package-archive' ||
      displayName.toLowerCase().endsWith('.apk')) {
    return 'application';
  }
  return 'other';
}

String _folderBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
