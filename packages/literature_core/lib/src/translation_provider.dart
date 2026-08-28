enum TranslationProviderKind { disabled, publicAnonymous, openAiCompatible }

final class TranslationAlternative {
  const TranslationAlternative({
    required this.label,
    required this.translatedText,
  });

  final String label;
  final String translatedText;
}

final class SelectedTextTranslation {
  const SelectedTextTranslation({
    required this.sourceText,
    required this.translatedText,
    required this.targetLanguage,
    required this.providerLabel,
    this.alternatives = const <TranslationAlternative>[],
  });

  final String sourceText;
  final String translatedText;
  final String targetLanguage;
  final String providerLabel;
  final List<TranslationAlternative> alternatives;
}

abstract interface class TranslationProvider {
  TranslationProviderKind get kind;

  String get label;

  Future<bool> isConfigured();

  /// Translates only text from a scope explicitly requested by the user.
  /// Callers must never pass PDF bytes or silently extracted content.
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  });
}

extension ExplicitTranslationChunks on TranslationProvider {
  /// Translates an explicitly requested text scope in bounded sequential
  /// chunks. This keeps provider request size predictable without uploading
  /// the source document itself.
  Future<SelectedTextTranslation> translateExplicitTextInChunks(
    String text, {
    required String targetLanguage,
    int maxChunkCharacters = 6000,
    Map<String, String> terminology = const <String, String>{},
  }) async {
    final source = text.trim();
    if (source.isEmpty) throw const FormatException('Text must not be empty.');
    if (maxChunkCharacters < 500 || maxChunkCharacters > 8000) {
      throw RangeError.range(maxChunkCharacters, 500, 8000);
    }
    final chunks = _boundedTextChunks(source, maxChunkCharacters);
    final translated = <String>[];
    var providerLabel = label;
    for (final chunk in chunks) {
      final result = await translateSelectedText(
        chunk,
        targetLanguage: targetLanguage,
        terminology: terminology,
      );
      providerLabel = result.providerLabel;
      translated.add(result.translatedText.trim());
    }
    return SelectedTextTranslation(
      sourceText: source,
      translatedText: translated.join('\n\n'),
      targetLanguage: targetLanguage,
      providerLabel: providerLabel,
    );
  }
}

List<String> _boundedTextChunks(String source, int limit) {
  final chunks = <String>[];
  var start = 0;
  while (start < source.length) {
    var end = (start + limit).clamp(0, source.length);
    if (end < source.length) {
      final paragraphBreak = source.lastIndexOf('\n\n', end);
      final sentenceBreak = source.lastIndexOf(RegExp(r'[.!?。！？]\s'), end);
      final wordBreak = source.lastIndexOf(RegExp(r'\s'), end);
      final candidate = <int>[
        paragraphBreak >= start + limit ~/ 2 ? paragraphBreak + 2 : -1,
        sentenceBreak >= start + limit ~/ 2 ? sentenceBreak + 1 : -1,
        wordBreak >= start + limit ~/ 2 ? wordBreak + 1 : -1,
      ].where((value) => value > start).firstOrNull;
      if (candidate != null) end = candidate;
    }
    final chunk = source.substring(start, end).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    start = end;
    while (start < source.length && source.codeUnitAt(start) <= 0x20) {
      start++;
    }
  }
  return chunks;
}

final class DisabledTranslationProvider implements TranslationProvider {
  const DisabledTranslationProvider();

  @override
  TranslationProviderKind get kind => TranslationProviderKind.disabled;

  @override
  String get label => 'Disabled';

  @override
  Future<bool> isConfigured() async => false;

  @override
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) => Future<SelectedTextTranslation>.error(
    StateError('Translation is disabled.'),
  );
}
