import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late ProviderContainer container;
  late RecordingScreenWakeService wake;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late AppDatabase db;

  setUp(() {
    wake = RecordingScreenWakeService();
    location = FakeLocationService();
    sensors = FakeSensorService();
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        screenWakeServiceProvider.overrideWithValue(wake),
        locationServiceProvider.overrideWithValue(location),
        sensorServiceProvider.overrideWithValue(sensors),
        appDatabaseProvider.overrideWithValue(db),
        recordingForegroundServiceProvider
            .overrideWithValue(const NoopRecordingForegroundService()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await location.dispose();
    await sensors.dispose();
    await db.close();
  });

  test('starts and stops recording, toggling the wakelock', () async {
    expect(container.read(recordingProvider), isFalse);

    await container.read(recordingProvider.notifier).start();
    expect(container.read(recordingProvider), isTrue);
    expect(wake.enableCount, 1);

    await container.read(recordingProvider.notifier).stop();
    expect(container.read(recordingProvider), isFalse);
    expect(wake.disableCount, 1);
  });

  test('live metrics update as samples arrive', () async {
    final t0 = DateTime.utc(2026, 1, 1, 12);
    container.listen(rideControllerProvider, (_, _) {});

    location.emit(GeoSample(latitude: 0, longitude: 0, time: t0, speedMps: 5));
    await Future<void>.delayed(Duration.zero);
    location.emit(GeoSample(
      latitude: 0,
      longitude: 0.00089932,
      time: t0.add(const Duration(seconds: 10)),
      speedMps: 8,
    ));
    await Future<void>.delayed(Duration.zero);

    final metrics = container.read(rideControllerProvider);
    expect(metrics.distanceMeters, closeTo(100, 1));
    expect(metrics.currentSpeedMps, 8);
  });

  test('recording persists a track with points and finalises stats', () async {
    final notifier = container.read(recordingProvider.notifier);
    container.listen(rideControllerProvider, (_, _) {});

    await notifier.start();
    final trackId = notifier.currentTrackId!;

    final t0 = DateTime.utc(2026, 1, 1, 12);
    location.emit(GeoSample(latitude: 0, longitude: 0, time: t0, speedMps: 5));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    location.emit(GeoSample(
      latitude: 0,
      longitude: 0.00089932,
      time: t0.add(const Duration(seconds: 10)),
      speedMps: 8,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    await notifier.stop();

    final track = await db.track(trackId);
    expect(track, isNotNull);
    expect(track!.endedAt, isNotNull);
    expect(track.distanceMeters, closeTo(100, 1));

    final points = await db.pointsFor(trackId);
    expect(points.length, 2);
    expect(points.last.latitude, closeTo(0, 0.0001));
  });
}
