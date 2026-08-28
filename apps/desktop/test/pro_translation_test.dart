import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picklogic_desktop/src/pro_translation.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';

void main() {
  test(
    'instant translation needs no key and exposes bounded alternatives',
    () async {
      Uri? requestedUri;
      final provider = PickLogicInstantTranslationProvider(
        request: (uri) async {
          requestedUri = uri;
          return <String, Object?>{
            'responseStatus': 200,
            'responseData': <String, Object?>{'translatedText': '晶界扩散'},
            'matches': <Object?>[
              <String, Object?>{'translation': '晶界扩散', 'quality': '100'},
              <String, Object?>{'translation': '沿晶扩散', 'quality': '92'},
            ],
          };
        },
      );

      expect(await provider.isConfigured(), isTrue);
      expect(provider.kind, TranslationProviderKind.publicAnonymous);
      final result = await provider.translateSelectedText(
        'grain-boundary diffusion',
        targetLanguage: 'Simplified Chinese',
      );

      expect(requestedUri?.host, 'api.mymemory.translated.net');
      expect(requestedUri?.queryParameters['q'], 'grain-boundary diffusion');
      expect(requestedUri?.queryParameters['langpair'], 'en|zh-CN');
      expect(result.translatedText, '晶界扩散');
      expect(result.alternatives, hasLength(1));
      expect(result.alternatives.single.translatedText, '沿晶扩散');
      expect(result.alternatives.single.label, 'MyMemory · 92%');
    },
  );

  test('instant translation enforces the public short-query limit', () async {
    final provider = PickLogicInstantTranslationProvider(
      request: (_) async => <String, Object?>{},
    );

    expect(
      () => provider.translateSelectedText(
        List<String>.filled(501, 'x').join(),
        targetLanguage: 'Simplified Chinese',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('translation engine choice is one-click and persists locally', () async {
    final directory = await Directory.systemTemp.createTemp(
      'picklogic-translation-engine-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}engine.json';
    final first = WindowsTranslationProviderHub(choicePath: path);

    await first.initialize();
    expect(first.selectedEngine, TranslationEngineChoice.off);
    await first.selectEngine(TranslationEngineChoice.instant);

    final restored = WindowsTranslationProviderHub(choicePath: path);
    await restored.initialize();
    expect(restored.selectedEngine, TranslationEngineChoice.instant);
  });
}
