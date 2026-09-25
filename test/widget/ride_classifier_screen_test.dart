import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/tracks/presentation/ride_classifier_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<int> _seedRide(
  AppDatabase db, {
  required DateTime startedAt,
  String name = 'Ride',
  String? bikeProfileId,
  double distanceMeters = 10000,
  double avgSpeedMps = 5,
  bool withCadence = false,
}) async {
  final id = await db.createTrack(startedAt,
      name: name, bikeProfileId: bikeProfileId);
  await db.addPoint(TrackPointsCompanion.insert(
    trackId: id,
    time: startedAt,
    latitude: 0,
    longitude: 0,
    cadenceRpm: Value(withCadence ? 80 : null),
  ));
  await db.finalizeTrack(id,
      endedAt: startedAt,
      distanceMeters: distanceMeters,
      durationSeconds: 1,
      avgSpeedMps: avgSpeedMps,
      maxSpeedMps: avgSpeedMps);
  return id;
}

/// The filter form is tall (switch + 3 checkboxes + 3 min/max rows + date
/// range) — a taller-than-default viewport keeps "Find rides" and the results
/// on-screen without needing a scroll in every test (mirrors
/// settings_screen_test.dart's wheel-circumference test).
Future<void> _pumpScreen(WidgetTester tester, AppDatabase db,
    BikeProfilesState profiles) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        bikeProfilesStoreProvider
            .overrideWithValue(FakeBikeProfilesStore(profiles)),
      ],
      child: const MaterialApp(home: RideClassifierScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const oneProfile = BikeProfilesState(
    profiles: [BikeProfile(id: 'p1', name: 'Cube', colorArgb: 1)],
    activeId: 'p1',
  );

  testWidgets('finds only unassigned rides by default', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedRide(db,
        startedAt: DateTime.utc(2026, 1, 1), name: 'Unassigned ride');
    await _seedRide(db,
        startedAt: DateTime.utc(2026, 1, 2),
        name: 'Assigned ride',
        bikeProfileId: 'p1');

    await _pumpScreen(tester, db, oneProfile);

    await tester.tap(find.byKey(const Key('findRidesButton')));
    await tester.pumpAndSettle();

    expect(find.text('1 matching ride'), findsOneWidget);
    expect(find.text('Unassigned ride'), findsOneWidget);
    expect(find.text('Assigned ride'), findsNothing);
  });

  testWidgets('cadence checkbox narrows results', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedRide(db,
        startedAt: DateTime.utc(2026, 1, 1),
        name: 'With cadence',
        withCadence: true);
    await _seedRide(db,
        startedAt: DateTime.utc(2026, 1, 2), name: 'Without cadence');

    await _pumpScreen(tester, db, oneProfile);

    await tester.tap(find.byKey(const Key('requireCadenceCheckbox')));
    await tester.tap(find.byKey(const Key('findRidesButton')));
    await tester.pumpAndSettle();

    expect(find.text('With cadence'), findsOneWidget);
    expect(find.text('Without cadence'), findsNothing);
  });

  testWidgets('distance min filters out short rides', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedRide(db,
        startedAt: DateTime.utc(2026, 1, 1),
        name: 'Short',
        distanceMeters: 2000);
    await _seedRide(db,
        startedAt: DateTime.utc(2026, 1, 2),
        name: 'Long',
        distanceMeters: 50000);

    await _pumpScreen(tester, db, oneProfile);

    await tester.enterText(find.byKey(const Key('minDistanceField')), '10');
    await tester.tap(find.byKey(const Key('findRidesButton')));
    await tester.pumpAndSettle();

    expect(find.text('Long'), findsOneWidget);
    expect(find.text('Short'), findsNothing);
  });

  testWidgets('finds, picks a bike, assigns, and clears the results',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id =
        await _seedRide(db, startedAt: DateTime.utc(2026, 1, 1), name: 'Old ride');

    await _pumpScreen(tester, db, oneProfile);

    await tester.tap(find.byKey(const Key('findRidesButton')));
    await tester.pumpAndSettle();
    expect(find.text('1 matching ride'), findsOneWidget);

    await tester.tap(find.byKey(const Key('classifyAssignDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cube').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('classifyAssignButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('classifyAssignConfirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Assigned 1 ride to "Cube"'), findsOneWidget);
    expect((await db.track(id))!.bikeProfileId, 'p1');
    // Results are cleared after a successful assignment.
    expect(find.textContaining('matching ride'), findsNothing);
  });
}
