import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/core/services/battery_service.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/location_power_control.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Reproduces the field reports: after a sensor's link dropped, its last value
/// stayed on the dashboard, was recorded into the next ride, and a gone speed
/// sensor's wheel speed kept the speed tile "from sensor" green.
void main() {
  late FakeSensorService sensors;
  late FakeLocationService location;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    sensors = FakeSensorService();
    location = FakeLocationService();
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(sensors),
      locationServiceProvider.overrideWithValue(location),
      appDatabaseProvider.overrideWithValue(db),
      screenWakeServiceProvider.overrideWithValue(RecordingScreenWakeService()),
      locationPowerControlProvider
          .overrideWithValue(const NoopLocationPowerControl()),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
      batteryServiceProvider.overrideWithValue(NoopBatteryService()),
      settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      bikeProfilesStoreProvider
          .overrideWithValue(FakeBikeProfilesStore(BikeProfilesState.empty)),
    ]);
    container.listen(rideControllerProvider, (_, _) {});
    container.listen(sensorSnapshotProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await sensors.dispose();
    await location.dispose();
    await db.close();
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  GeoSample fix({double speed = 4.0}) => GeoSample(
        latitude: 43.74,
        longitude: 7.42,
        time: DateTime.now(),
        speedMps: speed,
        accuracyMeters: 3,
      );

  Future<List<TrackPoint>> recordOnePoint() async {
    await container.read(recordingProvider.notifier).start();
    location.emit(fix());
    await settle();
    final id = container.read(recordingProvider.notifier).currentTrackId!;
    return db.pointsFor(id);
  }

  test('control: a linked heart-rate sensor is recorded', () async {
    await sensors.connect('hr');
    sensors.emitReading('hr', const SensorSnapshot(heartRate: 150));
    await settle();

    final points = await recordOnePoint();
    expect(points.single.heartRate, 150);
  });

  test("a dropped heart-rate sensor's last value is not shown or recorded",
      () async {
    await sensors.connect('hr');
    sensors.emitReading('hr', const SensorSnapshot(heartRate: 150));
    await settle();

    sensors.dropLink('hr');
    await settle();
    expect(container.read(sensorSnapshotProvider).value?.heartRate, isNull,
        reason: 'the dashboard tile must fall back to "—"');

    final points = await recordOnePoint();
    expect(points.single.heartRate, isNull,
        reason: "a gone strap's value must not land in the next ride's average");
  });

  test('a dropped cadence sensor is not recorded either', () async {
    await sensors.connect('cad');
    sensors.emitReading('cad', const SensorSnapshot(cadenceRpm: 85));
    await settle();
    sensors.dropLink('cad');
    await settle();

    final points = await recordOnePoint();
    expect(points.single.cadenceRpm, isNull);
  });

  test(
      "cadence notifications don't keep a gone speed sensor's reading 'fresh'",
      () async {
    await sensors.connect('spd');
    await sensors.connect('cad');
    sensors.emitReading('spd', const SensorSnapshot(wheelSpeedMps: 5.0));
    sensors.emitReading('cad', const SensorSnapshot(cadenceRpm: 80));
    await settle();

    sensors.dropLink('spd');
    // Let the speed fusion's 3 s freshness window lapse, as it would on the
    // road — then a cadence notification arrives. With the old global
    // snapshot that notification re-broadcast wheel speed 5.0 and re-armed it.
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    sensors.emitReading('cad', const SensorSnapshot(cadenceRpm: 82));
    await settle();
    location.emit(fix(speed: 4.0));
    await settle();

    final m = container.read(rideControllerProvider);
    expect(m.speedFromSensor, isFalse,
        reason: 'the speed tile must not show "from sensor" green');
    expect(m.currentSpeedMps, closeTo(4.0, 1e-9),
        reason: 'and it should show the GPS speed');
  });
}
