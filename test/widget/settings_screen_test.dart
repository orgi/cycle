import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/apple_health_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/health/application/apple_health_providers.dart';
import 'package:cycle/features/places/application/ride_places_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/settings/presentation/settings_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('shows current settings and changes units', (tester) async {
    final store = FakeSettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to imperial.
    await tester.tap(find.byKey(const Key('unitsImperial')));
    await tester.pumpAndSettle();
    expect((await store.load()).units, UnitSystem.imperial);
  });

  testWidgets('toggles the volume-keys switch', (tester) async {
    final store = FakeSettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Default is enabled; tapping disables it. Scroll it into view first
    // (the Appearance section sits above it).
    await tester.scrollUntilVisible(
      find.byKey(const Key('hardwareButtonsSwitch')),
      200,
    );
    await tester.tap(find.byKey(const Key('hardwareButtonsSwitch')));
    await tester.pumpAndSettle();
    expect((await store.load()).hardwareButtonsEnabled, isFalse);
  });

  Future<void> pumpSettings(WidgetTester tester, FakeSettingsStore store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Apple Health switch', () {
    Future<_FakeHealth> pumpIos(WidgetTester tester, {required bool allow}) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final health = _FakeHealth(allow);
      final store = FakeSettingsStore();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
          appleHealthServiceProvider.overrideWithValue(health),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      final sw = find.byKey(const Key('appleHealthSwitch'));
      await tester.scrollUntilVisible(sw, 300);
      await tester.ensureVisible(sw); // it's tall; make sure all of it is in view
      await tester.pumpAndSettle();
      await tester.tap(sw);
      await tester.pumpAndSettle();
      health.store = store;
      return health;
    }

    testWidgets('turns on once iOS grants access', (tester) async {
      final health = await pumpIos(tester, allow: true);
      expect(health.asked, 1);
      expect((await health.store!.load()).saveToAppleHealth, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('stays off and explains when access is refused',
        (tester) async {
      final health = await pumpIos(tester, allow: false);
      expect((await health.store!.load()).saveToAppleHealth, isFalse);
      expect(find.textContaining('Apple Health access was not granted'),
          findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('is not offered on Android', (tester) async {
      await pumpSettings(tester, FakeSettingsStore());
      expect(find.byKey(const Key('appleHealthSwitch')), findsNothing);
    });
  });

  testWidgets('About shows the app name Radl and the version', (tester) async {
    await pumpSettings(tester, FakeSettingsStore());
    final about = find.byKey(const Key('appVersionTile'));
    await tester.scrollUntilVisible(about, 300);
    expect(find.descendant(of: about, matching: find.text('Radl')),
        findsOneWidget);
    expect(find.descendant(of: about, matching: find.textContaining('Version')),
        findsOneWidget);
     final osm = find.byKey(const Key('osmCreditTile'));
    await tester.scrollUntilVisible(osm, 300);
    expect(
        find.descendant(
            of: osm, matching: find.textContaining('© OpenStreetMap contributors')),
        findsOneWidget);
  });

  testWidgets('iOS shows the hand-over-screen and Start/Stop switches, no volume keys',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final store = FakeSettingsStore();
    await pumpSettings(tester, store);

    await tester.scrollUntilVisible(
      find.byKey(const Key('vibrateStartStopSwitch')),
      200,
    );
    expect(find.byKey(const Key('hardwareButtonsSwitch')), findsNothing);
    expect(find.byKey(const Key('showStartStopSwitch')), findsOneWidget);

    await tester.tap(find.byKey(const Key('proximityHoldSwitch')));
    await tester.pumpAndSettle();
    expect((await store.load()).proximityHoldEnabled, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android has no hand-over-screen switch', (tester) async {
    await pumpSettings(tester, FakeSettingsStore());

    await tester.scrollUntilVisible(
      find.byKey(const Key('vibrateStartStopSwitch')),
      200,
    );
    expect(find.byKey(const Key('proximityHoldSwitch')), findsNothing);
  });

  testWidgets(
      'wheel size, auto-pause and auto-start are per bike, not app-wide',
      (tester) async {
    // Tall viewport so the whole settings list fits on screen.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(
            oneBike(const BikeSettings(
                wheelCircumferenceMeters: 2.2,
                autoPauseSpeedKmh: 3.5,
                autoStartEnabled: true,
                autoStartSpeedKmh: 12)))),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    for (final key in [
      'wheelCircumferenceTile',
      'autoPauseSwitch',
      'autoPauseSpeedTile',
      'autoStartSwitch',
      'autoStartSpeedTile',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    final tile = find.byKey(const Key('activeBikeSettingsTile'));
    expect(find.descendant(of: tile, matching: find.text('Settings for Bike')),
        findsOneWidget);
    expect(
        find.descendant(
            of: tile,
            matching: find.text(
                'Wheel 2200 mm · auto-pause below 3.5 km/h · '
                'auto-start above 12 km/h')),
        findsOneWidget);
  });

  testWidgets('an upgraded bike shows the app-wide values it had before',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(FakeSettingsStore(
            AppSettings.fromJson(const {
          'wheel_circumference_m': 2.3,
          'auto_pause': false,
          'auto_pause_kmh': 5.0,
          'auto_start': false,
        }))),
        bikeProfilesStoreProvider
            .overrideWithValue(FakeBikeProfilesStore(oneBike())),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(
        find.text('Wheel 2300 mm · auto-pause off · auto-start off'),
        findsOneWidget);
  });

  testWidgets('recalculates ride distances after confirmation', (tester) async {
    final store = FakeSettingsStore();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.createTrack(DateTime(2026, 1, 1));
    await db.addPoint(
      TrackPointsCompanion.insert(
        trackId: id,
        time: DateTime(2026, 1, 1, 0, 0, 0),
        latitude: 0,
        longitude: 0,
      ),
    );
    await db.addPoint(
      TrackPointsCompanion.insert(
        trackId: id,
        time: DateTime(2026, 1, 1, 0, 0, 10),
        latitude: 0,
        longitude: 0.001,
      ),
    );
    await db.finalizeTrack(
      id,
      endedAt: DateTime(2026, 1, 1, 0, 0, 10),
      distanceMeters: 9999,
      durationSeconds: 10,
      avgSpeedMps: 1,
      maxSpeedMps: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('recalculateDistancesTile')),
      200,
    );
    await tester.ensureVisible(find.byKey(const Key('recalculateDistancesTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recalculateDistancesTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recalculateDistancesConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('Recalculated 1 ride'), findsOneWidget);
    final track = await db.track(id);
    expect(track!.distanceMeters, lessThan(200));
  });

  testWidgets('removes duplicate rides after confirmation', (tester) async {
    final store = FakeSettingsStore();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final startedAt = DateTime(2026, 1, 1);
    final kept = await db.createTrack(startedAt);
    await db.createTrack(startedAt); // duplicate, same start time

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('removeDuplicatesTile')),
      200,
    );
    // Fully on screen, not just peeking in at the bottom edge (where a tap
    // misses).
    await tester.ensureVisible(find.byKey(const Key('removeDuplicatesTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('removeDuplicatesTile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('removeDuplicatesConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('Removed 1 duplicate ride'), findsOneWidget);
    final remaining = await db.allTracks();
    expect(remaining.map((t) => t.id), [kept]);
  });

  testWidgets('bike profiles tile summarises the active profile', (tester) async {
    final store = FakeSettingsStore();
    const seeded = BikeProfilesState(
      profiles: [BikeProfile(id: 'p1', name: 'Gravel bike', colorArgb: 1)],
      activeId: 'p1',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          bikeProfilesStoreProvider
              .overrideWithValue(FakeBikeProfilesStore(seeded)),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('bikeProfilesTile')),
      200,
    );
    final tile = find.byKey(const Key('bikeProfilesTile'));
    expect(find.descendant(of: tile, matching: find.text('1 bike • active: Gravel bike')),
        findsOneWidget);
  });

  testWidgets('keep screen on and continue a ride are picked from a list',
      (tester) async {
    final store = FakeSettingsStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
          ridePlacesStoreProvider.overrideWithValue(FakeRidePlacesStore()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('placesTile')), 200);
    expect(find.textContaining('Start a ride by leaving home'), findsOneWidget);

    final keepOn = find.byKey(const Key('keepScreenOnTile'));
    // The tile below it: built, but offstage until scrolled to.
    await tester.ensureVisible(
        find.byKey(const Key('keepScreenOnTile'), skipOffstage: false));
    await tester.pumpAndSettle();
    expect(find.text('Off: only while a ride records'), findsOneWidget);
    await tester.tap(keepOn);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('keepScreenOn_15')));
    await tester.pumpAndSettle();
    expect((await store.load()).keepScreenOnMinutes, 15);
    expect(find.textContaining("hasn't moved for 15 min"), findsOneWidget);

    final resume = find.byKey(const Key('continueRideTile'));
    expect(find.textContaining('within 30 min'), findsOneWidget);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continueRide_0')));
    await tester.pumpAndSettle();
    expect((await store.load()).continueRideWithinMinutes, 0);
    expect(find.textContaining('always a new ride'), findsOneWidget);

  });
}

class _FakeHealth implements AppleHealthService {
  _FakeHealth(this.allow);
  final bool allow;
  int asked = 0;
  FakeSettingsStore? store;

  @override
  Future<bool> requestAccess() async {
    asked++;
    return allow;
  }

  @override
  Future<void> saveRide(HealthRide ride) async {}
}
