import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

final class LiteraturePageTranslation {
  LiteraturePageTranslation({
    required this.literatureId,
    required this.pageNumber,
    required this.targetLanguage,
    required this.sourceText,
    required this.translatedText,
    required this.providerLabel,
    required this.updatedAt,
  }) : sourceFingerprint = fingerprint(sourceText) {
    if (literatureId.trim().isEmpty || targetLanguage.trim().isEmpty) {
      throw ArgumentError('Literature ID and target language are required.');
    }
    if (pageNumber < 1) {
      throw RangeError.value(pageNumber, 'pageNumber', 'Must be positive.');
    }
    if (sourceText.trim().isEmpty || translatedText.trim().isEmpty) {
      throw ArgumentError('Source and translated text are required.');
    }
  }

  final String literatureId;
  final int pageNumber;
  final String targetLanguage;
  final String sourceText;
  final String translatedText;
  final String providerLabel;
  final DateTime updatedAt;
  final String sourceFingerprint;

  static String fingerprint(String source) {
    const offsetBasis = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    var hash = offsetBasis;
    for (final codeUnit in source.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

final class LiteratureTerminologyEntry {
  LiteratureTerminologyEntry({
    required this.id,
    required this.sourceTerm,
    required this.translatedTerm,
    required this.targetLanguage,
    required this.updatedAt,
  }) {
    if (id.trim().isEmpty ||
        sourceTerm.trim().isEmpty ||
        translatedTerm.trim().isEmpty ||
        targetLanguage.trim().isEmpty) {
      throw ArgumentError('Terminology fields must not be empty.');
    }
  }

  final String id;
  final String sourceTerm;
  final String translatedTerm;
  final String targetLanguage;
  final DateTime updatedAt;
}

abstract interface class LiteratureTranslationStore {
  Future<List<LiteraturePageTranslation>> loadPages({
    required String literatureId,
    required String targetLanguage,
  });

  Future<void> upsertPage(LiteraturePageTranslation translation);

  Future<void> deletePage({
    required String literatureId,
    required int pageNumber,
    required String targetLanguage,
  });

  Future<List<LiteratureTerminologyEntry>> loadTerminology(
    String targetLanguage,
  );

  Future<void> upsertTerm(LiteratureTerminologyEntry term);

  Future<void> deleteTerm(String id);
}

final class InMemoryLiteratureTranslationStore
    implements LiteratureTranslationStore {
  final Map<String, LiteraturePageTranslation> _pages = {};
  final Map<String, LiteratureTerminologyEntry> _terms = {};

  @override
  Future<List<LiteraturePageTranslation>> loadPages({
    required String literatureId,
    required String targetLanguage,
  }) async =>
      _pages.values
          .where(
            (item) =>
                item.literatureId == literatureId &&
                item.targetLanguage == targetLanguage,
          )
          .toList(growable: false)
        ..sort((left, right) => left.pageNumber.compareTo(right.pageNumber));

  @override
  Future<void> upsertPage(LiteraturePageTranslation translation) async {
    _pages[_pageKey(
          translation.literatureId,
          translation.pageNumber,
          translation.targetLanguage,
        )] =
        translation;
  }

  @override
  Future<void> deletePage({
    required String literatureId,
    required int pageNumber,
    required String targetLanguage,
  }) async {
    _pages.remove(_pageKey(literatureId, pageNumber, targetLanguage));
  }

  @override
  Future<List<LiteratureTerminologyEntry>> loadTerminology(
    String targetLanguage,
  ) async =>
      _terms.values
          .where((item) => item.targetLanguage == targetLanguage)
          .toList(growable: false)
        ..sort(
          (left, right) => left.sourceTerm.toLowerCase().compareTo(
            right.sourceTerm.toLowerCase(),
          ),
        );

  @override
  Future<void> upsertTerm(LiteratureTerminologyEntry term) async {
    _terms[term.id] = term;
  }

  @override
  Future<void> deleteTerm(String id) async {
    _terms.remove(id);
  }
}

final class SqliteLiteratureTranslationStore
    implements LiteratureTranslationStore {
  const SqliteLiteratureTranslationStore(this.catalogPath);

  final String catalogPath;

  @override
  Future<List<LiteraturePageTranslation>> loadPages({
    required String literatureId,
    required String targetLanguage,
  }) async {
    final database = _open();
    try {
      return List<LiteraturePageTranslation>.unmodifiable(
        database
            .select(
              'SELECT literature_id, page_number, target_language, source_text, '
              'translated_text, provider_label, updated_at '
              'FROM literature_translations '
              'WHERE literature_id = ? AND target_language = ? '
              'ORDER BY page_number',
              <Object?>[literatureId, targetLanguage],
            )
            .map(_pageFromRow),
      );
    } finally {
      database.close();
    }
  }

  @override
  Future<void> upsertPage(LiteraturePageTranslation translation) async {
    final database = _open();
    try {
      database.execute(
        'INSERT OR REPLACE INTO literature_translations '
        '(literature_id, page_number, target_language, source_fingerprint, '
        'source_text, translated_text, provider_label, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          translation.literatureId,
          translation.pageNumber,
          translation.targetLanguage,
          translation.sourceFingerprint,
          translation.sourceText,
          translation.translatedText,
          translation.providerLabel,
          translation.updatedAt.toUtc().toIso8601String(),
        ],
      );
    } finally {
      database.close();
    }
  }

  @override
  Future<void> deletePage({
    required String literatureId,
    required int pageNumber,
    required String targetLanguage,
  }) async {
    final database = _open();
    try {
      database.execute(
        'DELETE FROM literature_translations '
        'WHERE literature_id = ? AND page_number = ? AND target_language = ?',
        <Object?>[literatureId, pageNumber, targetLanguage],
      );
    } finally {
      database.close();
    }
  }

  @override
  Future<List<LiteratureTerminologyEntry>> loadTerminology(
    String targetLanguage,
  ) async {
    final database = _open();
    try {
      return List<LiteratureTerminologyEntry>.unmodifiable(
        database
            .select(
              'SELECT term_id, source_term, translated_term, target_language, '
              'updated_at FROM literature_terminology '
              'WHERE target_language = ? ORDER BY source_term COLLATE NOCASE',
              <Object?>[targetLanguage],
            )
            .map(_termFromRow),
      );
    } finally {
      database.close();
    }
  }

  @override
  Future<void> upsertTerm(LiteratureTerminologyEntry term) async {
    final database = _open();
    try {
      database.execute(
        'INSERT OR REPLACE INTO literature_terminology '
        '(term_id, source_term, translated_term, target_language, updated_at) '
        'VALUES (?, ?, ?, ?, ?)',
        <Object?>[
          term.id,
          term.sourceTerm,
          term.translatedTerm,
          term.targetLanguage,
          term.updatedAt.toUtc().toIso8601String(),
        ],
      );
    } finally {
      database.close();
    }
  }

  @override
  Future<void> deleteTerm(String id) async {
    final database = _open();
    try {
      database.execute(
        'DELETE FROM literature_terminology WHERE term_id = ?',
        <Object?>[id],
      );
    } finally {
      database.close();
    }
  }

  Database _open() {
    final file = File(catalogPath);
    file.parent.createSync(recursive: true);
    final database = sqlite3.open(catalogPath);
    database.execute('''
      CREATE TABLE IF NOT EXISTS literature_translations (
        literature_id TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        target_language TEXT NOT NULL,
        source_fingerprint TEXT NOT NULL,
        source_text TEXT NOT NULL,
        translated_text TEXT NOT NULL,
        provider_label TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (literature_id, page_number, target_language)
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS literature_terminology (
        term_id TEXT PRIMARY KEY NOT NULL,
        source_term TEXT NOT NULL,
        translated_term TEXT NOT NULL,
        target_language TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    return database;
  }

  static LiteraturePageTranslation _pageFromRow(Row row) =>
      LiteraturePageTranslation(
        literatureId: row['literature_id']! as String,
        pageNumber: row['page_number']! as int,
        targetLanguage: row['target_language']! as String,
        sourceText: row['source_text']! as String,
        translatedText: row['translated_text']! as String,
        providerLabel: row['provider_label']! as String,
        updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      );

  static LiteratureTerminologyEntry _termFromRow(Row row) =>
      LiteratureTerminologyEntry(
        id: row['term_id']! as String,
        sourceTerm: row['source_term']! as String,
        translatedTerm: row['translated_term']! as String,
        targetLanguage: row['target_language']! as String,
        updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      );
}

String _pageKey(String literatureId, int pageNumber, String targetLanguage) =>
    '$literatureId\u0000$pageNumber\u0000$targetLanguage';
