import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/hardware_button_service.dart';
import 'package:cycle/core/services/haptics_service.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/auto_start_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/hardware_button_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Every way a ride can start/stop confirms it by vibration: 1 pulse = started,
/// 2 = stopped, 3 = bike switched — whatever the trigger.
void main() {
  late ProviderContainer container;
  late RecordingHapticsService haptics;
  late FakeHardwareButtonService buttons;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late AppDatabase db;

  ProviderContainer build({
    AppSettings settings = const AppSettings(),
    BikeProfilesState bikes = BikeProfilesState.empty,
  }) {
    haptics = RecordingHapticsService();
    buttons = FakeHardwareButtonService();
    location = FakeLocationService();
    sensors = FakeSensorService();
    db = AppDatabase(NativeDatabase.memory());
    final c = ProviderContainer(overrides: [
      hapticsServiceProvider.overrideWithValue(haptics),
      hardwareButtonServiceProvider.overrideWithValue(buttons),
      settingsStoreProvider.overrideWithValue(FakeSettingsStore(settings)),
      locationServiceProvider.overrideWithValue(location),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      sensorServiceProvider.overrideWithValue(sensors),
      appDatabaseProvider.overrideWithValue(db),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikes)),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
      proximityHoldDurationProvider
          .overrideWithValue(const Duration(milliseconds: 50)),
    ]);
    c.listen(recordingProvider, (_, _) {});
    c.listen(bikeProfilesProvider, (_, _) {});
    c.listen(hardwareButtonControllerProvider, (_, _) {});
    c.listen(autoStartControllerProvider, (_, _) {});
    return c;
  }

  tearDown(() async {
    container.dispose();
    await buttons.dispose();
    await location.dispose();
    await sensors.dispose();
    await db.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('start = 1 pulse, stop = 2, felt once per real transition', () async {
    container = build();
    await settle();
    final rec = container.read(recordingProvider.notifier);

    await rec.start();
    await rec.start(); // already recording: no second buzz
    await rec.stop();
    await rec.stop(); // already stopped: nothing
    expect(haptics.felt, [RideFeedback.started, RideFeedback.stopped]);
    expect(RideFeedback.started.pulses, 1);
    expect(RideFeedback.stopped.pulses, 2);
  });

  test('volume keys: start, bike switch (3 pulses), stop', () async {
    const p1 = BikeProfile(id: 'p1', name: 'Road', colorArgb: 1);
    const p2 = BikeProfile(id: 'p2', name: 'Gravel', colorArgb: 2);
    container = build(
        bikes: const BikeProfilesState(profiles: [p1, p2], activeId: 'p1'));
    await settle();

    buttons.press(HardwareButton.volumeUp);
    await settle();
    buttons.press(HardwareButton.volumeUp);
    await settle();
    buttons.press(HardwareButton.volumeDown);
    await settle();
    expect(haptics.felt, [
      RideFeedback.started,
      RideFeedback.bikeProfileChanged,
      RideFeedback.stopped,
    ]);
    expect(RideFeedback.bikeProfileChanged.pulses, 3);
  });

  test('hand over screen: the hold is confirmed when it registers', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    container = build(settings: const AppSettings(proximityHoldEnabled: true));
    await settle();

    buttons.cover(true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // Felt while the hand is still there — the cue to take it away.
    expect(haptics.felt, [RideFeedback.started]);
    buttons.cover(false);
    await settle();
    debugDefaultTargetPlatformOverride = null;
  });

  test('auto-start is confirmed too', () async {
    container = build(settings: const AppSettings(autoStartEnabled: true));
    await settle();
    final t0 = DateTime.utc(2026, 10, 8, 9);
    for (var s = 0; s <= 6; s++) {
      location.emit(GeoSample(
        latitude: 47,
        longitude: 11,
        time: t0.add(Duration(seconds: s)),
        speedMps: 20 / 3.6,
        accuracyMeters: 4,
      ));
    }
    await settle();
    expect(haptics.felt, [RideFeedback.started]);
  });

  test('switched off in settings: no vibration', () async {
    container = build(settings: const AppSettings(vibrateOnStartStop: false));
    await settle();
    final rec = container.read(recordingProvider.notifier);
    await rec.start();
    await rec.stop();
    expect(haptics.felt, isEmpty);
  });

  test('on by default, and survives a settings round-trip', () {
    expect(const AppSettings().vibrateOnStartStop, isTrue);
    expect(AppSettings.fromJson(const {}).vibrateOnStartStop, isTrue);
    const off = AppSettings(vibrateOnStartStop: false);
    expect(AppSettings.fromJson(off.toJson()), off);
  });
}
