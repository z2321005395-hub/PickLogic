import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:picklogic_literature_core/picklogic_literature_core.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';
import 'package:picklogic_windows_bridge/picklogic_windows_bridge.dart';

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
        title: Text(chinese ? '配置文献翻译' : 'Configure literature translation'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                chinese
                    ? '默认关闭。只发送你主动请求的选中文字、当前页或全文提取文字；绝不发送 PDF 文件。API Key 由 Windows DPAPI 保护。'
                    : 'Disabled by default. Only text from a selection, page, or document scope you explicitly request is sent; the PDF file is never sent. The API key is protected by Windows DPAPI.',
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
