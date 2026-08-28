import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

enum TranslationEngineChoice { off, instant, openAiCompatible }

typedef PublicTranslationRequest =
    Future<Map<String, Object?>> Function(Uri uri);

/// No-key short-text translation available from the selection workflow.
///
/// MyMemory accepts anonymous public requests with a 500-character query
/// limit. PickLogic sends only the text the user selected and keeps the PDF
/// bytes, images, paths, and library metadata local.
final class PickLogicInstantTranslationProvider implements TranslationProvider {
  PickLogicInstantTranslationProvider({PublicTranslationRequest? request})
    : _request = request ?? _requestJson;

  static const _maxCharacters = 500;
  static const _maxResponseBytes = 512 * 1024;
  final PublicTranslationRequest _request;

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
    if (source.length > _maxCharacters) {
      throw const FormatException(
        'Instant translation accepts up to 500 characters per request.',
      );
    }
    final targetCode = targetLanguage.toLowerCase().startsWith('english')
        ? 'en'
        : 'zh-CN';
    final sourceCode = targetCode == 'en' ? 'zh-CN' : 'en';
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': source,
      'langpair': '$sourceCode|$targetCode',
    });
    final decoded = await _request(uri);
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

  static Future<Map<String, Object?>> _requestJson(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 15)
      ..maxConnectionsPerHost = 1;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'PickLogic/0.1');
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
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
        throw const FormatException(
          'Instant translation returned invalid JSON.',
        );
      }
      return Map<String, Object?>.from(value);
    } finally {
      client.close(force: true);
    }
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
    final key = await _bridge.readProtectedSecret(_secretName);
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
final class WindowsTranslationProviderHub implements TranslationProvider {
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
    return _activeProvider.isConfigured();
  }

  @override
  Future<SelectedTextTranslation> translateSelectedText(
    String selectedText, {
    required String targetLanguage,
    Map<String, String> terminology = const <String, String>{},
  }) async {
    await initialize();
    return _activeProvider.translateSelectedText(
      selectedText,
      targetLanguage: targetLanguage,
      terminology: terminology,
    );
  }

  static String? _defaultChoicePath() {
    final base = Platform.environment['LOCALAPPDATA'];
    if (base == null || base.trim().isEmpty) return null;
    return '$base${Platform.pathSeparator}PickLogic${Platform.pathSeparator}translation_engine.json';
  }
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
