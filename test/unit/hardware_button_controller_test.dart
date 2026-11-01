import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/hardware_button_service.dart';
import 'package:cycle/core/services/haptics_service.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/hardware_button_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeHardwareButtonService buttons;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late AppDatabase db;
  late RecordingHapticsService haptics;

  ProviderContainer build({
    bool enabled = true,
    bool proximityHold = false,
    bool vibrate = true,
    BikeProfilesState? bikeProfiles,
  }) {
    buttons = FakeHardwareButtonService();
    haptics = RecordingHapticsService();
    location = FakeLocationService();
    sensors = FakeSensorService();
    db = AppDatabase(NativeDatabase.memory());
    return ProviderContainer(overrides: [
      hardwareButtonServiceProvider.overrideWithValue(buttons),
      settingsStoreProvider.overrideWithValue(
          FakeSettingsStore(AppSettings(
              hardwareButtonsEnabled: enabled,
              proximityHoldEnabled: proximityHold,
              vibrateOnStartStop: vibrate))),
      proximityHoldDurationProvider
          .overrideWithValue(const Duration(milliseconds: 50)),
      proximityStopWindowProvider
          .overrideWithValue(const Duration(milliseconds: 400)),
      hapticsServiceProvider.overrideWithValue(haptics),
      locationServiceProvider.overrideWithValue(location),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      sensorServiceProvider.overrideWithValue(sensors),
      appDatabaseProvider.overrideWithValue(db),
      bikeProfilesStoreProvider.overrideWithValue(
        FakeBikeProfilesStore(bikeProfiles ?? BikeProfilesState.empty),
      ),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
    ]);
  }

  tearDown(() async {
    container.dispose();
    await buttons.dispose();
    await location.dispose();
    await sensors.dispose();
    await db.close();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('enables interception and toggles recording with the volume keys',
      () async {
    container = build(enabled: true);
    // Keep the wiring alive.
    container.listen(hardwareButtonControllerProvider, (_, _) {});
    await settle();
    expect(buttons.enabled, isTrue);
    expect(container.read(recordingProvider), isFalse);

    buttons.press(HardwareButton.volumeUp); // start
    await settle();
    expect(container.read(recordingProvider), isTrue);

    buttons.press(HardwareButton.volumeDown); // stop
    await settle();
    expect(container.read(recordingProvider), isFalse);
  });

  test('does nothing when the setting is disabled', () async {
    container = build(enabled: false);
    container.listen(hardwareButtonControllerProvider, (_, _) {});
    await settle();
    expect(buttons.enabled, isFalse);

    buttons.press(HardwareButton.volumeUp);
    await settle();
    expect(container.read(recordingProvider), isFalse);
  });

  test('toggling the setting updates interception', () async {
    container = build(enabled: false);
    container.listen(hardwareButtonControllerProvider, (_, _) {});
    await settle();
    expect(buttons.enabled, isFalse);

    await container.read(settingsProvider.notifier).setHardwareButtons(true);
    await settle();
    expect(buttons.enabled, isTrue);

    buttons.press(HardwareButton.volumeUp);
    await settle();
    expect(container.read(recordingProvider), isTrue);
  });

  test(
      'a 2nd volume-up press while recording cycles the bike profile '
      'instead of starting again', () async {
    const p1 = BikeProfile(id: 'p1', name: 'Road', colorArgb: 1);
    const p2 = BikeProfile(id: 'p2', name: 'Gravel', colorArgb: 2);
    container = build(
      bikeProfiles: const BikeProfilesState(profiles: [p1, p2], activeId: 'p1'),
    );
    container.listen(hardwareButtonControllerProvider, (_, _) {});
    container.listen(bikeProfilesProvider, (_, _) {});
    await settle();

    buttons.press(HardwareButton.volumeUp); // 1st press: starts
    await settle();
    expect(container.read(recordingProvider), isTrue);
    expect(container.read(bikeProfilesProvider).activeId, 'p1');

    buttons.press(HardwareButton.volumeUp); // 2nd press: cycles, doesn't stop
    await settle();
    expect(container.read(recordingProvider), isTrue); // still recording
    expect(container.read(bikeProfilesProvider).activeId, 'p2');

    buttons.press(HardwareButton.volumeUp); // 3rd press: cycles back
    await settle();
    expect(container.read(bikeProfilesProvider).activeId, 'p1');
  });

  test('the active bike\'s wheel circumference is pushed to the sensor service',
      () async {
    container = build(
      enabled: true,
      bikeProfiles: const BikeProfilesState(
        profiles: [
          BikeProfile(id: 'road', name: 'Road', colorArgb: 1),
          BikeProfile(
              id: 'mtb',
              name: 'MTB',
              colorArgb: 2,
              settings: BikeSettings(wheelCircumferenceMeters: 2.3)),
        ],
        activeId: 'road',
      ),
    );
    container.listen(sensorSettingsSyncProvider, (_, _) {});
    await settle();
    // Road never had its own: the default.
    expect(sensors.wheelCircumference, closeTo(2.105, 1e-9));

    await container.read(bikeProfilesProvider.notifier).setSettings(
        'road', const BikeSettings(wheelCircumferenceMeters: 2.2));
    await settle();
    expect(sensors.wheelCircumference, closeTo(2.2, 1e-9));

    // Switching bikes (e.g. volume-up mid-ride) switches the wheel too.
    await container.read(bikeProfilesProvider.notifier).setActive('mtb');
    await settle();
    expect(sensors.wheelCircumference, closeTo(2.3, 1e-9));
  });

  group('proximity hold (iOS)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<void> hold() async {
      buttons.cover(true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      buttons.cover(false);
      await settle();
    }

    bool recording() => container.read(recordingProvider);
    DateTime? armed() => container.read(proximityStopProvider);

    test(
        'a hold starts a ride; stopping takes a second hold, the hand taken '
        'away in between', () async {
      container = build(proximityHold: true);
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();
      expect(buttons.proximityEnabled, isTrue);

      await hold();
      expect(recording(), isTrue);
      expect(haptics.felt, [RideFeedback.started]);

      // The first hold only arms the stop: one buzz.
      await hold();
      expect(recording(), isTrue);
      expect(armed(), isNotNull);
      expect(haptics.felt.last, RideFeedback.stopArmed);

      await hold();
      expect(recording(), isFalse);
      expect(armed(), isNull);
      expect(haptics.felt.last, RideFeedback.stopped);
    });

    test('a single hold — a hand passing over — stops nothing: it runs out',
        () async {
      container = build(proximityHold: true);
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();
      await hold();
      await hold();
      expect(armed(), isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(armed(), isNull);
      expect(recording(), isTrue);
      // The next hold is a first one again.
      await hold();
      expect(recording(), isTrue);
      expect(armed(), isNotNull);
    });

    test('keeping the hand there is one hold, not two', () async {
      container = build(proximityHold: true);
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();
      await hold();

      buttons.cover(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      buttons.cover(false);
      await settle();
      expect(recording(), isTrue);
      expect(armed(), isNotNull);
    });

    test('stopped some other way: nothing left armed', () async {
      container = build(proximityHold: true);
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();
      await hold();
      await hold();
      expect(armed(), isNotNull);

      await container.read(recordingProvider.notifier).toggle(); // TIME
      await settle();
      expect(armed(), isNull);
      // A new ride starts with a single hold, and is armed afresh.
      await hold();
      expect(recording(), isTrue);
      expect(armed(), isNull);
    });

    test('vibration off: no buzz, still two holds', () async {
      container = build(proximityHold: true, vibrate: false);
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();
      await hold();
      await hold();
      expect(recording(), isTrue);
      await hold();
      expect(recording(), isFalse);
      expect(haptics.felt, isEmpty);
    });

    test('a brief cover does nothing', () async {
      container = build(proximityHold: true);
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();

      buttons.cover(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      buttons.cover(false);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(container.read(recordingProvider), isFalse);
    });

    test('off by default: the sensor is not even monitored', () async {
      container = build();
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();
      expect(buttons.proximityEnabled, isFalse);

      await hold();
      expect(container.read(recordingProvider), isFalse);
    });

    test('volume keys are never intercepted on iOS (guideline 2.5.9)',
        () async {
      container = build(enabled: true);
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();
      expect(buttons.setEnabledCalls, 0);
    });

    test('works independently of the volume-key setting', () async {
      container = build(enabled: false, proximityHold: true);
      container.listen(hardwareButtonControllerProvider, (_, _) {});
      await settle();
      await hold();
      expect(container.read(recordingProvider), isTrue);
    });
  });

  test('proximity hold is never enabled on Android (not wired natively)',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    container = build(proximityHold: true);
    container.listen(hardwareButtonControllerProvider, (_, _) {});
    await settle();
    expect(buttons.proximityEnabled, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
