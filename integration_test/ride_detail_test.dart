import 'package:cycle/app.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/tracks/application/track_providers.dart';
import 'package:cycle/features/tracks/presentation/widgets/ride_map.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';
import 'package:mapsforge_flutter_core/model.dart';

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps until [finder] shows (the offline map loads in the background).
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  testWidgets(
      'ride details: stats, and the map with the elevation profile linked; '
      'the map pans without switching tabs and takes a style of its own',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final location = FakeLocationService();
    final sensors = FakeSensorService();
    addTearDown(db.close);
    addTearDown(location.dispose);
    addTearDown(sensors.dispose);

    // A ride across Monaco (the bundled demo map), climbing.
    final start = DateTime.utc(2026, 6, 1, 8);
    final id = await db.createTrack(start, name: 'Monaco loop');
    for (var i = 0; i < 120; i++) {
      await db.addPoint(TrackPointsCompanion.insert(
        trackId: id,
        time: start.add(Duration(seconds: i * 5)),
        latitude: 43.728 + i * 0.00015,
        longitude: 7.414 + i * 0.0001,
        altitude: Value(20.0 + i),
        speedMps: Value(4.0 + (i % 10)),
      ));
    }
    await db.finalizeTrack(id,
        endedAt: start.add(const Duration(minutes: 10)),
        distanceMeters: 3000,
        durationSeconds: 600,
        avgSpeedMps: 5,
        maxSpeedMps: 13);

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      locationServiceProvider.overrideWithValue(location),
      sensorServiceProvider.overrideWithValue(sensors),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
      settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CycleApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openTracksButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('trackTile_$id')));
    await tester.pumpAndSettle();

    // Stats first.
    expect(find.text('3.00'), findsOneWidget);
    expect(find.byType(RideMap), findsNothing);
    TabController tabs() =>
        DefaultTabController.of(tester.element(find.byType(TabBarView)));

    // The map tab: the real offline map, the elevation profile under it.
    await tester.tap(find.byKey(const Key('rideTabMap')));
    await tester.pumpAndSettle();
    await waitFor(tester, find.byType(MapsforgeView));
    expect(find.byKey(const Key('rideSpeedLegend')), findsOneWidget);
    expect(find.byKey(const Key('rideElevationChart')), findsOneWidget);
    RideMap rideMap() => tester.widget<RideMap>(find.byType(RideMap));

    // A point picked on the profile shows on the map.
    await tester.tapAt(
        tester.getCenter(find.byKey(const Key('rideElevationChart'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rideSelectionInfo')), findsOneWidget);
    expect(rideMap().selected, isNotNull);

    // A tap on the map right on a track point (the 30th) shows it on the
    // profile: find where that point is on screen.
    await tester.pump(const Duration(seconds: 1)); // the map has settled
    final model = container.read(rideMapProvider).value!.model;
    final pos = model.lastPosition!;
    final centerPx = pos.getCenter();
    final pointPx =
        pos.projection.latLonToPixel(const LatLong(43.728 + 29 * 0.00015, 7.414 + 29 * 0.0001));
    final mapCenter = tester.getCenter(find.byType(MapsforgeView));
    await tester.tapAt(mapCenter +
        Offset(pointPx.x - centerPx.x, pointPx.y - centerPx.y));
    await tester.pump(const Duration(milliseconds: 600)); // single, not double
    await tester.pumpAndSettle();
    final picked = rideMap().selected!;
    expect(picked.latitude, closeTo(43.728 + 29 * 0.00015, 0.0004));
    expect(picked.longitude, closeTo(7.414 + 29 * 0.0001, 0.0003));
    // No coordinates popup (mapsforge's default context menu).
    expect(find.textContaining(RegExp(r'^-?\d+\.\d+ / -?\d+\.\d+$')),
        findsNothing);

    // Dragging and pinching move the map, never the tabs.
    await tester.drag(find.byType(MapsforgeView), const Offset(-250, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(MapsforgeView), const Offset(250, 40));
    await tester.pumpAndSettle();
    expect(tabs().index, 1);
    expect(find.byType(MapsforgeView), findsOneWidget);
    await tester.tap(find.byKey(const Key('rideMapFit')));
    await tester.pumpAndSettle();

    // Its own style: Detailed, while the app stays Dark.
    await tester.tap(find.byKey(const Key('rideMapStyleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rideMapStyle_detailed')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).rideMapStyle,
        AppColorScheme.detailed);
    expect(container.read(settingsProvider).colorScheme, AppColorScheme.dark);
    await waitFor(tester, find.byType(MapsforgeView));
    await tester.pump(const Duration(seconds: 2)); // tiles in the new style
    expect(tester.takeException(), isNull);

    // Stats and back: the map is still there (kept, not reloaded).
    await tester.tap(find.byKey(const Key('rideTabStats')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rideTabMap')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MapsforgeView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
