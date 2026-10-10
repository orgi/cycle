import 'dart:io';

import 'package:cycle/core/battery_test/battery_test_log.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/battery_service.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/core/services/simulated_ride_location_service.dart';
import 'package:cycle/core/utils/geo.dart';
import 'package:cycle/features/battery_test/application/battery_test_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Battery level that drops by one point per reading.
class _DrainingBattery implements BatteryService {
  _DrainingBattery(this._level);
  int _level;
  @override
  Future<int?> level() async => _level--;
}

void main() {
  late Directory tmp;
  late ProviderContainer c;
  late FakeLocationService device;
  late FakeSensorService sensors;
  late AppDatabase db;
  late RecordingScreenWakeService wake;

  ProviderContainer build() {
    device = FakeLocationService();
    sensors = FakeSensorService();
    db = AppDatabase(NativeDatabase.memory());
    wake = RecordingScreenWakeService();
    return ProviderContainer(overrides: [
      // The real GPS; the app-wide locationServiceProvider is NOT overridden,
      // so the simulated-ride switch is exercised for real.
      deviceLocationServiceProvider.overrideWithValue(device),
      batteryTestStoreProvider
          .overrideWithValue(BatteryTestStore(() async => tmp)),
      batteryTestSampleIntervalProvider
          .overrideWithValue(const Duration(milliseconds: 40)),
      batteryServiceProvider.overrideWithValue(_DrainingBattery(97)),
      screenWakeServiceProvider.overrideWithValue(wake),
      settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      sensorServiceProvider.overrideWithValue(sensors),
      appDatabaseProvider.overrideWithValue(db),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
      recordingForegroundServiceProvider
          .overrideWithValue(const NoopRecordingForegroundService()),
      hapticsServiceProvider.overrideWithValue(RecordingHapticsService()),
    ]);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('battery_test_');
    c = build();
  });

  tearDown(() async {
    c.dispose();
    await device.dispose();
    await sensors.dispose();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  GeoSample home() => GeoSample(
        latitude: 47.8,
        longitude: 11.9,
        time: DateTime.now(),
        accuracyMeters: 4,
      );

  Future<void> givenARealFix() async {
    c.listen(currentPositionProvider, (_, _) {});
    await wait(10);
    device.emit(home());
    await wait(10);
  }

  test('start → simulated ride over the rider\'s area, real GPS still on, '
      'samples logged, stop', () async {
    await givenARealFix();
    final positions = <GeoSample>[];
    c.listen(currentPositionProvider, (_, n) {
      if (n.value != null) positions.add(n.value!);
    });

    expect(await c.read(batteryTestProvider.notifier).start(),
        BatteryTestStartResult.started);
    expect(wake.isHeld, isTrue); // screen kept on
    final service = c.read(locationServiceProvider);
    expect(service, isA<SimulatedRideLocationService>());

    await wait(150);
    // The map is fed the loop around the last real fix (800 m away from it).
    expect(positions, isNotEmpty);
    final p = positions.last;
    expect(haversineMeters(47.8, 11.9, p.latitude, p.longitude),
        closeTo(800, 2));
    // The real GPS is still subscribed underneath; its fixes are counted.
    device.emit(home());
    device.emit(home());
    await wait(60);

    await c.read(batteryTestProvider.notifier).stop();
    expect(wake.isHeld, isFalse);
    expect(c.read(locationServiceProvider), same(device)); // real GPS again

    final results = await c.read(batteryTestResultsProvider.future);
    final r = results.single;
    expect(r.stoppedByHand, isTrue);
    expect(r.startLevel, 97);
    expect(r.samples.length, greaterThanOrEqualTo(3)); // samples + stop
    expect(r.samples.map((s) => s.realFixes).fold<int>(0, (a, b) => a + b), 2);
  });

  test('no ride can be recorded during a test (simulated positions)', () async {
    await givenARealFix();
    await c.read(batteryTestProvider.notifier).start();
    await c.read(recordingProvider.notifier).start();
    expect(c.read(recordingProvider), isFalse);
    await c.read(batteryTestProvider.notifier).stop();
  });

  test('cannot start while a ride is recording', () async {
    await givenARealFix();
    c.listen(recordingProvider, (_, _) {});
    await c.read(recordingProvider.notifier).start();
    expect(await c.read(batteryTestProvider.notifier).start(),
        BatteryTestStartResult.rideRecording);
    await c.read(recordingProvider.notifier).stop();
  });

  test('a test the phone ended is announced once, then marked seen', () async {
    // A previous test with no stop line: the phone switched off.
    final store = BatteryTestStore(() async => tmp);
    final t0 = DateTime.utc(2026, 10, 10, 6);
    await store.append('old', BatteryTestLog.startLine(t0, 100, 'iOS'));
    await store.append('old', BatteryTestLog.sampleLine(
        t0.add(const Duration(hours: 7, minutes: 12)), 1, 40));

    final unseen = await c.read(unseenShutdownResultProvider.future);
    expect(unseen?.id, 'old');
    expect(unseen!.runtime, const Duration(hours: 7, minutes: 12));

    await c.read(batteryTestProvider.notifier).markSeen('old');
    expect(await c.read(unseenShutdownResultProvider.future), isNull);
  });
}
