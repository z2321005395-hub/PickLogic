import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

final class ExactDuplicateScanResult {
  ExactDuplicateScanResult({
    required Iterable<FileRecord> records,
    required Iterable<List<FileRecord>> groups,
    required this.hashedCount,
    required this.failedCount,
  }) : records = List<FileRecord>.unmodifiable(records),
       groups = List<List<FileRecord>>.unmodifiable(
         groups.map(List<FileRecord>.unmodifiable),
       );

  final List<FileRecord> records;
  final List<List<FileRecord>> groups;
  final int hashedCount;
  final int failedCount;
}

final class Sha256DuplicateDetector implements DuplicateDetector {
  @override
  Future<String> hashBytes(Stream<List<int>> bytes) async =>
      (await sha256.bind(bytes).first).toString();

  Future<ExactDuplicateScanResult> findExactFiles(
    Iterable<FileRecord> records,
  ) async {
    final sourceRecords = records.toList(growable: false);
    final sizeCounts = <int, int>{};
    for (final record in sourceRecords) {
      sizeCounts.update(
        record.sizeBytes,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    var hashedCount = 0;
    var failedCount = 0;
    final hashedRecords = <FileRecord>[];
    for (final record in sourceRecords) {
      if (sizeCounts[record.sizeBytes] == 1) {
        hashedRecords.add(record);
        continue;
      }
      final existingDigest = _normalizedDigest(record.sha256);
      if (record.hashState == HashState.complete && existingDigest != null) {
        hashedRecords.add(record.copyWith(sha256: existingDigest));
        continue;
      }
      if (!_canHash(record)) {
        hashedRecords.add(record);
        continue;
      }
      try {
        final digest = await hashBytes(File(record.locator.value).openRead());
        hashedRecords.add(
          record.copyWith(hashState: HashState.complete, sha256: digest),
        );
        hashedCount += 1;
      } on FileSystemException {
        hashedRecords.add(record.copyWith(hashState: HashState.failed));
        failedCount += 1;
      }
    }
    return ExactDuplicateScanResult(
      records: hashedRecords,
      groups: groupExact(hashedRecords),
      hashedCount: hashedCount,
      failedCount: failedCount,
    );
  }

  @override
  List<List<FileRecord>> groupExact(Iterable<FileRecord> records) {
    final groups = <String, List<FileRecord>>{};
    for (final record in records) {
      final digest = _normalizedDigest(record.sha256);
      if (record.hashState != HashState.complete || digest == null) continue;
      groups.putIfAbsent('${record.sizeBytes}:$digest', () => []).add(record);
    }
    final duplicates = groups.values
        .where((group) => group.length > 1)
        .toList();
    for (final group in duplicates) {
      group.sort((left, right) => left.id.compareTo(right.id));
    }
    duplicates.sort((a, b) {
      final bytesA = a.first.sizeBytes * (a.length - 1);
      final bytesB = b.first.sizeBytes * (b.length - 1);
      final byReclaimableBytes = bytesB.compareTo(bytesA);
      if (byReclaimableBytes != 0) return byReclaimableBytes;
      return a.first.id.compareTo(b.first.id);
    });
    return duplicates.map(List<FileRecord>.unmodifiable).toList();
  }
}

bool _canHash(FileRecord record) =>
    record.isAccessible &&
    (record.sourceKind == SourceKind.fileSystem ||
        record.sourceKind == SourceKind.synthetic) &&
    (record.platform == PickLogicPlatform.windows ||
        record.platform == PickLogicPlatform.synthetic);

String? _normalizedDigest(String? digest) {
  if (digest == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest)) {
    return null;
  }
  return digest.toLowerCase();
}
