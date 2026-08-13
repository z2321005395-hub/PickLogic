import 'package:flutter/material.dart';

abstract final class PickLogicTokens {
  static const double radiusSmall = 10;
  static const double radiusMedium = 16;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
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
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Segoe UI',
      fontFamilyFallback: const ['Microsoft YaHei UI'],
      scaffoldBackgroundColor: surface,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMedium)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: 48,
        contentPadding: EdgeInsets.symmetric(horizontal: spaceMd),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(40, 40),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(40, 40),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
          ),
        ),
      ),
    );
  }
}
