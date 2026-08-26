import 'package:picklogic_core_models/picklogic_core_models.dart';

enum CitationExportFormat { bibtex, ris, plainText }

enum QuickCitationStyle { authorDate, numbered }

/// Lightweight, dependency-free citation export for the local literature
/// library. It deliberately does not claim full CSL conformance.
final class LiteratureCitationFormatter {
  const LiteratureCitationFormatter();

  String format(
    LiteratureRecord record, {
    required CitationExportFormat format,
    QuickCitationStyle style = QuickCitationStyle.authorDate,
    int number = 1,
  }) => switch (format) {
    CitationExportFormat.bibtex => toBibTeX(record),
    CitationExportFormat.ris => toRis(record),
    CitationExportFormat.plainText => toPlainText(
      record,
      style: style,
      number: number,
    ),
  };

  String toBibTeX(LiteratureRecord record) {
    final fields = <(String, String)>[
      ('title', record.title),
      if (record.authors.isNotEmpty) ('author', record.authors.join(' and ')),
      if (record.journal.trim().isNotEmpty) ('journal', record.journal),
      if (record.year != null) ('year', '${record.year}'),
      if (record.volume.trim().isNotEmpty) ('volume', record.volume),
      if (record.issue.trim().isNotEmpty) ('number', record.issue),
      if (record.pages.trim().isNotEmpty) ('pages', record.pages),
      if (record.doi?.trim().isNotEmpty == true) ('doi', record.doi!.trim()),
      if (record.keywords.isNotEmpty) ('keywords', record.keywords.join(', ')),
      if (record.abstractText.trim().isNotEmpty)
        ('abstract', record.abstractText),
    ];
    final body = fields
        .map((field) => '  ${field.$1} = {${_escapeBibTeX(field.$2)}},')
        .join('\n');
    return '@article{${citeKey(record)},\n$body\n}';
  }

  String toRis(LiteratureRecord record) {
    final lines = <String>[
      'TY  - JOUR',
      'TI  - ${_singleLine(record.title)}',
      for (final author in record.authors) 'AU  - ${_singleLine(author)}',
      if (record.journal.trim().isNotEmpty)
        'JO  - ${_singleLine(record.journal)}',
      if (record.year != null) 'PY  - ${record.year}',
      if (record.volume.trim().isNotEmpty)
        'VL  - ${_singleLine(record.volume)}',
      if (record.issue.trim().isNotEmpty) 'IS  - ${_singleLine(record.issue)}',
      if (record.pages.trim().isNotEmpty) ..._risPages(record.pages),
      if (record.doi?.trim().isNotEmpty == true)
        'DO  - ${_singleLine(record.doi!)}',
      for (final keyword in record.keywords) 'KW  - ${_singleLine(keyword)}',
      if (record.abstractText.trim().isNotEmpty)
        'AB  - ${_singleLine(record.abstractText)}',
      'ER  -',
    ];
    return '${lines.join('\n')}\n';
  }

  String toPlainText(
    LiteratureRecord record, {
    QuickCitationStyle style = QuickCitationStyle.authorDate,
    int number = 1,
  }) {
    final authorText = _displayAuthors(record.authors);
    final yearText = record.year?.toString() ?? 'n.d.';
    final source = <String>[
      if (record.journal.trim().isNotEmpty) record.journal.trim(),
      if (record.volume.trim().isNotEmpty) record.volume.trim(),
      if (record.issue.trim().isNotEmpty) '(${record.issue.trim()})',
      if (record.pages.trim().isNotEmpty) record.pages.trim(),
    ].join(' ');
    final doi = record.doi?.trim();
    final citation = <String>[
      if (authorText.isNotEmpty) authorText,
      '($yearText).',
      '${record.title.trim()}.',
      if (source.isNotEmpty) '$source.',
      if (doi?.isNotEmpty == true) 'https://doi.org/$doi',
    ].join(' ');
    return style == QuickCitationStyle.numbered
        ? '[${number < 1 ? 1 : number}] $citation'
        : citation;
  }

  String inText(LiteratureRecord record) {
    final year = record.year?.toString() ?? 'n.d.';
    if (record.authors.isEmpty) return '(${record.title}, $year)';
    final first = _familyName(record.authors.first);
    return record.authors.length == 1
        ? '($first, $year)'
        : record.authors.length == 2
        ? '($first & ${_familyName(record.authors[1])}, $year)'
        : '($first et al., $year)';
  }

  String citeKey(LiteratureRecord record) {
    final author = record.authors.isEmpty
        ? 'untitled'
        : _familyName(record.authors.first);
    final year = record.year?.toString() ?? 'nd';
    final titleWord = RegExp(
      r'[\p{L}\p{N}]+',
      unicode: true,
    ).firstMatch(record.title)?.group(0);
    final raw = '$author$year${titleWord ?? 'work'}';
    final normalized = raw.replaceAll(
      RegExp(r'[^\p{L}\p{N}_-]', unicode: true),
      '',
    );
    return normalized.isEmpty ? 'picklogic$year' : normalized;
  }

  static String _escapeBibTeX(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('{', r'\{')
      .replaceAll('}', r'\}')
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .trim();

  static String _singleLine(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

  static List<String> _risPages(String pages) {
    final normalized = _singleLine(pages);
    final parts = normalized.split(RegExp(r'\s*[-–—]\s*'));
    return <String>[
      'SP  - ${parts.first}',
      if (parts.length > 1 && parts.last.isNotEmpty) 'EP  - ${parts.last}',
    ];
  }

  static String _displayAuthors(List<String> authors) {
    if (authors.isEmpty) return '';
    if (authors.length == 1) return authors.single;
    if (authors.length == 2) return '${authors.first} & ${authors.last}';
    return '${authors.first} et al.';
  }

  static String _familyName(String author) {
    final clean = author.trim();
    if (clean.contains(',')) return clean.split(',').first.trim();
    final parts = clean.split(RegExp(r'\s+'));
    return parts.isEmpty ? clean : parts.last;
  }
}
