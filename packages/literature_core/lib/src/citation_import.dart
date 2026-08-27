import 'package:petit_bibtex/bibtex.dart';
import 'package:picklogic_core_models/picklogic_core_models.dart';

import 'library_catalog.dart';

enum CitationImportFormat { bibtex, ris }

final class CitationImportResult {
  const CitationImportResult({
    required this.entries,
    this.warnings = const <String>[],
  });

  final List<LiteratureLibraryEntry> entries;
  final List<String> warnings;
}

/// Imports portable citation text into local reference-only library entries.
/// No network lookup occurs and no source document is uploaded.
final class LiteratureCitationImporter {
  const LiteratureCitationImporter();

  CitationImportResult parse(
    String source, {
    required CitationImportFormat format,
    required DateTime importedAt,
    String sourceFileName = 'Imported references',
  }) => switch (format) {
    CitationImportFormat.bibtex => _parseBibTeX(
      source,
      importedAt: importedAt,
      sourceFileName: sourceFileName,
    ),
    CitationImportFormat.ris => _parseRis(
      source,
      importedAt: importedAt,
      sourceFileName: sourceFileName,
    ),
  };

  CitationImportResult _parseBibTeX(
    String source, {
    required DateTime importedAt,
    required String sourceFileName,
  }) {
    late final List<BibTeXEntry> parsedEntries;
    try {
      parsedEntries = BibTeXDefinition().build().parse(source).value;
    } on Object catch (error) {
      throw FormatException('Invalid BibTeX: $error');
    }
    final entries = <LiteratureLibraryEntry>[];
    final warnings = <String>[];
    final ids = <String>{};
    for (final item in parsedEntries) {
      final fields = <String, String>{
        for (final field in item.fields.entries)
          field.key.toLowerCase(): _cleanBibValue(field.value),
      };
      final title = fields['title']?.trim() ?? '';
      if (title.isEmpty) {
        warnings.add('Skipped BibTeX entry ${item.key}: title is missing.');
        continue;
      }
      final authors = _splitBibPeople(fields['author'] ?? '');
      final doi = _normalizeDoi(fields['doi']);
      final year = _firstYear(fields['year'] ?? fields['date']);
      final id = LiteratureLibraryEntry.stableIdForReference(
        doi: doi,
        title: title,
        authors: authors,
        year: year,
      );
      if (!ids.add(id)) {
        warnings.add('Skipped duplicate BibTeX entry ${item.key}.');
        continue;
      }
      final record = LiteratureRecord(
        id: id,
        localFileId: 'reference-$id',
        doi: doi,
        title: title,
        authors: authors,
        journal: fields['journal'] ?? fields['booktitle'] ?? '',
        year: year,
        volume: fields['volume'] ?? '',
        issue: fields['number'] ?? fields['issue'] ?? '',
        pages: fields['pages'] ?? '',
        abstractText: fields['abstract'] ?? '',
        keywords: _splitKeywords(fields['keywords'] ?? fields['keyword'] ?? ''),
        metadataSource: 'BibTeX import',
        metadataConfidence: 1,
      );
      entries.add(
        LiteratureLibraryEntry.fromImportedRecord(
          record: record,
          addedAt: importedAt,
          sourceFileName: sourceFileName,
        ),
      );
    }
    return CitationImportResult(
      entries: List<LiteratureLibraryEntry>.unmodifiable(entries),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  CitationImportResult _parseRis(
    String source, {
    required DateTime importedAt,
    required String sourceFileName,
  }) {
    final rawRecords = <Map<String, List<String>>>[];
    Map<String, List<String>>? current;
    String? lastTag;
    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trimRight();
      final match = RegExp(r'^([A-Z0-9]{2})\s{0,2}-\s?(.*)$').firstMatch(line);
      if (match != null) {
        final tag = match.group(1)!;
        final value = match.group(2)!.trim();
        if (tag == 'TY') {
          if (current != null && current.isNotEmpty) rawRecords.add(current);
          current = <String, List<String>>{};
        }
        current ??= <String, List<String>>{};
        current.putIfAbsent(tag, () => <String>[]).add(value);
        lastTag = tag;
        if (tag == 'ER') {
          rawRecords.add(current);
          current = null;
          lastTag = null;
        }
      } else if (current != null && lastTag != null && line.trim().isNotEmpty) {
        final values = current[lastTag]!;
        values[values.length - 1] = '${values.last} ${line.trim()}';
      }
    }
    if (current != null && current.isNotEmpty) rawRecords.add(current);
    if (rawRecords.isEmpty && source.trim().isNotEmpty) {
      throw const FormatException('No RIS records were found.');
    }

    final entries = <LiteratureLibraryEntry>[];
    final warnings = <String>[];
    final ids = <String>{};
    for (var index = 0; index < rawRecords.length; index++) {
      final fields = rawRecords[index];
      final title = _first(fields, const ['TI', 'T1', 'CT']);
      if (title.isEmpty) {
        warnings.add('Skipped RIS record ${index + 1}: title is missing.');
        continue;
      }
      final authors = <String>[...?fields['AU'], ...?fields['A1']]
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      final doi = _normalizeDoi(_first(fields, const ['DO']));
      final year = _firstYear(_first(fields, const ['PY', 'Y1', 'DA']));
      final id = LiteratureLibraryEntry.stableIdForReference(
        doi: doi,
        title: title,
        authors: authors,
        year: year,
      );
      if (!ids.add(id)) {
        warnings.add('Skipped duplicate RIS record ${index + 1}.');
        continue;
      }
      final startPage = _first(fields, const ['SP']);
      final endPage = _first(fields, const ['EP']);
      final pages = startPage.isEmpty
          ? ''
          : endPage.isEmpty || startPage == endPage
          ? startPage
          : '$startPage-$endPage';
      final record = LiteratureRecord(
        id: id,
        localFileId: 'reference-$id',
        doi: doi,
        title: title,
        authors: List<String>.unmodifiable(authors),
        journal: _first(fields, const ['JO', 'JF', 'T2', 'JA']),
        year: year,
        volume: _first(fields, const ['VL']),
        issue: _first(fields, const ['IS']),
        pages: pages,
        abstractText: _first(fields, const ['AB', 'N2']),
        keywords: List<String>.unmodifiable({...?fields['KW']}),
        metadataSource: 'RIS import',
        metadataConfidence: 1,
      );
      entries.add(
        LiteratureLibraryEntry.fromImportedRecord(
          record: record,
          addedAt: importedAt,
          sourceFileName: sourceFileName,
        ),
      );
    }
    return CitationImportResult(
      entries: List<LiteratureLibraryEntry>.unmodifiable(entries),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static String _cleanBibValue(String value) {
    var result = value.trim();
    while (result.length >= 2 &&
        ((result.startsWith('{') && result.endsWith('}')) ||
            (result.startsWith('"') && result.endsWith('"')))) {
      result = result.substring(1, result.length - 1).trim();
    }
    return result
        .replaceAll(r'\&', '&')
        .replaceAll(r'\_', '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _splitBibPeople(String value) =>
      List<String>.unmodifiable(
        value
            .split(RegExp(r'\s+and\s+', caseSensitive: false))
            .map(_cleanBibValue)
            .where((author) => author.isNotEmpty),
      );

  static List<String> _splitKeywords(String value) => List<String>.unmodifiable(
    value
        .split(RegExp(r'[;,]'))
        .map(_cleanBibValue)
        .where((keyword) => keyword.isNotEmpty)
        .toSet(),
  );

  static String _first(Map<String, List<String>> fields, List<String> names) {
    for (final name in names) {
      final value = fields[name]?.firstOrNull?.trim();
      if (value?.isNotEmpty == true) return value!;
    }
    return '';
  }

  static int? _firstYear(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'(?<!\d)(1[5-9]\d{2}|20\d{2}|21\d{2})(?!\d)',
    ).firstMatch(value);
    return match == null ? null : int.parse(match.group(1)!);
  }

  static String? _normalizeDoi(String? value) {
    final normalized = value
        ?.trim()
        .replaceFirst(
          RegExp(r'^https?://(?:dx\.)?doi\.org/', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'^doi:\s*', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    return normalized?.isNotEmpty == true ? normalized : null;
  }
}
