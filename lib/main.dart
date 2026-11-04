import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/removed_logins.dart';
import 'features/dashboard/application/keep_screen_on_providers.dart';
import 'features/dashboard/application/ride_providers.dart';
import 'features/health/application/apple_health_providers.dart';
import 'features/map/application/map_providers.dart';
import 'features/routing/application/follow_route_providers.dart';
import 'features/sensors/application/sensor_power_gate.dart';
import 'features/settings/application/hardware_button_providers.dart';
import 'features/sync/application/sync_providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Handlebar use: lock to portrait for a stable, predictable layout.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // GPS is the top priority: start acquiring a fix the instant the app
  // launches, before the map/UI finish building, so a lock is ready as early
  // as possible. We own the container so we can warm the location stream up
  // here; keeping the subscription alive for the app's lifetime holds the one
  // continuous GPS stream open (see GeolocatorLocationService).
  final container = ProviderContainer();
  unawaited(container.read(locationServiceProvider).ensurePermission());
  container.listen(currentPositionProvider, (_, _) {}, fireImmediately: true);
  // Release BLE sensor links while backgrounded with no ride (the Bluetooth
  // counterpart of the GPS lifecycle gate). Owned here so it covers the whole
  // app lifetime, not one screen's.
  container.read(sensorPowerGateProvider);
  // The active bike's wheel size goes to the speed sensor the moment the bike
  // or its setting changes, whichever screen is open: a watch from the home
  // screen alone is paused by Riverpod while another screen covers it.
  container.listen(sensorSettingsSyncProvider, (_, _) {});
  // "Keep screen on without a ride": from launch, and a change in Settings
  // applies at once (never paused, unlike the home screen's watch).
  container.listen(keepScreenOnProvider, (_, _) {});

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CycleApp(),
    ),
  );

  // Follow again the route that was followed when the app last ran.
  unawaited(container.read(followRouteProvider.notifier).restore());

  // Ride sync + trash/backup housekeeping. After runApp and self-delayed
  // (SyncController.startupDelay), so it never competes with GPS/map startup.
  container.read(syncControllerProvider);

  // Apple Health gets the ride stopped last once it can't be continued any
  // more — also if that window ended while the app was closed.
  container.read(stoppedRideSettlerProvider);

  // Komoot and Strava upload were removed; delete logins older versions saved.
  unawaited(forgetRemovedLogins());
}
