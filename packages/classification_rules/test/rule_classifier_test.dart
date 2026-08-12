import 'package:picklogic_classification_rules/picklogic_classification_rules.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:test/test.dart';

void main() {
  FileRecord fixture(
    String name,
    String extension, {
    List<String> tags = const [],
  }) => FileRecord(
    id: name,
    locator: FileLocator(
      value: 'synthetic://$name',
      sourceKind: SourceKind.synthetic,
      platform: PickLogicPlatform.synthetic,
    ),
    displayName: name,
    extension: extension,
    mimeType: '',
    sizeBytes: 1,
    createdAt: null,
    modifiedAt: DateTime.utc(2026),
    parentLocator: null,
    sourceKind: SourceKind.synthetic,
    platform: PickLogicPlatform.synthetic,
    isHidden: false,
    isSystem: false,
    isAccessible: true,
    isProtected: false,
    category: VirtualCategory.unknown,
    tags: tags,
    hashState: HashState.notRequested,
    ocrState: OcrState.notRequested,
  );

  test('classifies common extensions and screenshots deterministically', () {
    final engine = RuleClassificationEngine();
    expect(
      engine.classify(fixture('notes.docx', 'docx')).category,
      VirtualCategory.documents,
    );
    expect(
      engine.classify(fixture('Screenshot_1.png', 'png')).category,
      VirtualCategory.screenshots,
    );
  });

  test('remembered user extension rule takes priority', () {
    final engine = RuleClassificationEngine()
      ..rememberExtension('.dat', VirtualCategory.code);
    expect(
      engine.classify(fixture('result.dat', 'dat')).category,
      VirtualCategory.code,
    );
  });
}
