import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
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

  ProviderContainer build({required bool autoStart}) {
    location = FakeLocationService();
    sensors = FakeSensorService();
    db = AppDatabase(NativeDatabase.memory());
    return ProviderContainer(overrides: [
      settingsStoreProvider.overrideWithValue(
          FakeSettingsStore(AppSettings(autoStartEnabled: autoStart))),
      locationServiceProvider.overrideWithValue(location),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      sensorServiceProvider.overrideWithValue(sensors),
      appDatabaseProvider.overrideWithValue(db),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
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

  test('does nothing when the setting is off (the default)', () async {
    container = build(autoStart: false);
    container.listen(autoStartControllerProvider, (_, _) {});
    container.listen(recordingProvider, (_, _) {});
    await settle();

    await rideFor(30, 20);
    expect(container.read(recordingProvider), isFalse);
  });
}
