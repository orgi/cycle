import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/settings/application/settings_providers.dart';
import 'features/map/presentation/manage_maps_screen.dart';
import 'features/map/presentation/map_screen.dart';
import 'features/sensors/presentation/sensors_screen.dart';
import 'features/tracks/presentation/track_detail_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/tracks/presentation/tracks_screen.dart';
import 'features/upload/presentation/upload_settings_screen.dart';

/// App-wide router. The home screen combines the map + live stats; the download
/// manager, sensors and rides are reachable from its app bar.
final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MapScreen(),
    ),
    GoRoute(
      path: '/maps',
      builder: (context, state) => const ManageMapsScreen(),
    ),
    GoRoute(
      path: '/sensors',
      builder: (context, state) => const SensorsScreen(),
    ),
    GoRoute(
      path: '/tracks',
      builder: (context, state) => const TracksScreen(),
    ),
    GoRoute(
      path: '/tracks/:id',
      builder: (context, state) => TrackDetailScreen(
        trackId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/upload-accounts',
      builder: (context, state) => const UploadSettingsScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class CycleApp extends ConsumerWidget {
  const CycleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ref.watch(settingsProvider.select((s) => s.colorScheme));
    final theme = buildAppTheme(scheme);
    return MaterialApp.router(
      title: 'Cycle',
      debugShowCheckedModeBanner: false,
      // `theme` always wins under ThemeMode.light; the scheme's ThemeData already
      // carries the right brightness (light vs true-black).
      theme: theme,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
    );
  }
}
