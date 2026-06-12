import 'package:cycle/core/db/database.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/tracks/application/track_providers.dart';
import 'package:cycle/features/tracks/presentation/track_detail_screen.dart';
import 'package:cycle/features/tracks/presentation/tracks_screen.dart';
import 'package:cycle/features/tracks/presentation/widgets/route_preview.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(find.textContaining('12.00 km'), findsOneWidget);

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
        ],
        child: MaterialApp(home: TrackDetailScreen(trackId: id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12.00'), findsOneWidget); // distance km
    expect(find.text('0:30:00'), findsOneWidget); // duration
    expect(find.text('ROUTE'), findsOneWidget);
    expect(find.byType(RoutePreview), findsOneWidget);
    expect(find.text('ELEVATION'), findsOneWidget);
  });
}
