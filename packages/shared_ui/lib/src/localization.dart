import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

final class PickLogicLocalizations {
  const PickLogicLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('zh')];

  static const LocalizationsDelegate<PickLogicLocalizations> delegate =
      _PickLogicLocalizationsDelegate();

  static PickLogicLocalizations of(BuildContext context) =>
      Localizations.of<PickLogicLocalizations>(
        context,
        PickLogicLocalizations,
      ) ??
      const PickLogicLocalizations(Locale('en'));

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'files': 'Files',
      'screenshots': 'Screenshots',
      'photos': 'Photos',
      'storage': 'Storage',
      'search': 'Search',
      'insight': 'Insight',
    },
    'zh': {
      'files': '文件',
      'screenshots': '截图',
      'photos': '照片',
      'storage': '存储',
      'search': '搜索',
      'insight': '知件',
    },
  };

  String text(String key) =>
      _values[locale.languageCode]?[key] ?? _values['en']![key] ?? key;
}

final class _PickLogicLocalizationsDelegate
    extends LocalizationsDelegate<PickLogicLocalizations> {
  const _PickLogicLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => PickLogicLocalizations.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<PickLogicLocalizations> load(Locale locale) =>
      SynchronousFuture(PickLogicLocalizations(locale));

  @override
  bool shouldReload(_PickLogicLocalizationsDelegate old) => false;
}
