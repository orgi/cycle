import 'package:flutter/material.dart';

import 'services/settings/app_settings.dart';

/// Builds the app [ThemeData] for the chosen [AppColorScheme].
///
/// * Dark / B&W keep a true-black background (OLED battery win on an always-on
///   handlebar display); B&W swaps the accent to white for a monochrome look.
/// * Light is a conventional bright scheme for daytime / preference.
ThemeData buildAppTheme(AppColorScheme scheme) {
  switch (scheme) {
    case AppColorScheme.light:
      return _light();
    case AppColorScheme.bw:
      return _oled(const Color(0xFFE0E0E0));
    case AppColorScheme.dark:
      return _oled(const Color(0xFF00E5FF));
  }
}

/// Kept for callers/tests that want the default dark theme directly.
ThemeData buildOledTheme() => buildAppTheme(AppColorScheme.dark);

/// True-black theme with a configurable accent (used by Dark and B&W).
ThemeData _oled(Color accent) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
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

ThemeData _light() {
  const accent = Color(0xFF1565C0); // blue
  final colorScheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.light,
  ).copyWith(primary: accent);
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF4F4F4),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFFAFAFA),
      foregroundColor: Color(0xFF202020),
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
  );
}

/// Accent colours for the map overlays (recorded track, followed route, the
/// rider's location dot and the ghost rider) per [AppColorScheme]. Argb ints,
/// as required by the mapsforge markers.
class MapAccents {
  const MapAccents({
    required this.track,
    required this.route,
    required this.me,
    required this.meStroke,
    required this.ghost,
    required this.onLightMap,
  });

  final int track;
  final int route;
  final int me;
  final int meStroke;
  final int ghost;

  /// Whether the map underneath is light (so text overlays need a light scrim).
  final bool onLightMap;

  static const _dark = MapAccents(
    track: 0xFFFF6D00, // orange
    route: 0xFF2979FF, // blue
    me: 0xFF00E5FF, // cyan
    meStroke: 0xFFFFFFFF,
    ghost: 0xFFB0BEC5,
    onLightMap: false,
  );

  static const _light = MapAccents(
    track: 0xFFE65100, // deep orange
    route: 0xFF1565C0, // dark blue
    me: 0xFF0D47A1,
    meStroke: 0xFFFFFFFF,
    ghost: 0xFF546E7A,
    onLightMap: true,
  );

  static const _bw = MapAccents(
    track: 0xFFFFFFFF, // white
    route: 0xFFBDBDBD, // light gray
    me: 0xFFFFFFFF,
    meStroke: 0xFF000000,
    ghost: 0xFF8A8A8A,
    onLightMap: false,
  );

  static MapAccents of(AppColorScheme scheme) {
    switch (scheme) {
      case AppColorScheme.light:
        return _light;
      case AppColorScheme.bw:
        return _bw;
      case AppColorScheme.dark:
        return _dark;
    }
  }
}
