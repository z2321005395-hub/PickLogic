import 'package:picklogic_core_models/picklogic_core_models.dart';

enum LiteratureCitationStyle {
  apa7,
  mla9,
  chicagoAuthorDate,
  vancouver,
  ieee,
  gbT7714,
}

final class FormattedBibliography {
  const FormattedBibliography({
    required this.style,
    required this.entries,
    required this.plainText,
    required this.rtf,
  });

  final LiteratureCitationStyle style;
  final List<String> entries;
  final String plainText;
  final String rtf;
}

/// A deterministic local formatter for the six bundled styles.
///
/// This is not a general CSL interpreter. It produces usable bibliography and
/// citation output without introducing a JavaScript runtime or copyleft code.
final class LiteratureBibliographyFormatter {
  const LiteratureBibliographyFormatter();

  FormattedBibliography bibliography(
    Iterable<LiteratureRecord> records, {
    required LiteratureCitationStyle style,
  }) {
    final values = records.toList(growable: false);
    if (!_numeric(style)) {
      values.sort((left, right) {
        final author = _family(
          left.authors.firstOrNull ?? '',
        ).compareTo(_family(right.authors.firstOrNull ?? ''));
        if (author != 0) return author;
        final year = (left.year ?? 0).compareTo(right.year ?? 0);
        return year != 0
            ? year
            : left.title.toLowerCase().compareTo(right.title.toLowerCase());
      });
    }
    final entries = <String>[
      for (var index = 0; index < values.length; index++)
        formatReference(values[index], style: style, number: index + 1),
    ];
    final plain = entries.join('\n\n');
    return FormattedBibliography(
      style: style,
      entries: List<String>.unmodifiable(entries),
      plainText: plain,
      rtf: _rtf(entries),
    );
  }

  String formatCitation(
    Iterable<LiteratureRecord> records, {
    required LiteratureCitationStyle style,
    int firstNumber = 1,
  }) {
    final values = records.toList(growable: false);
    if (values.isEmpty) return '';
    if (_numeric(style)) {
      final numbers = List<int>.generate(
        values.length,
        (index) => firstNumber + index,
      );
      return style == LiteratureCitationStyle.ieee
          ? numbers.map((number) => '[$number]').join(', ')
          : '[${numbers.join(',')}]';
    }
    return '(${values.map(_authorYear).join('; ')})';
  }

  String formatReference(
    LiteratureRecord record, {
    required LiteratureCitationStyle style,
    int number = 1,
  }) => switch (style) {
    LiteratureCitationStyle.apa7 => _apa(record),
    LiteratureCitationStyle.mla9 => _mla(record),
    LiteratureCitationStyle.chicagoAuthorDate => _chicago(record),
    LiteratureCitationStyle.vancouver => '$number. ${_vancouver(record)}',
    LiteratureCitationStyle.ieee => '[$number] ${_ieee(record)}',
    LiteratureCitationStyle.gbT7714 => '[$number] ${_gb(record)}',
  };

  static String _apa(LiteratureRecord record) {
    final authors = _apaAuthors(record.authors);
    final year = record.year?.toString() ?? 'n.d.';
    final journal = _journalBlock(record);
    return _sentence([
      if (authors.isNotEmpty) authors,
      '($year)',
      _terminal(record.title),
      if (journal.isNotEmpty) journal,
      _doiUrl(record.doi),
    ]);
  }

  static String _mla(LiteratureRecord record) {
    final authors = _displayAuthors(record.authors);
    final issue = [
      if (record.volume.isNotEmpty) 'vol. ${record.volume}',
      if (record.issue.isNotEmpty) 'no. ${record.issue}',
      if (record.year != null) '${record.year}',
      if (record.pages.isNotEmpty) 'pp. ${record.pages}',
    ].join(', ');
    return _sentence([
      if (authors.isNotEmpty) _terminal(authors),
      '“${_stripTerminal(record.title)}.”',
      if (record.journal.isNotEmpty) record.journal,
      issue,
      _doiUrl(record.doi),
    ]);
  }

  static String _chicago(LiteratureRecord record) => _sentence([
    if (record.authors.isNotEmpty) _displayAuthors(record.authors),
    record.year?.toString() ?? 'n.d.',
    '“${_stripTerminal(record.title)}.”',
    _journalBlock(record),
    _doiUrl(record.doi),
  ]);

  static String _vancouver(LiteratureRecord record) => _sentence([
    _vancouverAuthors(record.authors),
    _terminal(record.title),
    if (record.journal.isNotEmpty) record.journal,
    _compactPublication(record),
    _doiLabel(record.doi),
  ]);

  static String _ieee(LiteratureRecord record) => _sentence([
    _initialAuthors(record.authors),
    '“${_stripTerminal(record.title)},”',
    if (record.journal.isNotEmpty) record.journal,
    if (record.volume.isNotEmpty) 'vol. ${record.volume}',
    if (record.issue.isNotEmpty) 'no. ${record.issue}',
    if (record.pages.isNotEmpty) 'pp. ${record.pages}',
    if (record.year != null) '${record.year}',
    _doiLabel(record.doi),
  ]);

  static String _gb(LiteratureRecord record) {
    final authors = record.authors
        .map((author) => author.toUpperCase())
        .join(', ');
    final publication = <String>[
      if (record.journal.isNotEmpty) record.journal,
      if (record.year != null) '${record.year}',
      if (record.volume.isNotEmpty) record.volume,
      if (record.issue.isNotEmpty) '(${record.issue})',
      if (record.pages.isNotEmpty) ': ${record.pages}',
    ].join(', ').replaceAll(', (', '(').replaceAll(', :', ':');
    return _sentence([
      if (authors.isNotEmpty) authors,
      '${_stripTerminal(record.title)}[J]',
      publication,
      _doiLabel(record.doi),
    ]);
  }

