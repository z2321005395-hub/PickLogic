import 'dart:io';

import 'package:picklogic_test_fixtures/picklogic_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('writes a complete synthetic fixture tree', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'picklogic-fixtures-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final files = await const SyntheticFixtureSet().writeTo(temporary);
    expect(files.length, 14);
    final duplicateA = File('${temporary.path}/images/exact_duplicate_a.png');
    final duplicateB = File('${temporary.path}/images/exact_duplicate_b.png');
    expect(await duplicateA.readAsBytes(), await duplicateB.readAsBytes());
    final pdf = File('${temporary.path}/documents/synthetic_paper.pdf');
    expect(await pdf.readAsString(), startsWith('%PDF-1.4'));
  });

  test('records contain one exact duplicate group and a protected item', () {
    final records = const SyntheticFixtureSet().records();
    expect(records.where((record) => record.sha256 != null), hasLength(2));
    expect(records.where((record) => record.isProtected), hasLength(1));
  });
}
