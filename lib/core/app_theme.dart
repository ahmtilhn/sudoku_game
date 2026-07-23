import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light({required bool highContrast}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E6B63),
      brightness: Brightness.light,
      contrastLevel: highContrast ? 1 : 0,
    );
    return _build(scheme);
  }

  static ThemeData dark({required bool highContrast}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF67C6B7),
      brightness: Brightness.dark,
      contrastLevel: highContrast ? 1 : 0,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(52, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
