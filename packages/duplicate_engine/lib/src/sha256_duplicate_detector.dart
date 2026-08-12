import 'package:crypto/crypto.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

final class Sha256DuplicateDetector implements DuplicateDetector {
  @override
  Future<String> hashBytes(Stream<List<int>> bytes) async =>
      (await sha256.bind(bytes).first).toString();

  @override
  List<List<FileRecord>> groupExact(Iterable<FileRecord> records) {
    final groups = <String, List<FileRecord>>{};
    for (final record in records) {
      final digest = record.sha256;
      if (record.hashState != HashState.complete || digest == null) continue;
      groups.putIfAbsent('${record.sizeBytes}:$digest', () => []).add(record);
    }
    final duplicates = groups.values
        .where((group) => group.length > 1)
        .toList();
    duplicates.sort((a, b) {
      final bytesA = a.first.sizeBytes * (a.length - 1);
      final bytesB = b.first.sizeBytes * (b.length - 1);
      return bytesB.compareTo(bytesA);
    });
    return duplicates.map(List<FileRecord>.unmodifiable).toList();
  }
}
