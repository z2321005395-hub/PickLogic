import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_search_index/picklogic_search_index.dart';
import 'package:test/test.dart';

void main() {
  FileRecord fixture(
    String id,
    String name,
    VirtualCategory category, {
    List<String> tags = const <String>[],
  }) => FileRecord(
    id: id,
    locator: FileLocator(
      value: 'synthetic://$id',
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
    ),
    displayName: name,
    extension: name.split('.').last,
    mimeType: '',
    sizeBytes: 1,
    createdAt: null,
    modifiedAt: DateTime.utc(2026, 1, int.parse(id)),
    parentLocator: null,
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
    isHidden: false,
    isSystem: false,
    isAccessible: true,
    isProtected: false,
    category: category,
    tags: tags,
    hashState: HashState.notRequested,
    ocrState: OcrState.notRequested,
  );

  test('upserts, searches, ranks, and removes records', () async {
    final index = InMemorySearchIndex();
    await index.upsertBatch([
      fixture('1', 'notes.pdf', VirtualCategory.pdf),
      fixture('2', 'experiment_notes.txt', VirtualCategory.documents),
    ]);
    final results = await index.search('notes pdf');
    expect(results.map((item) => item.id), ['1']);
    await index.removeByIds(['1']);
    expect(await index.search('notes pdf'), isEmpty);
  });

  test('requires every term and uses deterministic metadata ranking', () async {
    final index = InMemorySearchIndex();
    await index.upsertBatch([
      fixture('1', 'alpha-notes.pdf', VirtualCategory.pdf),
      fixture(
        '2',
        'alpha.txt',
        VirtualCategory.documents,
        tags: const ['notes'],
      ),
      fixture('3', 'unrelated.pdf', VirtualCategory.pdf),
    ]);

    expect((await index.search('notes pdf')).map((record) => record.id), ['1']);
    expect((await index.search('notes alpha')).map((record) => record.id), [
      '1',
      '2',
    ]);
  });
}
