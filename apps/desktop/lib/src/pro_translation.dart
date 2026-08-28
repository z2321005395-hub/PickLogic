import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

enum TranslationEngineChoice { off, aggregate, instant, openAiCompatible }

typedef PublicTranslationRequest =
    Future<Map<String, Object?>> Function(Uri uri);

/// No-key short-text translation available from the selection workflow.
///
/// PickLogic accepts selections of up to 2,000 characters and splits them into
/// anonymous MyMemory requests of at most 500 UTF-8 bytes. At most four chunks
/// run concurrently so a cross-page paragraph stays responsive without
/// flooding the public service. It sends only the selected text; PDF bytes,
/// images, paths, and library metadata stay local.
final class PickLogicInstantTranslationProvider implements TranslationProvider {
  PickLogicInstantTranslationProvider({PublicTranslationRequest? request})
    : _requestOverride = request,
      _client = request == null ? _createClient() : null;

  static const _maxSelectionCharacters = 2000;
  static const _maxQueryBytes = 500;
  static const _maxConcurrentRequests = 4;
  static const _maxResponseBytes = 512 * 1024;
  static const _requestTimeout = Duration(seconds: 8);
  static const _cacheCapacity = 96;
  final PublicTranslationRequest? _requestOverride;
  final HttpClient? _client;
  final LinkedHashMap<String, SelectedTextTranslation> _cache =
      LinkedHashMap<String, SelectedTextTranslation>();
  final Map<String, Future<SelectedTextTranslation>> _inFlight =
      <String, Future<SelectedTextTranslation>>{};

  @override
  TranslationProviderKind get kind => TranslationProviderKind.publicAnonymous;

