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

  testWidgets('track detail shows stats, route and elevation', (tester) async {
    final (db, id) = await _seed();
    addTearDown(db.close);

    // Tall surface so the whole (scrolling) detail list is built, including the
    // elevation section near the bottom.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Pre-fetch and override the family providers so the data is present
    // synchronously (avoids a FutureProvider race with pumpAndSettle).
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

    expect(find.text('12.00'), findsOneWidget); // distance km
    expect(find.text('0:30:00'), findsOneWidget); // duration
    expect(find.textContaining('MAP'), findsOneWidget);
    expect(find.byType(RideMap), findsOneWidget);
    expect(find.textContaining('ELEVATION'), findsOneWidget);
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
