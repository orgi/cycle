import 'package:cycle/features/tracks/presentation/widgets/speed_color.dart';
import 'package:cycle/features/tracks/presentation/widgets/track_segments.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/tracks/application/track_providers.dart';
import 'package:cycle/features/tracks/presentation/track_detail_screen.dart';
import 'package:cycle/features/tracks/presentation/tracks_screen.dart';
import 'package:cycle/features/tracks/presentation/widgets/ride_map.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<(AppDatabase, int)> _seed() async {
  final db = AppDatabase(NativeDatabase.memory());
  final start = DateTime.utc(2026, 6, 1, 8);
  final id = await db.createTrack(start, name: 'Morning ride');
  await db.addPoint(TrackPointsCompanion.insert(
      trackId: id,
      time: start,
      latitude: 43.0,
      longitude: 7.0,
      altitude: const Value(100)));
  await db.addPoint(TrackPointsCompanion.insert(
      trackId: id,
      time: start.add(const Duration(seconds: 10)),
      latitude: 43.001,
      longitude: 7.001,
      altitude: const Value(110)));
  await db.finalizeTrack(id,
      endedAt: start.add(const Duration(minutes: 30)),
      distanceMeters: 12000,
      durationSeconds: 1800,
      avgSpeedMps: 6.0,
      maxSpeedMps: 10.0);
  return (db, id);
}

