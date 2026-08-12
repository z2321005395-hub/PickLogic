import 'locator.dart';
import 'operations.dart';
import 'records.dart';

final class ScanRequest {
  const ScanRequest({
    required this.root,
    this.resumeCursor,
    this.batchSize = 200,
  }) : assert(batchSize > 0);

  final FileLocator root;
  final String? resumeCursor;
  final int batchSize;
}

final class ScanBatch {
  const ScanBatch({
    required this.records,
    required this.cursor,
    required this.isComplete,
    required this.scannedCount,
  });

  final List<FileRecord> records;
  final String? cursor;
  final bool isComplete;
  final int scannedCount;
}

abstract interface class FileScanner {
  Stream<ScanBatch> scan(ScanRequest request);
  Future<void> cancel();
}

abstract interface class FileOperator {
  Future<OperationPlan> preview(OperationPlan plan);
  Future<OperationResult> execute(OperationPlan confirmedPlan);
  Future<OperationResult> undo(OperationPlan completedPlan);
}

abstract interface class PreviewProvider {
  Future<Object?> loadPreview(FileRecord record, {int maxBytes = 8388608});
  Future<void> evict(String fileId);
}

abstract interface class SearchIndexer {
  Future<void> upsertBatch(List<FileRecord> records);
  Future<void> removeByIds(Iterable<String> ids);
  Future<List<FileRecord>> search(String query, {int limit = 100});
}

abstract interface class DuplicateDetector {
  Future<String> hashBytes(Stream<List<int>> bytes);
  List<List<FileRecord>> groupExact(Iterable<FileRecord> records);
}

abstract interface class ClassificationEngine {
  FileRecord classify(FileRecord record);
}

abstract interface class InsightEngine {
  InsightRecord explainFile(FileRecord record);
}

abstract interface class StorageAnalyzer {
  Stream<StorageBreakdown> analyze();
  Future<void> cancel();
}

abstract interface class LiteratureMetadataProvider {
  Future<LiteratureRecord?> lookupByDoi(String doi, String localFileId);
}

abstract interface class TranslationProvider {
  Future<String> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
  });
}

abstract interface class OcrProvider {
  Future<String> recognize(FileLocator locator);
}

abstract interface class IntelligenceProvider {
  Future<InsightRecord?> enrich(InsightRecord localInsight);
}
