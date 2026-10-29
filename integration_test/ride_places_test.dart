import 'dart:math' as math;

import 'package:cycle/app.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/screen_wake_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/keep_screen_on_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/places/application/ride_places_providers.dart';
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

  // The emulator screen is small (320×640): bring a widget fully on screen
  // before tapping it, not just to the edge where scrollUntilVisible stops.
  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 100);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'set up home as a place in Settings, keep the screen on; leaving home '
      'starts a ride, coming back stops it, starting again by hand continues '
      'it — and "New ride" makes it a new one', (tester) async {
    final location = FakeLocationService();
    final sensors = FakeSensorService();
    final db = AppDatabase(NativeDatabase.memory());
    final wake = RecordingScreenWakeService();
    final places = FakeRidePlacesStore();
    addTearDown(location.dispose);
    addTearDown(sensors.dispose);
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      locationServiceProvider.overrideWithValue(location),
      sensorServiceProvider.overrideWithValue(sensors),
      screenWakeServiceProvider.overrideWithValue(wake),
      appDatabaseProvider.overrideWithValue(db),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
      // The on-screen Start/Stop button is hidden by default (volume keys).
      settingsStoreProvider.overrideWithValue(
          FakeSettingsStore(const AppSettings(showStartStopButton: true))),
      bikeProfilesStoreProvider
          .overrideWithValue(FakeBikeProfilesStore(oneBike())),
      ridePlacesStoreProvider.overrideWithValue(places),
      placeStopAfterProvider.overrideWithValue(const Duration(seconds: 2)),
    ]);
    addTearDown(container.dispose);
    // As main() does.
    container.listen(keepScreenOnProvider, (_, _) {});
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CycleApp(),
    ));
    await tester.pumpAndSettle();

    /// A fix [east] (and [north]) metres from home (47 N 11 E).
    Future<void> at(double east, {double north = 0}) async {
      location.emit(GeoSample(
        latitude: 47 + north / 111195,
        longitude: 11 + east / (111195 * math.cos(47 * math.pi / 180)),
        time: DateTime.now(),
        speedMps: 5,
        accuracyMeters: 4,
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    bool recording() => container.read(recordingProvider);
    await at(0);

    // Settings: home as a place, and keep the screen on without a ride
    // (the tile below it).
    await tester.tap(find.byKey(const Key('openSettingsButton')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('placesTile')));
    await at(0);
    await tester.tap(find.byKey(const Key('addPlaceButton')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Home'), findsOneWidget);
    await tester.tap(find.byKey(const Key('placeSave')));
    await tester.pumpAndSettle();
    expect(find.textContaining("You're here"), findsOneWidget);
    expect(places.places.single.name, 'Home');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(wake.holds(ScreenWakeService.ownerKeepOn), isFalse);
    // Right below the places tile: built but offstage, which
    // scrollUntilVisible's finder never sees.
    final keepOn =
        find.byKey(const Key('keepScreenOnTile'), skipOffstage: false);
    await tester.ensureVisible(keepOn);
    await tester.pumpAndSettle();
    await tester.tap(keepOn);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('keepScreenOn_15')));
    await tester.pumpAndSettle();
    expect(wake.holds(ScreenWakeService.ownerKeepOn), isTrue);
    expect(recording(), isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Waiting at home, then riding off: the ride starts at the edge.
    await at(5);
    await at(30);
    expect(recording(), isFalse);
    await at(90);
    await tester.pumpAndSettle();
    expect(recording(), isTrue);
    expect(find.text('Ride started: you left Home'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    // A loop — out east, back along a street 300 m north — then home
    // again: stopped after the stay.
    for (var m = 150.0; m <= 1500; m += 150) {
      await at(m);
    }
    await at(1500, north: 150);
    for (var m = 1500.0; m >= 0; m -= 150) {
      await at(m, north: 300);
    }
    await at(0, north: 150);
    await at(0, north: 20);
    expect(recording(), isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(recording(), isFalse);
    expect(find.text('Ride stopped: you arrived at Home'), findsOneWidget);
    final rides = await db.allTracks();
    expect(rides, hasLength(1));
    expect(rides.single.endedAt, isNotNull);
    expect(rides.single.distanceMeters, greaterThan(2000));
    // The screen stays on without a ride.
    expect(wake.holds(ScreenWakeService.ownerKeepOn), isTrue);

    // Starting again by hand, still at home: the ride continues.
    await at(10);
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();
    expect(recording(), isTrue);
    expect(find.textContaining('Continued the ride stopped at'),
        findsOneWidget);
    expect(await db.allTracks(), hasLength(1));
    expect(container.read(recordingProvider.notifier).currentTrackId,
        rides.single.id);

    // …unless the rider says it's a new ride.
    await tester.tap(find.byKey(const Key('rideNoticeNewRide')));
    await tester.pumpAndSettle();
    expect(recording(), isTrue);
    final now = await db.allTracks();
    expect(now, hasLength(2));
    expect(now.firstWhere((t) => t.id == rides.single.id).endedAt,
        rides.single.endedAt);

    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();
    expect(recording(), isFalse);
  });
}