  static String _authorYear(LiteratureRecord record) {
    final year = record.year?.toString() ?? 'n.d.';
    if (record.authors.isEmpty) return '${record.title}, $year';
    final first = _family(record.authors.first);
    if (record.authors.length == 1) return '$first, $year';
    if (record.authors.length == 2) {
      return '$first & ${_family(record.authors.last)}, $year';
    }
    return '$first et al., $year';
  }

  static String _apaAuthors(List<String> authors) {
    final values = authors.map(_familyInitials).toList(growable: false);
    if (values.length <= 1) return values.join();
    if (values.length <= 20) {
      return '${values.take(values.length - 1).join(', ')}, & ${values.last}';
    }
    return '${values.take(19).join(', ')}, … ${values.last}';
  }

  static String _displayAuthors(List<String> authors) {
    if (authors.length <= 2) return authors.join(', and ');
    return '${authors.first}, et al.';
  }

  static String _vancouverAuthors(List<String> authors) {
    final values = authors.map(_vancouverName).toList(growable: false);
    return values.length <= 6
        ? values.join(', ')
        : '${values.take(6).join(', ')}, et al.';
  }

  static String _initialAuthors(List<String> authors) =>
      authors.map(_initialFamily).join(', ');

  static String _familyInitials(String author) {
    final parts = _nameParts(author);
    if (parts.isEmpty) return '';
    final family = parts.last;
    final initials = parts
        .take(parts.length - 1)
        .map((part) => '${part[0]}.')
        .join(' ');
    return initials.isEmpty ? family : '$family, $initials';
  }

  static String _vancouverName(String author) {
    final parts = _nameParts(author);
    if (parts.isEmpty) return '';
    final initials = parts.take(parts.length - 1).map((part) => part[0]).join();
    return '${parts.last} $initials'.trim();
  }

  static String _initialFamily(String author) {
    final parts = _nameParts(author);
    if (parts.isEmpty) return '';
    final initials = parts
        .take(parts.length - 1)
        .map((part) => '${part[0]}.')
        .join(' ');
    return '$initials ${parts.last}'.trim();
  }

  static String _family(String author) {
    final parts = _nameParts(author);
    return parts.isEmpty ? '' : parts.last.toLowerCase();
  }

  static List<String> _nameParts(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return const <String>[];
    if (normalized.contains(',')) {
      final parts = normalized.split(',');
      return <String>[
        ...parts.skip(1).join(' ').trim().split(RegExp(r'\s+')),
        parts.first.trim(),
      ].where((part) => part.isNotEmpty).toList(growable: false);
    }
    return normalized.split(RegExp(r'\s+'));
  }

  static String _journalBlock(LiteratureRecord record) {
    final pieces = <String>[
      if (record.journal.isNotEmpty) record.journal,
      if (record.volume.isNotEmpty) record.volume,
      if (record.issue.isNotEmpty) '(${record.issue})',
      if (record.pages.isNotEmpty) record.pages,
    ];
    return pieces.join(', ').replaceAll(', (', '(');
  }

  static String _compactPublication(LiteratureRecord record) {
    final year = record.year?.toString() ?? '';
    final volumeIssue =
        '${record.volume}${record.issue.isEmpty ? '' : '(${record.issue})'}';
    final dateAndVolume = [
      if (year.isNotEmpty) year,
      if (volumeIssue.isNotEmpty) volumeIssue,
    ].join(';');
    if (record.pages.isEmpty) return dateAndVolume;
    return dateAndVolume.isEmpty
        ? record.pages
        : '$dateAndVolume:${record.pages}';
  }

  static String _doiUrl(String? doi) =>
      doi?.trim().isNotEmpty == true ? 'https://doi.org/${doi!.trim()}' : '';

  static String _doiLabel(String? doi) =>
      doi?.trim().isNotEmpty == true ? 'doi:${doi!.trim()}' : '';

  static String _sentence(Iterable<String> pieces) => pieces
      .map((piece) => piece.trim())
      .where((piece) => piece.isNotEmpty)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _terminal(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || RegExp(r'[.!?]$').hasMatch(trimmed)
        ? trimmed
        : '$trimmed.';
  }

  static String _stripTerminal(String value) =>
      value.trim().replaceFirst(RegExp(r'[.!?]+$'), '');

  static bool _numeric(LiteratureCitationStyle style) => switch (style) {
    LiteratureCitationStyle.vancouver ||
    LiteratureCitationStyle.ieee ||
    LiteratureCitationStyle.gbT7714 => true,
    _ => false,
  };

  static String _rtf(List<String> entries) {
    final body = entries.map(_escapeRtf).join(r'\par\par ');
    return '${r'{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\fs22 '}$body}';
  }

  static String _escapeRtf(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune == 0x5c) {
        buffer.write(r'\\');
      } else if (rune == 0x7b) {
        buffer.write(r'\{');
      } else if (rune == 0x7d) {
        buffer.write(r'\}');
      } else if (rune >= 0x20 && rune <= 0x7e) {
        buffer.writeCharCode(rune);
      } else {
        final signed = rune > 32767 ? rune - 65536 : rune;
        buffer.write('\\u$signed?');
      }
    }
    return buffer.toString();
  }
}
