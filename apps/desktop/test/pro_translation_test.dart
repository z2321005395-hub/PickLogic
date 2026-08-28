import 'dart:async';
import 'dart:convert';
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

  test('instant translation reuses the bounded in-memory cache', () async {
    var requestCount = 0;
    final provider = PickLogicInstantTranslationProvider(
      request: (_) async {
        requestCount++;
        return <String, Object?>{
          'responseStatus': 200,
          'responseData': <String, Object?>{'translatedText': '材料科学'},
        };
      },
    );

    final first = await provider.translateSelectedText(
      'materials science',
      targetLanguage: 'Simplified Chinese',
    );
    final second = await provider.translateSelectedText(
      'materials science',
      targetLanguage: 'Simplified Chinese',
    );

    expect(first.translatedText, '材料科学');
    expect(identical(first, second), isTrue);
    expect(requestCount, 1);
  });

  test(
    'UTF-8 query chunks start concurrently and stay within 500 bytes',
    () async {
      final requests = <Uri>[];
      final responses = <Completer<Map<String, Object?>>>[];
      final provider = PickLogicInstantTranslationProvider(
        request: (uri) {
          requests.add(uri);
          final response = Completer<Map<String, Object?>>();
          responses.add(response);
          return response.future;
        },
      );

      final pending = provider.translateSelectedText(
        List<String>.filled(300, '界').join(),
        targetLanguage: 'English',
      );
      await Future<void>.delayed(Duration.zero);

      expect(requests, hasLength(2));
      expect(
        requests.every(
          (uri) => utf8.encode(uri.queryParameters['q'] ?? '').length <= 500,
        ),
        isTrue,
      );
      for (var index = 0; index < responses.length; index++) {
        responses[index].complete(<String, Object?>{
          'responseStatus': 200,
          'responseData': <String, Object?>{
            'translatedText': 'chunk-${index + 1}',
          },
        });
      }

      final result = await pending;
      expect(result.translatedText, 'chunk-1\nchunk-2');
    },
  );

  test(
    'aggregate translation yields local terminology before network',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'picklogic-translation-aggregate-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final networkResponse = Completer<Map<String, Object?>>();
      final provider = PickLogicInstantTranslationProvider(
        request: (_) => networkResponse.future,
      );
      final hub = WindowsTranslationProviderHub(
        instantProvider: provider,
        choicePath: '${directory.path}${Platform.pathSeparator}engine.json',
      );
      await hub.selectEngine(TranslationEngineChoice.aggregate);

      final results = <SelectedTextTranslation>[];
      final firstResult = Completer<void>();
      final done = Completer<void>();
      hub
          .translateSelectedTextProgressively(
            'grain boundary',
            targetLanguage: 'Simplified Chinese',
            terminology: const <String, String>{'grain boundary': '晶界'},
          )
          .listen(
            (result) {
              results.add(result);
              if (!firstResult.isCompleted) firstResult.complete();
            },
            onError: done.completeError,
            onDone: done.complete,
          );

      await firstResult.future;
      expect(results.single.providerLabel, 'PickLogic Local');
      expect(results.single.translatedText, '晶界');
      networkResponse.complete(<String, Object?>{
        'responseStatus': 200,
        'responseData': <String, Object?>{'translatedText': '晶粒边界'},
      });
      await done.future;

      expect(results, hasLength(2));
      expect(results.last.providerLabel, contains('MyMemory'));
      expect(results.last.translatedText, '晶粒边界');
    },
  );

  test('translation engine choice is one-click and persists locally', () async {
    final directory = await Directory.systemTemp.createTemp(
      'picklogic-translation-engine-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}engine.json';
    final first = WindowsTranslationProviderHub(choicePath: path);

    await first.initialize();
    expect(first.selectedEngine, TranslationEngineChoice.off);
    await first.selectEngine(TranslationEngineChoice.aggregate);

    final restored = WindowsTranslationProviderHub(choicePath: path);
    await restored.initialize();
    expect(restored.selectedEngine, TranslationEngineChoice.aggregate);
  });
}