  @override
  String get label => 'PickLogic Instant · MyMemory';

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async {
    final source = selectedText.trim();
    if (source.isEmpty) throw const FormatException('Select text first.');
    if (source.length > _maxSelectionCharacters) {
      throw const FormatException(
        'Instant translation accepts up to 2,000 selected characters.',
      );
    }
    final cacheKey = '${targetLanguage.trim().toLowerCase()}\u0000$source';
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }
    final existing = _inFlight[cacheKey];
    if (existing != null) return existing;
    final pending = _translateUncached(source, targetLanguage);
    _inFlight[cacheKey] = pending;
    try {
      final result = await pending;
      _cache[cacheKey] = result;
      while (_cache.length > _cacheCapacity) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<SelectedTextTranslation> _translateUncached(
    String source,
    String targetLanguage,
  ) async {
    final targetCode = targetLanguage.toLowerCase().startsWith('english')
        ? 'en'
        : 'zh-CN';
    final sourceCode = targetCode == 'en' ? 'zh-CN' : 'en';
    final chunks = _boundedUtf8Chunks(source);
    final translatedChunks = List<SelectedTextTranslation?>.filled(
      chunks.length,
      null,
    );
    var nextChunk = 0;
    Future<void> translateNextChunk() async {
      while (nextChunk < chunks.length) {
        final index = nextChunk++;
        translatedChunks[index] = await _translateChunk(
          chunks[index],
          sourceCode: sourceCode,
          targetCode: targetCode,
          targetLanguage: targetLanguage,
        );
      }
    }

    final workerCount = chunks.length < _maxConcurrentRequests
        ? chunks.length
        : _maxConcurrentRequests;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => translateNextChunk()),
    );
    final completedChunks = translatedChunks
        .whereType<SelectedTextTranslation>();
    if (translatedChunks.length == 1) return translatedChunks.single!;
    return SelectedTextTranslation(
      sourceText: source,
      translatedText: completedChunks
          .map((result) => result.translatedText.trim())
          .join('\n'),
      targetLanguage: targetLanguage,
      providerLabel: label,
    );
  }

  Future<SelectedTextTranslation> _translateChunk(
    String source, {
    required String sourceCode,
    required String targetCode,
    required String targetLanguage,
  }) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': source,
      'langpair': '$sourceCode|$targetCode',
    });
    final decoded = await (_requestOverride?.call(uri) ?? _requestJson(uri))
        .timeout(_requestTimeout);
    final responseStatus = decoded['responseStatus'];
    if (responseStatus != null && responseStatus.toString() != '200') {
      throw HttpException(
        decoded['responseDetails']?.toString() ??
            'Instant translation returned $responseStatus.',
        uri: uri,
      );
    }
    final responseData = decoded['responseData'];
    final primary = responseData is Map
        ? _decodeEntities(responseData['translatedText']?.toString() ?? '')
        : '';
    if (primary.trim().isEmpty) {
      throw const FormatException('Instant translation returned no text.');
    }

    final alternatives = <TranslationAlternative>[];
    final seen = <String>{primary.trim().toLowerCase()};
    final matches = decoded['matches'];
    if (matches is List) {
      for (final match in matches) {
        if (match is! Map) continue;
        final translated = _decodeEntities(
          match['translation']?.toString() ?? '',
        ).trim();
        if (translated.isEmpty || !seen.add(translated.toLowerCase())) continue;
        final quality = match['quality']?.toString().trim();
        alternatives.add(
          TranslationAlternative(
            label: quality?.isNotEmpty == true
                ? 'MyMemory · $quality%'
                : 'MyMemory · Alternative',
            translatedText: translated,
          ),
        );
        if (alternatives.length == 3) break;
      }
    }
    return SelectedTextTranslation(
      sourceText: source,
      translatedText: primary.trim(),
      targetLanguage: targetLanguage,
      providerLabel: label,
      alternatives: List<TranslationAlternative>.unmodifiable(alternatives),
    );
  }

  static List<String> _boundedUtf8Chunks(String source) {
    if (utf8.encode(source).length <= _maxQueryBytes) return <String>[source];
    final chunks = <String>[];
    var buffer = StringBuffer();
    var byteLength = 0;
    for (final rune in source.runes) {
      final character = String.fromCharCode(rune);
      final characterBytes = utf8.encode(character).length;
      if (byteLength + characterBytes > _maxQueryBytes && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer = StringBuffer();
        byteLength = 0;
      }
      buffer.write(character);
      byteLength += characterBytes;
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) chunks.add(tail);
    return chunks;
  }

  static HttpClient _createClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 60)
    ..maxConnectionsPerHost = 4;

  Future<Map<String, Object?>> _requestJson(Uri uri) async {
    final request = await _client!.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'PickLogic/0.1');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_requestTimeout);
    final bytes = <int>[];
    await for (final chunk in response.timeout(_requestTimeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _maxResponseBytes) {
        throw const FormatException(
          'Instant translation response is too large.',
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Instant translation returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map) {
      throw const FormatException('Instant translation returned invalid JSON.');
    }
    return Map<String, Object?>.from(value);
  }

  static String _decodeEntities(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

final class TranslationConfiguration {
  const TranslationConfiguration({
    required this.endpoint,
    required this.model,
    required this.keyPresent,
  });

  final String endpoint;
  final String model;
  final bool keyPresent;
}

/// Opt-in OpenAI-compatible translator for explicitly requested PDF text.
///
/// Endpoint/model are app-owned preferences. The API key is stored by the
/// Windows bridge with DPAPI and is never written to JSON or logs.
final class WindowsOpenAiCompatibleTranslationProvider
    implements TranslationProvider {
  WindowsOpenAiCompatibleTranslationProvider({
    this._bridge = const PicklogicWindowsBridge(),
    String? settingsPath,
  }) : _settingsPath = settingsPath ?? _defaultSettingsPath();

  static const _secretName = 'translation-openai-compatible-api-key';
  static const _maxSelectionCharacters = 8000;
  static const _maxResponseBytes = 1024 * 1024;

  final PicklogicWindowsBridge _bridge;
  final String _settingsPath;

  @override
  TranslationProviderKind get kind => TranslationProviderKind.openAiCompatible;

  @override
  String get label => 'OpenAI-compatible';

  Future<TranslationConfiguration> loadConfiguration() async {
    var endpoint = '';
    var model = '';
    final file = File(_settingsPath);
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded case final Map<String, Object?> map) {
          endpoint = map['endpoint'] as String? ?? '';
          model = map['model'] as String? ?? '';
        }
      } on Object {
        // Invalid app-owned preferences disable online translation safely.
      }
    }
    final key = endpoint.isNotEmpty && model.isNotEmpty
        ? await _bridge.readProtectedSecret(_secretName)
        : null;
    return TranslationConfiguration(
      endpoint: endpoint,
      model: model,
      keyPresent: key?.isNotEmpty == true,
    );
  }

  Future<void> saveConfiguration({
    required String endpoint,
    required String model,
    String? newApiKey,
    bool removeApiKey = false,
  }) async {
    final normalizedEndpoint = endpoint.trim();
    final normalizedModel = model.trim();
    if (normalizedEndpoint.isNotEmpty) {
      _validatedEndpoint(normalizedEndpoint);
      if (normalizedModel.isEmpty) {
        throw const FormatException('A model name is required.');
      }
    }
    final file = File(_settingsPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, String>{
        'endpoint': normalizedEndpoint,
        'model': normalizedModel,
      }),
      flush: true,
    );
    if (removeApiKey) {
      await _bridge.deleteProtectedSecret(_secretName);
    } else if (newApiKey?.trim().isNotEmpty == true) {
      await _bridge.writeProtectedSecret(_secretName, newApiKey!.trim());
    }
  }

  @override
  Future<bool> isConfigured() async {
    final configuration = await loadConfiguration();
    return configuration.endpoint.isNotEmpty &&
        configuration.model.isNotEmpty &&
        configuration.keyPresent;
  }

  @override
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async {
    final source = selectedText.trim();
    if (source.isEmpty) throw const FormatException('Select text first.');
    if (source.length > _maxSelectionCharacters) {
      throw const FormatException('The selection exceeds 8000 characters.');
    }
    final configuration = await loadConfiguration();
    final apiKey = await _bridge.readProtectedSecret(_secretName);
    if (configuration.endpoint.isEmpty ||
        configuration.model.isEmpty ||
        apiKey?.isNotEmpty != true) {
      throw StateError('Translation provider is not configured.');
    }
    final endpoint = _validatedEndpoint(configuration.endpoint);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 20)
      ..maxConnectionsPerHost = 1;
    try {
      final terminologyPrompt = _terminologyPrompt(terminology);
      final request = await client.postUrl(endpoint);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(
        jsonEncode(<String, Object>{
          'model': configuration.model,
          'temperature': 0,
          'messages': <Map<String, String>>[
            <String, String>{
              'role': 'system',
              'content':
                  'Translate only the user-selected text into $targetLanguage. '
                  'Preserve equations, citations, and paragraph breaks. '
                  'Return only the translation.'
                  '${terminologyPrompt.isEmpty ? '' : ' $terminologyPrompt'}',
            },
            <String, String>{'role': 'user', 'content': source},
          ],
        }),
      );
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > _maxResponseBytes) {
          throw const FormatException('Translation response is too large.');
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Translation service returned HTTP ${response.statusCode}.',
          uri: endpoint,
        );
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final translated = _responseText(decoded);
      return SelectedTextTranslation(
        sourceText: source,
        translatedText: translated,
        targetLanguage: targetLanguage,
        providerLabel: label,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Uri _validatedEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    final localHttp =
        uri?.scheme == 'http' &&
        const <String>{'localhost', '127.0.0.1', '::1'}.contains(uri?.host);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && !localHttp)) {
      throw const FormatException(
        'Use an HTTPS endpoint, or HTTP only for localhost.',
      );
    }
    return uri;
  }

  static String _responseText(Object? decoded) {
    if (decoded case {
      'choices': [{'message': {'content': final String content}}, ...],
    }) {
      final value = content.trim();
      if (value.isNotEmpty) return value;
    }
    throw const FormatException('Translation response did not contain text.');
  }

  static String _terminologyPrompt(Map<String, String> terminology) {
    if (terminology.isEmpty) return '';
    final lines = <String>[];
    var length = 0;
    for (final entry in terminology.entries.take(100)) {
      final source = entry.key.trim();
      final translated = entry.value.trim();
      if (source.isEmpty || translated.isEmpty) continue;
      final line = '$source => $translated';
      if (length + line.length > 4000) break;
      lines.add(line);
      length += line.length;
    }
    return lines.isEmpty
        ? ''
        : 'Use this user terminology consistently:\n${lines.join('\n')}';
  }

  static String _defaultSettingsPath() {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null || base.trim().isEmpty) {
      throw StateError('LOCALAPPDATA is unavailable.');
    }
    return '$base${Platform.pathSeparator}PickLogic${Platform.pathSeparator}translation.json';
  }
}

