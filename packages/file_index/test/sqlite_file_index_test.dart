import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_file_index/picklogic_file_index.dart';
import 'package:test/test.dart';

void main() {
  FileRecord fixture(String id, String name) => FileRecord(
    id: id,
    locator: FileLocator(
      value: 'synthetic://$id',
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
    ),
    displayName: name,
    extension: name.split('.').last,
    mimeType: 'application/pdf',
    sizeBytes: 42,
    createdAt: DateTime.utc(2026, 1, 1),
    modifiedAt: DateTime.utc(2026, 1, int.parse(id)),
    parentLocator: null,
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
    isHidden: false,
    isSystem: false,
    isAccessible: true,
    isProtected: false,
    category: VirtualCategory.pdf,
    tags: const ['synthetic'],
    hashState: HashState.notRequested,
    ocrState: OcrState.notRequested,
  );

  test('persists batches, search state, updates, and removals', () async {
    final index = SqliteFileIndex.inMemory();
    addTearDown(index.close);
    await index.upsertBatch([
      fixture('1', 'alpha.pdf'),
      fixture('2', 'beta.pdf'),
    ]);
    expect(index.count, 2);
    expect((await index.search('alpha')).single.id, '1');

    await index.saveScanState(rootKey: 'root', cursor: '2', scannedCount: 2);
    expect(index.loadScanState('root')?.cursor, '2');
    expect(index.loadScanState('root')?.scannedCount, 2);

    await index.removeByIds(['1']);
    expect(index.count, 1);
  });
}
