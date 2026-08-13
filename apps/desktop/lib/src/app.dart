import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:picklogic_shared_ui/picklogic_shared_ui.dart';

import 'desktop_repository.dart';
import 'standard_explorer.dart';

void runPickLogicDesktop({required bool pro}) {
  runApp(PickLogicDesktopApp(pro: pro, repository: WindowsDesktopRepository()));
}

final class PickLogicDesktopApp extends StatefulWidget {
  const PickLogicDesktopApp({
    super.key,
    required this.pro,
    this.repository = const SyntheticDesktopRepository(),
    this.proPdfReaderBuilder,
  });

  final bool pro;
  final DesktopRepository repository;
  final WidgetBuilder? proPdfReaderBuilder;

  @override
  State<PickLogicDesktopApp> createState() => _PickLogicDesktopAppState();
}

final class _PickLogicDesktopAppState extends State<PickLogicDesktopApp> {
  Locale _locale = const Locale('zh');

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: _locale.languageCode == 'zh'
        ? (widget.pro ? '拾理专业版' : '拾理')
        : (widget.pro ? 'PickLogic Pro' : 'PickLogic'),
    theme: PickLogicTokens.lightTheme(),
    darkTheme: PickLogicTokens.darkTheme(),
    locale: _locale,
    supportedLocales: PickLogicLocalizations.supportedLocales,
    localizationsDelegates: const [
      PickLogicLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: StandardExplorer(
      pro: widget.pro,
      repository: widget.repository,
      proPdfReaderBuilder: widget.proPdfReaderBuilder,
      locale: _locale,
      onLocaleChanged: (locale) => setState(() => _locale = locale),
    ),
  );
}
