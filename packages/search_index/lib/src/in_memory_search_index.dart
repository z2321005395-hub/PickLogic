import 'package:picklogic_core_models/picklogic_core_models.dart';

final class InMemorySearchIndex implements SearchIndexer {
  final Map<String, FileRecord> _records = {};

  @override
  Future<void> upsertBatch(List<FileRecord> records) async {
    for (final record in records) {
      _records[record.id] = record;
    }
  }

  @override
  Future<void> removeByIds(Iterable<String> ids) async {
    for (final id in ids) {
      _records.remove(id);
    }
  }

  @override
  Future<List<FileRecord>> search(String query, {int limit = 100}) async {
    if (limit <= 0) return const [];
    final terms = _terms(query);
    final scored = <({FileRecord record, int score})>[];
    for (final record in _records.values) {
      final haystack = _terms(
        '${record.displayName} ${record.extension} ${record.mimeType} '
        '${record.category.name} ${record.tags.join(' ')}',
      );
      final score = terms.isEmpty
          ? 1
          : terms.fold<int>(0, (sum, term) {
              if (record.displayName.toLowerCase() == term) {
                return sum + 10;
              }
              if (record.displayName.toLowerCase().contains(term)) {
                return sum + 5;
              }
              return haystack.contains(term) ? sum + 1 : -1000;
            });
      if (score >= 0) scored.add((record: record, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.record.modifiedAt.compareTo(a.record.modifiedAt);
    });
    return scored.take(limit).map((entry) => entry.record).toList();
  }

  Set<String> _terms(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true))
      .where((term) => term.isNotEmpty)
      .toSet();
}
