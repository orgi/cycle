import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/hardware_button_service.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/hardware_button_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeHardwareButtonService buttons;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late AppDatabase db;

  ProviderContainer build({bool enabled = true, BikeProfilesState? bikeProfiles}) {
    buttons = FakeHardwareButtonService();
    location = FakeLocationService();
    sensors = FakeSensorService();
    db = AppDatabase(NativeDatabase.memory());
    return ProviderContainer(overrides: [
      hardwareButtonServiceProvider.overrideWithValue(buttons),
      settingsStoreProvider.overrideWithValue(
          FakeSettingsStore(AppSettings(hardwareButtonsEnabled: enabled))),
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

  test('wheel-circumference setting is pushed to the sensor service', () async {
    container = build(enabled: true);
    container.listen(sensorSettingsSyncProvider, (_, _) {});
    await settle();
    expect(sensors.wheelCircumference, closeTo(2.105, 1e-9));

    await container
        .read(settingsProvider.notifier)
        .setWheelCircumference(2.2);
    await settle();
    expect(sensors.wheelCircumference, closeTo(2.2, 1e-9));
  });
}
