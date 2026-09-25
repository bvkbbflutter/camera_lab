import 'package:flutter/material.dart';

/// Material 3 theme for Camera Lab.
class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FED));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
          elevation: 0),
      cardTheme: const CardTheme(elevation: 0, margin: EdgeInsets.zero),
      inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(), isDense: true),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6FED), brightness: Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
          elevation: 0),
      cardTheme: const CardTheme(elevation: 0, margin: EdgeInsets.zero),
      inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(), isDense: true),
    );
  }
}

/// Small status colors used across the metadata comparison / verification UI.
class StatusColors {
  static const Color preserved = Color(0xFF2E7D32);
  static const Color changed = Color(0xFFF9A825);
  static const Color removed = Color(0xFF9E9E9E);
  static const Color unsupported = Color(0xFFC62828);
}
