import 'package:picklogic_android_bridge/picklogic_android_bridge.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

import 'paged_media.dart';

final class MobileScreenshotCandidate {
  const MobileScreenshotCandidate({
    required this.record,
    required this.metadata,
  });

  final FileRecord record;
  final AndroidMediaEntry metadata;

  DateTime get capturedAt => metadata.createdAt.millisecondsSinceEpoch > 0
      ? metadata.createdAt
      : metadata.modifiedAt;
}

final class MobileScreenshotGroup {
  const MobileScreenshotGroup({required this.summary, required this.records});

  final ScreenshotGroup summary;
  final List<FileRecord> records;
}

List<MobileScreenshotGroup> buildScreenshotGroups(
  Iterable<MobileScreenshotCandidate> candidates, {
  Duration continuousGap = const Duration(minutes: 3),
}) {
  if (continuousGap.isNegative) {
    throw ArgumentError.value(continuousGap, 'continuousGap');
  }
  final sorted = candidates.toList(growable: false)
    ..sort((left, right) {
      final byDate = right.capturedAt.compareTo(left.capturedAt);
      if (byDate != 0) return byDate;
      return compareMediaIdsDescending(left.metadata.id, right.metadata.id);
    });
  if (sorted.isEmpty) return const <MobileScreenshotGroup>[];

  final result = <MobileScreenshotGroup>[];
  var current = <MobileScreenshotCandidate>[sorted.first];
  var currentSource = screenshotSourceHint(sorted.first.metadata);

  void finishGroup() {
    final newest = current.first.capturedAt;
    final oldest = current.last.capturedAt;
    final memberIds = current
        .map((candidate) => candidate.record.id)
        .toList(growable: false);
    result.add(
      MobileScreenshotGroup(
        summary: ScreenshotGroup(
          groupId: 'timeline:${memberIds.first}:${memberIds.last}',
          sourceHint: currentSource,
          startedAt: oldest,
          endedAt: newest,
          memberIds: memberIds,
          duplicateConfidence: 0,
          contentHint: 'mediastore_time_and_source_clues',
          ocrState: OcrState.notRequested,
          reviewState: ScreenshotReviewState.unreviewed,
          protectedCount: 0,
        ),
        records: current
            .map((candidate) => candidate.record)
            .toList(growable: false),
      ),
    );
  }

  for (final candidate in sorted.skip(1)) {
    final previous = current.last;
    final source = screenshotSourceHint(candidate.metadata);
    final gap = previous.capturedAt.difference(candidate.capturedAt);
    final sameDay = _sameLocalDay(previous.capturedAt, candidate.capturedAt);
    if (sameDay && source == currentSource && gap <= continuousGap) {
      current.add(candidate);
      continue;
    }
    finishGroup();
    current = <MobileScreenshotCandidate>[candidate];
    currentSource = source;
  }
  finishGroup();
  return result;
}

String screenshotSourceHint(AndroidMediaEntry entry) {
  final nativeHint = entry.sourceHint?.trim();
  if (nativeHint != null && nativeHint.isNotEmpty) return nativeHint;
  final path = entry.relativePath?.replaceAll('\\', '/');
  final segments = path
      ?.split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
  if (segments != null && segments.isNotEmpty) {
    return 'folder:${segments.last}';
  }
  return 'unknown';
}

bool _sameLocalDay(DateTime left, DateTime right) {
  final leftLocal = left.toLocal();
  final rightLocal = right.toLocal();
  return leftLocal.year == rightLocal.year &&
      leftLocal.month == rightLocal.month &&
      leftLocal.day == rightLocal.day;
}
