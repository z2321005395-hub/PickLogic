import 'package:picklogic_core_models/picklogic_core_models.dart';

import 'library_catalog.dart';

final class LiteratureDuplicateGroup {
  const LiteratureDuplicateGroup({
    required this.entries,
    required this.reasons,
  });

  final List<LiteratureLibraryEntry> entries;
  final List<String> reasons;
}

/// High-confidence bibliographic duplicate detection.
///
/// It intentionally avoids fuzzy guesses that could merge distinct papers.
final class LiteratureReferenceDuplicateDetector {
  const LiteratureReferenceDuplicateDetector();

  List<LiteratureDuplicateGroup> find(
    Iterable<LiteratureLibraryEntry> entries,
  ) {
    final values = entries.where((entry) => !entry.isTrashed).toList();
    final parent = <String, String>{
      for (final entry in values) entry.id: entry.id,
    };
    final reasons = <String, Set<String>>{};
    final doiBuckets = <String, List<LiteratureLibraryEntry>>{};
    final identityBuckets = <String, List<LiteratureLibraryEntry>>{};
    for (final entry in values) {
      final doi = _doi(entry.record.doi);
      if (doi != null) doiBuckets.putIfAbsent(doi, () => []).add(entry);
      final identity = _identity(entry.record);
      if (identity != null) {
        identityBuckets.putIfAbsent(identity, () => []).add(entry);
      }
    }
    void joinBucket(List<LiteratureLibraryEntry> bucket, String reason) {
      if (bucket.length < 2) return;
      final first = bucket.first.id;
      for (final entry in bucket.skip(1)) {
        _union(parent, first, entry.id);
      }
      for (final entry in bucket) {
        reasons.putIfAbsent(entry.id, () => <String>{}).add(reason);
      }
    }

    for (final bucket in doiBuckets.values) {
      joinBucket(bucket, 'Same DOI');
    }
    for (final bucket in identityBuckets.values) {
      joinBucket(bucket, 'Same normalized title, year, and first author');
    }

    final grouped = <String, List<LiteratureLibraryEntry>>{};
    for (final entry in values) {
      grouped.putIfAbsent(_find(parent, entry.id), () => []).add(entry);
    }
    final result = <LiteratureDuplicateGroup>[];
    for (final group in grouped.values.where((group) => group.length > 1)) {
      final groupReasons = <String>{
        for (final entry in group) ...?reasons[entry.id],
      }.toList(growable: false)..sort();
      result.add(
        LiteratureDuplicateGroup(
          entries: List<LiteratureLibraryEntry>.unmodifiable(group),
          reasons: List<String>.unmodifiable(groupReasons),
        ),
      );
    }
    result.sort(
      (left, right) => left.entries.first.record.title.compareTo(
        right.entries.first.record.title,
      ),
    );
    return List<LiteratureDuplicateGroup>.unmodifiable(result);
  }

  LiteratureLibraryEntry merge(
    LiteratureDuplicateGroup group, {
    required String preferredId,
  }) {
    if (group.entries.length < 2) {
      throw ArgumentError('A duplicate group must contain at least two items.');
    }
    final preferred = group.entries
        .where((entry) => entry.id == preferredId)
        .firstOrNull;
    if (preferred == null) {
      throw ArgumentError.value(preferredId, 'preferredId', 'Not in group.');
    }
    final others = group.entries.where((entry) => entry.id != preferredId);
    final all = <LiteratureLibraryEntry>[preferred, ...others];
    final records = all.map((entry) => entry.record).toList(growable: false);
    final bestProgress = all.reduce(
      (left, right) =>
          left.record.readingProgress >= right.record.readingProgress
          ? left
          : right,
    );
    final mergedRecord = LiteratureRecord(
      id: preferred.record.id,
      localFileId: preferred.record.localFileId,
      doi: _firstNonEmpty(records.map((record) => record.doi)),
      title: _longest(records.map((record) => record.title)),
      authors: _bestList(records.map((record) => record.authors)),
      journal: _longest(records.map((record) => record.journal)),
      year: records.map((record) => record.year).whereType<int>().firstOrNull,
      volume: _longest(records.map((record) => record.volume)),
      issue: _longest(records.map((record) => record.issue)),
      pages: _longest(records.map((record) => record.pages)),
      abstractText: _longest(records.map((record) => record.abstractText)),
      keywords: List<String>.unmodifiable({
        for (final record in records) ...record.keywords,
      }),
      tags: List<String>.unmodifiable({
        for (final record in records) ...record.tags,
      }),
      readingProgress: bestProgress.record.readingProgress,
      lastOpenedAt: records
          .map((record) => record.lastOpenedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (latest, value) =>
                latest == null || value.isAfter(latest) ? value : latest,
          ),
      metadataSource: preferred.record.metadataSource,
      metadataConfidence: records
          .map((record) => record.metadataConfidence)
          .reduce((left, right) => left > right ? left : right),
    );
    final primary =
        preferred.localPath ??
        all.map((entry) => entry.localPath).whereType<String>().firstOrNull;
    final attachments =
        <String>{for (final entry in all) ...entry.allAttachmentPaths}
          ..removeWhere(
            (path) =>
                primary != null && path.toLowerCase() == primary.toLowerCase(),
          );
    return LiteratureLibraryEntry(
      record: mergedRecord,
      localPath: primary,
      fileName: primary == null
          ? preferred.fileName
          : all
                    .where((entry) => entry.localPath == primary)
                    .map((entry) => entry.fileName)
                    .firstOrNull ??
                preferred.fileName,
      addedAt: all
          .map((entry) => entry.addedAt)
          .reduce((left, right) => left.isBefore(right) ? left : right),
      currentPage: bestProgress.currentPage,
      totalPages: bestProgress.totalPages,
      collectionIds: List<String>.unmodifiable({
        for (final entry in all) ...entry.collectionIds,
      }),
      rating: all
          .map((entry) => entry.rating)
          .reduce((left, right) => left > right ? left : right),
      isStarred: all.any((entry) => entry.isStarred),
      supplementalPaths: List<String>.unmodifiable(attachments),
    );
  }

  static String? _doi(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized?.isNotEmpty == true ? normalized : null;
  }

  static String? _identity(LiteratureRecord record) {
    final title = _normalize(record.title);
    if (title.length < 8) return null;
    final author = record.authors.isEmpty
        ? ''
        : _normalize(record.authors.first);
    return '$title|${record.year ?? ''}|$author';
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _find(Map<String, String> parent, String id) {
    final current = parent[id]!;
    if (current == id) return id;
    final root = _find(parent, current);
    parent[id] = root;
    return root;
  }

  static void _union(Map<String, String> parent, String left, String right) {
    final leftRoot = _find(parent, left);
    final rightRoot = _find(parent, right);
    if (leftRoot != rightRoot) parent[rightRoot] = leftRoot;
  }

  static String? _firstNonEmpty(Iterable<String?> values) => values
      .map((value) => value?.trim())
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .firstOrNull;

  static String _longest(Iterable<String> values) => values.fold<String>(
    '',
    (best, value) => value.trim().length > best.length ? value.trim() : best,
  );

  static List<String> _bestList(Iterable<List<String>> values) =>
      List<String>.unmodifiable(
        values.fold<List<String>>(
          const <String>[],
          (best, value) => value.length > best.length ? value : best,
        ),
      );
}
