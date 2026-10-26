import 'package:cycle/app.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/hardware_button_providers.dart';
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
      'Settings → the active bike\'s settings: a new wheel size reaches the '
      'speed sensor, the ride auto-starts at its speed, and switching bikes '
      'switches them', (tester) async {
    final sensors = FakeSensorService();
    final location = FakeLocationService();
    final db = AppDatabase(NativeDatabase.memory());
    final bikes = FakeBikeProfilesStore(const BikeProfilesState(
      profiles: [
        BikeProfile(id: 'road', name: 'Road', colorArgb: 0xFFFFA726),
        BikeProfile(
            id: 'mtb',
            name: 'MTB',
            colorArgb: 0xFF29B6F6,
            settings: BikeSettings(wheelCircumferenceMeters: 2.3)),
      ],
      activeId: 'road',
    ));
    addTearDown(sensors.dispose);
    addTearDown(location.dispose);
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(sensors),
      locationServiceProvider.overrideWithValue(location),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      appDatabaseProvider.overrideWithValue(db),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
      // The on-screen Start/Stop button is hidden by default (volume keys).
      settingsStoreProvider.overrideWithValue(
          FakeSettingsStore(const AppSettings(showStartStopButton: true))),
      bikeProfilesStoreProvider.overrideWithValue(bikes),
    ]);
    addTearDown(container.dispose);
    // As main() does: keeps the wheel size live while Settings covers the map.
    container.listen(sensorSettingsSyncProvider, (_, _) {});
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CycleApp(),
    ));
    await tester.pumpAndSettle();
    expect(sensors.wheelCircumference, closeTo(2.105, 1e-9));

    await tester.tap(find.byKey(const Key('openSettingsButton')));
    await tester.pumpAndSettle();
    final tile = find.byKey(const Key('activeBikeSettingsTile'));
    await tester.scrollUntilVisible(tile, 100);
    expect(find.text('Settings for Road'), findsOneWidget);
    await tapVisible(tester, tile);

    // The bike's own screen.
    expect(find.text('Active bike'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('wheelCircumferenceTile')));
    await tester.enterText(
        find.byKey(const Key('wheelCircumferenceField')), '2200');
    await tester.tap(find.byKey(const Key('wheelCircumferenceSave')));
    await tester.pumpAndSettle();
    expect(find.text('2200 mm — used for BLE speed sensors'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('autoStartSwitch')));
    await tapVisible(tester, find.byKey(const Key('autoStartSpeedTile')));
    await tester.enterText(find.byKey(const Key('autoStartSpeedField')), '12');
    await tester.tap(find.byKey(const Key('autoStartSpeedSave')));
    await tester.pumpAndSettle();
    expect(find.text('12 km/h'), findsOneWidget);
    expect(sensors.wheelCircumference, closeTo(2.2, 1e-9));

    // Back in Settings the summary shows the edits.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
        find.text('Wheel 2200 mm · auto-pause below 5 km/h · '
            'auto-start above 12 km/h'),
        findsOneWidget);

    // On the map, riding off starts a ride only above the bike's 12 km/h.
    await tester.pageBack();
    await tester.pumpAndSettle();
    final t0 = DateTime.now().toUtc();
    var s = 0;
    Future<void> roll(int seconds, double kmh) async {
      for (final end = s + seconds; s < end; s++) {
        location.emit(GeoSample(
          latitude: 43.73,
          longitude: 7.42 + s * 0.00005,
          time: t0.add(Duration(seconds: s)),
          speedMps: kmh / 3.6,
          accuracyMeters: 4,
        ));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    await roll(10, 10);
    expect(container.read(recordingProvider), isFalse);
    expect(find.text('Start'), findsOneWidget);
    await roll(7, 14);
    expect(container.read(recordingProvider), isTrue);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);

    // Make the MTB active from the bike list: its wheel applies.
    await tester.tap(find.byKey(const Key('openSettingsButton')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('bikeProfilesTile')));
    await tapVisible(tester, find.byKey(const Key('bikeProfileRow_mtb')));
    expect(sensors.wheelCircumference, closeTo(2.3, 1e-9));

    final saved = await bikes.load();
    final road = saved.profiles.firstWhere((p) => p.id == 'road');
    expect(
        road.settings,
        const BikeSettings(
            wheelCircumferenceMeters: 2.2,
            autoStartEnabled: true,
            autoStartSpeedKmh: 12));
    expect(saved.activeId, 'mtb');
  });
}
