import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/map/presentation/manage_maps_screen.dart';
import 'features/map/presentation/map_screen.dart';

/// App-wide router. Dashboard is home; the map and its download manager are
/// reachable from there. Tracks/settings routes are added in later milestones.
final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/map',
      builder: (context, state) => const MapScreen(),
    ),
    GoRoute(
      path: '/maps',
      builder: (context, state) => const ManageMapsScreen(),
    ),
  ],
);

class CycleApp extends StatelessWidget {
  const CycleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Cycle',
      debugShowCheckedModeBanner: false,
      theme: buildOledTheme(),
      darkTheme: buildOledTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