void main() {
  testWidgets('tracks list shows a recorded ride', (tester) async {
    final (db, id) = await _seed();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TracksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('trackTile_$id')), findsOneWidget);
    expect(find.text('Morning ride'), findsOneWidget);
    expect(find.textContaining('12.00 km'), findsWidgets);

    // Week/month/year summary cards above the list pick up the seeded ride.
    expect(find.byKey(const Key('summaryWeek')), findsOneWidget);
    expect(find.byKey(const Key('summaryMonth')), findsOneWidget);
    expect(find.byKey(const Key('summaryYear')), findsOneWidget);

    // Unmount, then close the db so drift's watch-stream timer is cleared before
    // the framework's end-of-test timer check.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  /// A ride north from 43°N: [n] points ~111 m apart, climbing 10 m each
  /// (null heights with [heights] false), 20 km/h, a point every 20 s.
  Future<(AppDatabase, int)> seedClimb(int n, {bool heights = true}) async {
    final db = AppDatabase(NativeDatabase.memory());
    final start = DateTime(2026, 6, 1, 8);
    final id = await db.createTrack(start);
    for (var i = 0; i < n; i++) {
      await db.addPoint(TrackPointsCompanion.insert(
        trackId: id,
        time: start.add(Duration(seconds: 20 * i)),
        latitude: 43.0 + i * 0.001,
        longitude: 7.0,
        altitude: Value(heights ? 100.0 + 10 * i : null),
        speedMps: Value(20 / 3.6),
      ));
    }
    await db.finalizeTrack(id,
        endedAt: start.add(Duration(seconds: 20 * n)),
        distanceMeters: 111.2 * (n - 1),
        durationSeconds: 20 * n,
        avgSpeedMps: 20 / 3.6,
        maxSpeedMps: 20 / 3.6);
    return (db, id);
  }

  Future<void> pumpDetail(WidgetTester tester, AppDatabase db, int id) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Pre-fetched, so the data is there synchronously.
    final track = await db.track(id);
    final points = await db.pointsFor(id);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          trackProvider(id).overrideWith((ref) => track),
          trackPointsProvider(id).overrideWith((ref) => points),
          // The real offline map can't load in a host widget test; error fast
          // so RideMap shows its placeholder instead of spawning an isolate.
          rideMapProvider.overrideWith((ref) async =>
              throw StateError('no offline map in widget test')),
        ],
        child: MaterialApp(home: TrackDetailScreen(trackId: id)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('track detail: stats, then the map with the elevation profile '
      'on one tab; no swiping between tabs', (tester) async {
    final (db, id) = await _seed();
    addTearDown(db.close);
    await pumpDetail(tester, db, id);

    // Stats first: the numbers, no map.
    expect(find.text('12.00'), findsOneWidget); // distance km
    expect(find.text('0:30:00'), findsOneWidget); // duration
    expect(find.byType(RideMap), findsNothing);
    expect(find.byKey(const Key('rideTabElevation')), findsNothing);

    // A sideways drag doesn't switch tabs (it would steal the map's pans).
    await tester.fling(find.text('12.00'), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();
    expect(find.text('12.00'), findsOneWidget);
    expect(find.byType(RideMap), findsNothing);

    // The map tab: the map, and the profile under it.
    await tester.tap(find.byKey(const Key('rideTabMap')));
    await tester.pumpAndSettle();
    expect(find.byType(RideMap), findsOneWidget);
    expect(find.byKey(const Key('rideElevationChart')), findsOneWidget);
    expect(find.text('Climb 0 m · lowest 100 m · highest 110 m'),
        findsOneWidget);
    // The profile is a small strip under the map: about a quarter of the
    // map's height.
    final mapHeight = tester.getSize(find.byType(RideMap)).height;
    final chartHeight =
        tester.getSize(find.byKey(const Key('rideElevationChart'))).height;
    expect(chartHeight, lessThan(mapHeight / 3.5));
    expect(chartHeight, greaterThan(mapHeight / 6));
  });

  testWidgets('a point picked on the profile shows on the map, one tapped on '
      'the map shows on the profile', (tester) async {
    final (db, id) = await seedClimb(11); // 0 … ~1.11 km, 100 … 200 m
    addTearDown(db.close);
    await pumpDetail(tester, db, id);
    await tester.tap(find.byKey(const Key('rideTabMap')));
    await tester.pumpAndSettle();
    final chart = find.byKey(const Key('rideElevationChart'));
    RideMap map() => tester.widget<RideMap>(find.byType(RideMap));
    String info() => tester
        .widget<Text>(find.byKey(const Key('rideSelectionInfo')))
        .data!;
    expect(map().selected, isNull);
    expect(find.byKey(const Key('rideElevationSelection')), findsNothing);

    // The profile has the map's speed colours (all 20 km/h here: one band),
    // over the whole chart, like the track on the map.
    final bar = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.single;
    final bands = RideSpeedTrack.of(await db.pointsFor(id)).bands;
    expect(bar.gradientArea, LineChartGradientArea.wholeChart);
    expect(bar.gradient!.colors.toSet(), {for (final b in bands) Color(b.argb)});
    expect(bar.gradient!.colors.toSet(), {Color(speedColorArgb(20))});

    // Tap the middle of the profile: the 6th point, half way.
    await tester.tapAt(tester.getCenter(chart));
    await tester.pumpAndSettle();
    expect(info(), '0.56 km · 150 m · 20 km/h · 08:01');
    expect(map().selected, (latitude: 43.005, longitude: 7.0));
    expect(find.byKey(const Key('rideElevationSelection')), findsOneWidget);

    // Drag to the end: it follows the finger.
    final rect = tester.getRect(chart);
    await tester.dragFrom(rect.center, Offset(rect.width / 2 - 1, 0));
    await tester.pumpAndSettle();
    expect(info(), startsWith('1.11 km · 200 m'));
    expect(map().selected, (latitude: 43.01, longitude: 7.0));

    // A tap on the map next to the 3rd point (1 m per pixel: within 30 m).
    map().onMapTap!(43.002, 7.0001, 1.0);
    await tester.pumpAndSettle();
    expect(info(), startsWith('0.22 km · 120 m'));
    expect(map().selected, (latitude: 43.002, longitude: 7.0));

    // Beside the track clears it; the summary is back.
    map().onMapTap!(43.002, 7.01, 1.0);
    await tester.pumpAndSettle();
    expect(map().selected, isNull);
    expect(find.byKey(const Key('rideSelectionInfo')), findsNothing);
    expect(find.byKey(const Key('elevationSummary')), findsOneWidget);
  });

  testWidgets('without heights the map has the tab to itself; a map tap still '
      'marks the point', (tester) async {
    final (db, id) = await seedClimb(5, heights: false);
    addTearDown(db.close);
    await pumpDetail(tester, db, id);
    await tester.tap(find.byKey(const Key('rideTabMap')));
    await tester.pumpAndSettle();
    expect(find.byType(RideMap), findsOneWidget);
    expect(find.byKey(const Key('rideElevationChart')), findsNothing);
    final map = tester.widget<RideMap>(find.byType(RideMap));
    map.onMapTap!(43.001, 7.0, 1.0);
    await tester.pumpAndSettle();
    expect(tester.widget<RideMap>(find.byType(RideMap)).selected,
        (latitude: 43.001, longitude: 7.0));
  });

  testWidgets(
      'ride detail: shows Unassigned, then assigns a bike via the picker',
      (tester) async {
    final (db, id) = await _seed();
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const seeded = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Cube', colorArgb: 1)],
      activeId: 'p1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bikeProfilesStoreProvider
              .overrideWithValue(FakeBikeProfilesStore(seeded)),
          rideMapProvider.overrideWith((ref) async =>
              throw StateError('no offline map in widget test')),
        ],
        child: MaterialApp(home: TrackDetailScreen(trackId: id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unassigned'), findsOneWidget);

    await tester.tap(find.byKey(const Key('trackBikeRow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bikeProfileOption_p1')));
    await tester.pumpAndSettle();

    expect(find.text('Cube'), findsOneWidget);
    final track = await db.track(id);
    expect(track!.bikeProfileId, 'p1');
  });

  testWidgets('no filter row with a single bike profile', (tester) async {
    final (db, _) = await _seed();
    const oneProfile = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Bike 1', colorArgb: 1)],
      activeId: 'p1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bikeProfilesStoreProvider
              .overrideWithValue(FakeBikeProfilesStore(oneProfile)),
        ],
        child: const MaterialApp(home: TracksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bikeFilterAll')), findsNothing);

    // Unmount, then close the db so drift's watch-stream timer is cleared
    // before the framework's end-of-test timer check.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets('filters rides + summary by bike, with a per-row colour dot',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    const road = BikeProfile(id: 'road', name: 'Road', colorArgb: 0xFF112233);
    const gravel =
        BikeProfile(id: 'gravel', name: 'Gravel', colorArgb: 0xFF445566);

    Future<void> addRide(String name, String bikeProfileId, double km) async {
      final start = DateTime.utc(2026, 6, 1, 8);
      final id = await db.createTrack(start,
          name: name, bikeProfileId: bikeProfileId);
      await db.finalizeTrack(id,
          endedAt: start.add(const Duration(minutes: 30)),
          distanceMeters: km * 1000,
          durationSeconds: 1800,
          avgSpeedMps: 6.0,
          maxSpeedMps: 10.0);
    }

    await addRide('Road ride', 'road', 20);
    await addRide('Gravel ride', 'gravel', 15);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(
            const BikeProfilesState(profiles: [road, gravel], activeId: 'road'),
          )),
        ],
        child: const MaterialApp(home: TracksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Both rides visible under "All"; each row shows its bike's colour dot.
    expect(find.text('Road ride'), findsOneWidget);
    expect(find.text('Gravel ride'), findsOneWidget);
    expect(find.byKey(const Key('trackBikeDot_1')), findsOneWidget);
    expect(find.byKey(const Key('trackBikeDot_2')), findsOneWidget);

    // Switch the filter to "Gravel": only that ride + its summary remain.
    await tester.tap(find.byKey(const Key('bikeFilter_gravel')));
    await tester.pumpAndSettle();

    expect(find.text('Gravel ride'), findsOneWidget);
    expect(find.text('Road ride'), findsNothing);
    expect(find.textContaining('15.00 km'), findsWidgets); // summary picks up only this ride

    // Back to "All" shows both again.
    await tester.tap(find.byKey(const Key('bikeFilterAll')));
    await tester.pumpAndSettle();
    expect(find.text('Road ride'), findsOneWidget);
    expect(find.text('Gravel ride'), findsOneWidget);

    // Unmount, then close the db so drift's watch-stream timer is cleared
    // before the framework's end-of-test timer check.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });

  testWidgets('a bike with no rides shows an empty message when filtered',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    const road = BikeProfile(id: 'road', name: 'Road', colorArgb: 1);
    const gravel = BikeProfile(id: 'gravel', name: 'Gravel', colorArgb: 2);
    final start = DateTime.utc(2026, 6, 1, 8);
    final id = await db.createTrack(start, name: 'Road ride', bikeProfileId: 'road');
    await db.finalizeTrack(id,
        endedAt: start.add(const Duration(minutes: 30)),
        distanceMeters: 20000,
        durationSeconds: 1800,
        avgSpeedMps: 6.0,
        maxSpeedMps: 10.0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(
            const BikeProfilesState(profiles: [road, gravel], activeId: 'road'),
          )),
        ],
        child: const MaterialApp(home: TracksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bikeFilter_gravel')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No rides for this bike yet'), findsOneWidget);

    // Unmount, then close the db so drift's watch-stream timer is cleared
    // before the framework's end-of-test timer check.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await db.close();
  });
}
