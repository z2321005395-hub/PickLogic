import 'package:picklogic_core_models/picklogic_core_models.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'extracts normalized DOI candidates and removes sentence punctuation',
    () {
      final candidates = const DoiExtractor().candidates(
        'See https://doi.org/10.1000/ABC.123, and 10.1000/abc.123.',
      );
      expect(candidates, ['10.1000/abc.123']);
    },
  );

  test('creates a preview name without invalid Windows characters', () {
    const record = LiteratureRecord(
      id: 'lit-1',
      localFileId: 'file-1',
      title: 'A title: with / invalid * characters',
      authors: ['Researcher'],
      year: 2026,
    );
    final preview = const LiteratureNaming().previewFileName(record);
    expect(preview, endsWith('.pdf'));
    expect(preview, isNot(contains(':')));
    expect(preview, isNot(contains('/')));
  });
}
