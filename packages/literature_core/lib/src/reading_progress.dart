import 'package:picklogic_core_models/picklogic_core_models.dart';

/// Produces immutable reading-progress updates for a literature record.
///
/// Persistence is intentionally left to the caller; this class performs no
/// file mutation and does not require a PDF renderer.
final class LiteratureReadingTracker {
  const LiteratureReadingTracker();

  LiteratureRecord recordFraction(
    LiteratureRecord record, {
    required double progress,
    required DateTime openedAt,
  }) {
    if (!progress.isFinite || progress < 0 || progress > 1) {
      throw RangeError.range(progress, 0, 1, 'progress');
    }
    return _copyWithProgress(record, progress: progress, openedAt: openedAt);
  }

  LiteratureRecord recordPage(
    LiteratureRecord record, {
    required int currentPage,
    required int totalPages,
    required DateTime openedAt,
  }) {
    if (totalPages <= 0) {
      throw RangeError.value(totalPages, 'totalPages', 'Must be positive.');
    }
    if (currentPage < 0 || currentPage > totalPages) {
      throw RangeError.range(currentPage, 0, totalPages, 'currentPage');
    }
    return recordFraction(
      record,
      progress: currentPage / totalPages,
      openedAt: openedAt,
    );
  }

  LiteratureRecord markOpened(
    LiteratureRecord record, {
    required DateTime openedAt,
  }) => _copyWithProgress(
    record,
    progress: record.readingProgress,
    openedAt: openedAt,
  );

  LiteratureRecord _copyWithProgress(
    LiteratureRecord record, {
    required double progress,
    required DateTime openedAt,
  }) => LiteratureRecord(
    id: record.id,
    localFileId: record.localFileId,
    doi: record.doi,
    title: record.title,
    authors: List<String>.unmodifiable(record.authors),
    journal: record.journal,
    year: record.year,
    volume: record.volume,
    issue: record.issue,
    pages: record.pages,
    abstractText: record.abstractText,
    keywords: List<String>.unmodifiable(record.keywords),
    tags: List<String>.unmodifiable(record.tags),
    readingProgress: progress,
    lastOpenedAt: openedAt,
    metadataSource: record.metadataSource,
    metadataConfidence: record.metadataConfidence,
  );
}
