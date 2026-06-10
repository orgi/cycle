import 'package:flutter/material.dart';

/// True-black dark theme. On OLED panels black pixels are switched off, which
/// is the single biggest battery win for an always-on handlebar display.
ThemeData buildOledTheme() {
  const seed = Color(0xFF00E5FF); // cyan accent, high contrast on black
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  ).copyWith(
    surface: Colors.black,
    onSurface: Colors.white,
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.black,
    canvasColor: Colors.black,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFF0A0A0A),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
  );
}
