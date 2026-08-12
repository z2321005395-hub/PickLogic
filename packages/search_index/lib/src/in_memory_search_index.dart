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
      final score = terms.isEmpty ? 1 : _score(record, terms);
      if (score != null) scored.add((record: record, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byModified = b.record.modifiedAt.compareTo(a.record.modifiedAt);
      if (byModified != 0) return byModified;
      return a.record.id.compareTo(b.record.id);
    });
    return scored.take(limit).map((entry) => entry.record).toList();
  }

  int? _score(FileRecord record, Set<String> terms) {
    final name = record.displayName.toLowerCase();
    final nameTerms = _terms(name);
    final extension = record.extension.toLowerCase();
    final mimeType = record.mimeType.toLowerCase();
    final category = record.category.name.toLowerCase();
    final tags = record.tags.map((tag) => tag.toLowerCase()).toSet();
    var score = 0;
    for (final term in terms) {
      if (name == term) {
        score += 100;
      } else if (nameTerms.contains(term)) {
        score += 60;
      } else if (name.startsWith(term)) {
        score += 50;
      } else if (name.contains(term)) {
        score += 40;
      } else if (extension == term || category == term || tags.contains(term)) {
        score += 25;
      } else if (extension.contains(term) ||
          mimeType.contains(term) ||
          category.contains(term) ||
          tags.any((tag) => tag.contains(term))) {
        score += 10;
      } else {
        return null;
      }
    }
    return score;
  }

  Set<String> _terms(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true))
      .where((term) => term.isNotEmpty)
      .toSet();
}
