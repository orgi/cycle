import 'package:cycle/app.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/models/home_layout.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder tile(String area, int row, int i) =>
      find.byKey(Key('homeTile_${area}_${row}_$i'));

  Future<void> choose(WidgetTester tester, String key) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'edit the home screen on the map: CLIMB instead of MAX, TIME removed, '
      'the ride\'s elevation profile added — then a climbing ride fills them',
      (tester) async {
    final location = FakeLocationService();
    final sensors = FakeSensorService();
    final db = AppDatabase(NativeDatabase.memory());
    final bikes = FakeBikeProfilesStore(oneBike());
    addTearDown(location.dispose);
    addTearDown(sensors.dispose);
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(location),
        sensorServiceProvider.overrideWithValue(sensors),
        screenWakeServiceProvider
            .overrideWithValue(RecordingScreenWakeService()),
        appDatabaseProvider.overrideWithValue(db),
        recordingForegroundServiceProvider
            .overrideWithValue(const NoopRecordingForegroundService()),
        // The on-screen Start/Stop button is hidden by default (volume keys).
        settingsStoreProvider.overrideWithValue(
            FakeSettingsStore(const AppSettings(showStartStopButton: true))),
        bikeProfilesStoreProvider.overrideWithValue(bikes),
      ],
      child: const CycleApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('MAX'), findsOneWidget);

    // Long-press a tile: the app bar turns into the editor's.
    await tester.longPress(tile('top', 0, 0));
    await tester.pumpAndSettle();
    expect(find.text('Layout for Bike'), findsOneWidget);
    expect(find.byKey(const Key('openSettingsButton')), findsNothing);

    // MAX → CLIMB.
    await tester.tap(tile('bottom', 1, 2));
    await tester.pumpAndSettle();
    await choose(tester, 'homeTileOption_climb');
    expect(find.text('CLIMB'), findsOneWidget);

    // TIME onto the bin.
    final g = await tester.startGesture(tester.getCenter(tile('top', 0, 1)));
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    await g.moveTo(tester.getCenter(find.byKey(const Key('homeBin'))));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('TIME'), findsNothing);

    // A row with the ride's profile below DIST/AVG/CLIMB.
    await tester.tap(find.byKey(const Key('homeNewRow_bottom_2')));
    await tester.pumpAndSettle();
    await choose(tester, 'homeTileOption_ride_profile');

    await tester.tap(find.byKey(const Key('homeEditDone')));
    await tester.pumpAndSettle();
    expect(find.text('Radl'), findsOneWidget); // the normal app bar again
    expect(find.text('Starts with the ride'), findsOneWidget);
    expect(find.text('MAX'), findsNothing);
    final saved = (await bikes.load()).profiles.single.settings!.homeLayout;
    expect(saved.top, [
      [HomeTile.speed]
    ]);
    expect(saved.bottom.skip(1), [
      [HomeTile.distance, HomeTile.avgSpeed, HomeTile.climb],
      [HomeTile.rideProfile],
    ]);

    // Ride 60 m up a hill.
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();
    final t0 = DateTime.now().toUtc();
    for (var s = 0; s < 70; s++) {
      location.emit(GeoSample(
        latitude: 43.73 + s * 0.00005,
        longitude: 7.42,
        time: t0.add(Duration(seconds: s)),
        speedMps: 5,
        altitudeMeters: 100 + (s < 60 ? s : 60).toDouble(),
        accuracyMeters: 4,
      ));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.text('60'), findsOneWidget); // CLIMB (smoothed, all in)
    expect(find.text('↑ 60 m'), findsOneWidget); // the profile's caption
    expect(find.text('Starts with the ride'), findsNothing);

    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();
  });
}
