enum TranslationProviderKind { disabled, openAiCompatible }

final class SelectedTextTranslation {
  const SelectedTextTranslation({
    required this.sourceText,
    required this.translatedText,
    required this.targetLanguage,
    required this.providerLabel,
  });

  final String sourceText;
  final String translatedText;
  final String targetLanguage;
  final String providerLabel;
}

abstract interface class TranslationProvider {
  TranslationProviderKind get kind;

  String get label;

  Future<bool> isConfigured();

  /// Translates only the explicit selection passed by the caller.
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
  });
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
  }) => Future<SelectedTextTranslation>.error(
    StateError('Translation is disabled.'),
  );
}