/// Switches between a zero-configuration public engine and the optional
/// user-configured OpenAI-compatible engine without changing reader code.
final class WindowsTranslationProviderHub
    implements TranslationProvider, ProgressiveTranslationProvider {
  WindowsTranslationProviderHub({
    PickLogicInstantTranslationProvider? instantProvider,
    WindowsOpenAiCompatibleTranslationProvider? advancedProvider,
    String? choicePath,
  }) : instantProvider =
           instantProvider ?? PickLogicInstantTranslationProvider(),
       _openAiProvider = advancedProvider,
       _choicePath = choicePath ?? _defaultChoicePath();

  final PickLogicInstantTranslationProvider instantProvider;
  WindowsOpenAiCompatibleTranslationProvider? _openAiProvider;
  final String? _choicePath;
  final LinkedHashMap<String, List<SelectedTextTranslation>> _aggregateCache =
      LinkedHashMap<String, List<SelectedTextTranslation>>();
  TranslationEngineChoice _selectedEngine = TranslationEngineChoice.off;
  bool _initialized = false;

  TranslationEngineChoice get selectedEngine => _selectedEngine;
  WindowsOpenAiCompatibleTranslationProvider get openAiProvider =>
      _openAiProvider ??= WindowsOpenAiCompatibleTranslationProvider();

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final choicePath = _choicePath;
    if (choicePath == null) return;
    final file = File(choicePath);
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded case {'engine': final String engine}) {
        _selectedEngine = TranslationEngineChoice.values.firstWhere(
          (candidate) => candidate.name == engine,
          orElse: () => TranslationEngineChoice.off,
        );
      }
    } on Object {
      _selectedEngine = TranslationEngineChoice.off;
    }
  }

  Future<void> selectEngine(TranslationEngineChoice choice) async {
    await initialize();
    _selectedEngine = choice;
    _aggregateCache.clear();
    final choicePath = _choicePath;
    if (choicePath == null) return;
    final file = File(choicePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(' ').convert({'engine': choice.name}),
      flush: true,
    );
  }

  TranslationProvider get _activeProvider => switch (_selectedEngine) {
    TranslationEngineChoice.off => const DisabledTranslationProvider(),
    TranslationEngineChoice.aggregate => instantProvider,
    TranslationEngineChoice.instant => instantProvider,
    TranslationEngineChoice.openAiCompatible => openAiProvider,
  };

  @override
  TranslationProviderKind get kind => _activeProvider.kind;

  @override
  String get label => _activeProvider.label;

  @override
  Future<bool> isConfigured() async {
    await initialize();
    if (_selectedEngine == TranslationEngineChoice.aggregate) return true;
    return _activeProvider.isConfigured();
  }

  @override
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async {
    await initialize();
    if (_selectedEngine == TranslationEngineChoice.aggregate) {
      final local = _exactTerminologyTranslation(
        selectedText,
        targetLanguage,
        terminology,
      );
      if (local != null) return local;
    }
    return _activeProvider.translateSelectedText(
      selectedText,
      targetLanguage: targetLanguage,
      terminology: terminology,
    );
  }

  @override
  Stream<SelectedTextTranslation> translateSelectedTextProgressively(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async* {
    await initialize();
    if (_selectedEngine != TranslationEngineChoice.aggregate) {
      yield await translateSelectedText(
        selectedText,
        targetLanguage: targetLanguage,
        terminology: terminology,
      );
      return;
    }

    final source = selectedText.trim();
    if (source.isEmpty) throw const FormatException('Select text first.');
    final cacheKey = _aggregateCacheKey(source, targetLanguage, terminology);
    final cached = _aggregateCache.remove(cacheKey);
    if (cached != null) {
      _aggregateCache[cacheKey] = cached;
      yield* Stream<SelectedTextTranslation>.fromIterable(cached);
      return;
    }

    final pending = <int, Future<_TranslationCompletion>>{};
    var taskIndex = 0;
    Future<void> addTask(Future<SelectedTextTranslation?> task) async {
      final index = taskIndex++;
      pending[index] = task
          .then((result) => _TranslationCompletion(index, result: result))
          .catchError(
            (Object error, StackTrace stackTrace) =>
                _TranslationCompletion(index, error: error),
          );
    }

    await addTask(
      instantProvider
          .translateSelectedText(
            source,
            targetLanguage: targetLanguage,
            terminology: terminology,
          )
          .then<SelectedTextTranslation?>((value) => value),
    );
    await addTask(
      _translateWithAdvancedIfConfigured(
        source,
        targetLanguage: targetLanguage,
        terminology: terminology,
      ),
    );

    final results = <SelectedTextTranslation>[];
    final local = _exactTerminologyTranslation(
      source,
      targetLanguage,
      terminology,
    );
    if (local != null) {
      results.add(local);
      yield local;
    }

    Object? firstError;
    while (pending.isNotEmpty) {
      final completion = await Future.any(pending.values);
      pending.remove(completion.index);
      final result = completion.result;
      if (result != null) {
        results.add(result);
        yield result;
      } else if (completion.error != null) {
        firstError ??= completion.error;
      }
    }
    if (results.isEmpty && firstError != null) throw firstError;
    if (results.isNotEmpty) {
      _aggregateCache[cacheKey] = List<SelectedTextTranslation>.unmodifiable(
        results,
      );
      while (_aggregateCache.length > 64) {
        _aggregateCache.remove(_aggregateCache.keys.first);
      }
    }
  }

  Future<SelectedTextTranslation?> _translateWithAdvancedIfConfigured(
    String source, {
    required String targetLanguage,
    required Map<String, String> terminology,
  }) async {
    if (!await openAiProvider.isConfigured()) return null;
    return openAiProvider
        .translateSelectedText(
          source,
          targetLanguage: targetLanguage,
          terminology: terminology,
        )
        .timeout(const Duration(seconds: 12));
  }

  static SelectedTextTranslation? _exactTerminologyTranslation(
    String source,
    String targetLanguage,
    Map<String, String> terminology,
  ) {
    final normalized = source.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final toEnglish = targetLanguage.toLowerCase().startsWith('english');
    for (final entry in terminology.entries) {
      final from = (toEnglish ? entry.value : entry.key).trim();
      final to = (toEnglish ? entry.key : entry.value).trim();
      if (from.toLowerCase() == normalized && to.isNotEmpty) {
        return SelectedTextTranslation(
          sourceText: source.trim(),
          translatedText: to,
          targetLanguage: targetLanguage,
          providerLabel: 'PickLogic Local',
        );
      }
    }
    return null;
  }

  static String _aggregateCacheKey(
    String source,
    String targetLanguage,
    Map<String, String> terminology,
  ) {
    final entries = terminology.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final terms = entries
        .take(100)
        .map((entry) => '${entry.key}\u0001${entry.value}')
        .join('\u0002');
    return '${targetLanguage.trim().toLowerCase()}\u0000$source\u0000$terms';
  }

  static String? _defaultChoicePath() {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null || base.trim().isEmpty) return null;
    return '$base${Platform.pathSeparator}PickLogic${Platform.pathSeparator}translation_engine.json';
  }
}

