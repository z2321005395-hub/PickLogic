import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class PickLogicTokens {
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 18;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceSmd = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double iconSmall = 18;
  static const double iconMedium = 22;
  static const double iconLarge = 28;
  static const Duration motionShort = Duration(milliseconds: 160);

  static ThemeData lightTheme() => _theme(
    brightness: Brightness.light,
    seed: const Color(0xFF315C70),
    surface: const Color(0xFFF7F9FA),
  );

  static ThemeData darkTheme() => _theme(
    brightness: Brightness.dark,
    seed: const Color(0xFF8EC6D5),
    surface: const Color(0xFF151A1D),
  );

  static ThemeData _theme({
    required Brightness brightness,
    required Color seed,
    required Color surface,
  }) {
    final android = defaultTargetPlatform == TargetPlatform.android;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: android ? 'Roboto' : 'Segoe UI',
      fontFamilyFallback: android
          ? const ['Noto Sans CJK SC', 'Noto Sans SC', 'sans-serif']
          : const ['Microsoft YaHei UI', 'Arial'],
      scaffoldBackgroundColor: surface,
      visualDensity: VisualDensity.compact,
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        useIndicator: true,
        minWidth: 72,
        minExtendedWidth: 184,
        labelType: NavigationRailLabelType.all,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        height: 68,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMedium)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: 44,
        contentPadding: EdgeInsets.symmetric(horizontal: spaceSmd),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          iconSize: iconMedium,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(40, 36),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(40, 36),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
          ),
        ),
      ),
    );
  }
}
