import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
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
  late RecordingScreenWakeService wake;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late AppDatabase db;

  ProviderContainer build({BikeProfilesState? bikeProfiles}) =>
      ProviderContainer(
        overrides: [
          screenWakeServiceProvider.overrideWithValue(wake),
          locationServiceProvider.overrideWithValue(location),
          sensorServiceProvider.overrideWithValue(sensors),
          appDatabaseProvider.overrideWithValue(db),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          bikeProfilesStoreProvider.overrideWithValue(
            FakeBikeProfilesStore(bikeProfiles ?? BikeProfilesState.empty),
          ),
          recordingForegroundServiceProvider.overrideWithValue(
            const NoopRecordingForegroundService(),
          ),
        ],
      );

  setUp(() {
    wake = RecordingScreenWakeService();
    location = FakeLocationService();
    sensors = FakeSensorService();
    db = AppDatabase(NativeDatabase.memory());
    container = build();
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

  test('idle: live speed shows but ride totals stay at zero', () async {
    final t0 = DateTime.utc(2026, 1, 1, 12);
    container.listen(rideControllerProvider, (_, _) {});

    location.emit(GeoSample(latitude: 0, longitude: 0, time: t0, speedMps: 5));
    await Future<void>.delayed(Duration.zero);
    location.emit(
      GeoSample(
        latitude: 0,
        longitude: 0.00089932,
        time: t0.add(const Duration(seconds: 10)),
        speedMps: 8,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final metrics = container.read(rideControllerProvider);
    expect(metrics.currentSpeedMps, 8); // live speed still shown
    expect(metrics.distanceMeters, 0); // but no ride accumulates
    expect(metrics.elapsed, Duration.zero);
  });

  test('recording: metrics accumulate as samples arrive', () async {
    final notifier = container.read(recordingProvider.notifier);
    container.listen(rideControllerProvider, (_, _) {});
    await notifier.start();

    final t0 = DateTime.utc(2026, 1, 1, 12);
    location.emit(GeoSample(latitude: 0, longitude: 0, time: t0, speedMps: 5));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    location.emit(
      GeoSample(
        latitude: 0,
        longitude: 0.00089932,
        time: t0.add(const Duration(seconds: 10)),
        speedMps: 10,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final metrics = container.read(rideControllerProvider);
    expect(metrics.distanceMeters, closeTo(100, 1));
    expect(metrics.currentSpeedMps, 10);
    expect(metrics.elapsed, const Duration(seconds: 10));
    await notifier.stop();
  });

  test('recording persists a track with points and finalises stats', () async {
    final notifier = container.read(recordingProvider.notifier);
    container.listen(rideControllerProvider, (_, _) {});

    await notifier.start();
    final trackId = notifier.currentTrackId!;

    final t0 = DateTime.utc(2026, 1, 1, 12);
    location.emit(GeoSample(latitude: 0, longitude: 0, time: t0, speedMps: 5));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    location.emit(
      GeoSample(
        latitude: 0,
        longitude: 0.00089932,
        time: t0.add(const Duration(seconds: 10)),
        speedMps: 10,
      ),
    );
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

  test('start() stamps the ride with the active bike profile', () async {
    const p1 = BikeProfile(id: 'p1', name: 'Road', colorArgb: 1);
    container.dispose();
    container = build(
      bikeProfiles: const BikeProfilesState(profiles: [p1], activeId: 'p1'),
    );
    // Let the async profile load settle before starting.
    container.listen(rideControllerProvider, (_, _) {});
    // Reading it kicks off the async store load; wait for it to settle before
    // starting/cycling (mirrors the home screen watching it from launch).
    container.listen(bikeProfilesProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final notifier = container.read(recordingProvider.notifier);
    await notifier.start();
    final track = await db.track(notifier.currentTrackId!);
    expect(track!.bikeProfileId, 'p1');
  });

  test('cycleBikeProfile advances and live-corrects the recording ride',
      () async {
    const p1 = BikeProfile(id: 'p1', name: 'Road', colorArgb: 1);
    const p2 = BikeProfile(id: 'p2', name: 'Gravel', colorArgb: 2);
    container.dispose();
    container = build(
      bikeProfiles:
          const BikeProfilesState(profiles: [p1, p2], activeId: 'p1'),
    );
    container.listen(rideControllerProvider, (_, _) {});
    // Reading it kicks off the async store load; wait for it to settle before
    // starting/cycling (mirrors the home screen watching it from launch).
    container.listen(bikeProfilesProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final notifier = container.read(recordingProvider.notifier);
    await notifier.start();
    final trackId = notifier.currentTrackId!;
    expect((await db.track(trackId))!.bikeProfileId, 'p1');

    await notifier.cycleBikeProfile();
    expect(container.read(bikeProfilesProvider).activeId, 'p2');
    expect((await db.track(trackId))!.bikeProfileId, 'p2');

    // Wraps back around.
    await notifier.cycleBikeProfile();
    expect(container.read(bikeProfilesProvider).activeId, 'p1');
    expect((await db.track(trackId))!.bikeProfileId, 'p1');
  });

  test('cycleBikeProfile is a no-op with a single profile', () async {
    const p1 = BikeProfile(id: 'p1', name: 'Road', colorArgb: 1);
    container.dispose();
    container = build(
      bikeProfiles: const BikeProfilesState(profiles: [p1], activeId: 'p1'),
    );
    container.listen(rideControllerProvider, (_, _) {});
    // Reading it kicks off the async store load; wait for it to settle before
    // starting/cycling (mirrors the home screen watching it from launch).
    container.listen(bikeProfilesProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container.read(recordingProvider.notifier).cycleBikeProfile();
    expect(container.read(bikeProfilesProvider).activeId, 'p1');
  });
}