final class _TranslationCompletion {
  const _TranslationCompletion(this.index, {this.result, this.error});

  final int index;
  final SelectedTextTranslation? result;
  final Object? error;
}

Future<void> showTranslationConfigurationDialog(
  BuildContext context,
  WindowsOpenAiCompatibleTranslationProvider provider,
) async {
  final configuration = await provider.loadConfiguration();
  if (!context.mounted) return;
  final chinese =
      PickLogicLocalizations.of(context).locale.languageCode == 'zh';
  final endpoint = TextEditingController(text: configuration.endpoint);
  final model = TextEditingController(text: configuration.model);
  final key = TextEditingController();
  var removeKey = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        key: const Key('translation-configuration-dialog'),
        title: Text(
          chinese ? '配置高级 AI 翻译' : 'Configure advanced AI translation',
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                chinese
                    ? '这是可选高级引擎。免密“即时翻译”无需这里的任何设置。使用 AI 模型时只发送所选文字；绝不发送 PDF 文件或图片，API Key 由 Windows DPAPI 保护。'
                    : 'This is an optional advanced engine. Instant translation needs no setup here. The AI engine receives only selected text, never PDF files or images, and its API key is protected by Windows DPAPI.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('translation-endpoint-field'),
                controller: endpoint,
                decoration: const InputDecoration(
                  labelText: 'OpenAI-compatible HTTPS endpoint',
                  hintText: 'https://…/v1/chat/completions',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('translation-model-field'),
                controller: model,
                decoration: InputDecoration(
                  labelText: chinese ? '模型名称' : 'Model name',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('translation-api-key-field'),
                controller: key,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  helperText: configuration.keyPresent
                      ? (chinese
                            ? '已安全保存；留空表示保持不变'
                            : 'Securely stored; leave blank to keep it')
                      : (chinese ? '尚未配置' : 'Not configured'),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: removeKey,
                onChanged: (value) =>
                    setDialogState(() => removeKey = value ?? false),
                title: Text(chinese ? '移除已保存的 Key' : 'Remove stored key'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(chinese ? '取消' : 'Cancel'),
          ),
          FilledButton(
            key: const Key('translation-save-action'),
            onPressed: () async {
              try {
                await provider.saveConfiguration(
                  endpoint: endpoint.text,
                  model: model.text,
                  newApiKey: key.text,
                  removeApiKey: removeKey,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } on Object catch (failure) {
                setDialogState(() => error = failure.toString());
              }
            },
            child: Text(chinese ? '保存' : 'Save'),
          ),
        ],
      ),
    ),
  );
  endpoint.dispose();
  model.dispose();
  key.dispose();
}
