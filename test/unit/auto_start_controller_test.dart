import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/dashboard/application/auto_start_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late AppDatabase db;

  ProviderContainer build({bool? autoStart, BikeProfilesState? bikes}) {
    location = FakeLocationService();
    sensors = FakeSensorService();
    db = AppDatabase(NativeDatabase.memory());
    bikes ??= oneBike(BikeSettings(autoStartEnabled: autoStart ?? false));
    return ProviderContainer(overrides: [
      settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      locationServiceProvider.overrideWithValue(location),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      sensorServiceProvider.overrideWithValue(sensors),
      appDatabaseProvider.overrideWithValue(db),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikes)),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
    ]);
  }

  tearDown(() async {
    container.dispose();
    await location.dispose();
    await sensors.dispose();
    await db.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  final t0 = DateTime.utc(2026, 10, 7, 12);
  Future<void> rideFor(int seconds, double kmh) async {
    for (var s = 0; s <= seconds; s++) {
      location.emit(GeoSample(
        latitude: 47,
        longitude: 11 + s * 1e-4,
        time: t0.add(Duration(seconds: s)),
        speedMps: kmh / 3.6,
        accuracyMeters: 4,
      ));
    }
    await settle();
  }

  test('riding off starts recording when enabled', () async {
    container = build(autoStart: true);
    container.listen(autoStartControllerProvider, (_, _) {});
    container.listen(recordingProvider, (_, _) {});
    await settle();
    expect(container.read(autoStartControllerProvider), isTrue);

    await rideFor(6, 20);
    expect(container.read(recordingProvider), isTrue);
  });

  test('starts above the active bike\'s own start speed', () async {
    container = build(
        bikes: oneBike(const BikeSettings(
            autoStartEnabled: true, autoStartSpeedKmh: 15)));
    container.listen(autoStartControllerProvider, (_, _) {});
    container.listen(recordingProvider, (_, _) {});
    await settle();

    await rideFor(10, 12); // would have started at the old fixed 8 km/h
    expect(container.read(recordingProvider), isFalse);
    await rideFor(6, 16);
    expect(container.read(recordingProvider), isTrue);
  });

  test('an edited start speed applies from the next fix', () async {
    container = build(
        bikes: oneBike(const BikeSettings(
            autoStartEnabled: true, autoStartSpeedKmh: 15)));
    container.listen(autoStartControllerProvider, (_, _) {});
    container.listen(recordingProvider, (_, _) {});
    await settle();
    await rideFor(10, 12);
    expect(container.read(recordingProvider), isFalse);

    await container.read(bikeProfilesProvider.notifier).setSettings('bike',
        const BikeSettings(autoStartEnabled: true, autoStartSpeedKmh: 10));
    await rideFor(6, 12);
    expect(container.read(recordingProvider), isTrue);
  });

  test('does nothing when the setting is off (the default)', () async {
    container = build(autoStart: false);
    container.listen(autoStartControllerProvider, (_, _) {});
    container.listen(recordingProvider, (_, _) {});
    await settle();

    await rideFor(30, 20);
    expect(container.read(recordingProvider), isFalse);
  });

  test('is off for a bike that never had the setting (the old default)',
      () async {
    container = build(bikes: oneBike());
    container.listen(autoStartControllerProvider, (_, _) {});
    await settle();
    expect(container.read(autoStartControllerProvider), isFalse);
  });

  test('follows the active bike', () async {
    container = build(
      bikes: const BikeProfilesState(
        profiles: [
          BikeProfile(
              id: 'commute',
              name: 'Commuter',
              colorArgb: 1,
              settings: BikeSettings(autoStartEnabled: true)),
          BikeProfile(
              id: 'mtb',
              name: 'MTB',
              colorArgb: 2,
              settings: BikeSettings(autoStartEnabled: false)),
        ],
        activeId: 'mtb',
      ),
    );
    container.listen(autoStartControllerProvider, (_, _) {});
    container.listen(recordingProvider, (_, _) {});
    await settle();
    expect(container.read(autoStartControllerProvider), isFalse);
    await rideFor(10, 20);
    expect(container.read(recordingProvider), isFalse);

    await container.read(bikeProfilesProvider.notifier).setActive('commute');
    await settle();
    expect(container.read(autoStartControllerProvider), isTrue);
    await rideFor(6, 20);
    expect(container.read(recordingProvider), isTrue);
  });
}
