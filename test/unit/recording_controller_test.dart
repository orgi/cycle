import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/metrics/elevation.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
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
  late RecordingLocationPowerControl gpsGate;
  late FakeLocationService location;
  late FakeSensorService sensors;
  late AppDatabase db;

  ProviderContainer build({BikeProfilesState? bikeProfiles}) =>
      ProviderContainer(
        overrides: [
          screenWakeServiceProvider.overrideWithValue(wake),
          locationPowerControlProvider.overrideWithValue(gpsGate),
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
    gpsGate = RecordingLocationPowerControl();
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
    // Ride start re-arms the sensor reconnect retry window.
    expect(sensors.retryConnectionsCalls, 1);

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

  test(
      'an inaccurate fix updates the live speed but is neither counted nor '
      'saved', () async {
    final notifier = container.read(recordingProvider.notifier);
    container.listen(rideControllerProvider, (_, _) {});

    await notifier.start();
    final trackId = notifier.currentTrackId!;

    final t0 = DateTime.utc(2026, 1, 1, 12);
    location.emit(GeoSample(
        latitude: 0, longitude: 0, time: t0, speedMps: 5, accuracyMeters: 4));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // 30 m accuracy, 200 m away: a drifting fix while standing still.
    location.emit(GeoSample(
      latitude: 0,
      longitude: 0.0018,
      time: t0.add(const Duration(seconds: 5)),
      speedMps: 2,
      accuracyMeters: 30,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final metrics = container.read(rideControllerProvider);
    expect(metrics.currentSpeedMps, 2); // the display follows the fix
    expect(metrics.distanceMeters, 0); // the ride doesn't
    expect(metrics.maxSpeedMps, 5);
    expect(await db.pointsFor(trackId), hasLength(1));
    await notifier.stop();
  });

  test(
      'elevation: the height shows idle and riding; a ride counts its climb '
      'and profile, its saved points give the same climb, also on resume',
      () async {
    final notifier = container.read(recordingProvider.notifier);
    container.listen(rideControllerProvider, (_, _) {});
    final t0 = DateTime.utc(2026, 1, 1, 12);
    var s = 0;
    Future<void> fix(double altitude, {double speed = 5}) async {
      location.emit(GeoSample(
        latitude: 0,
        longitude: s * 0.00005, // ~5.6 m per fix
        time: t0.add(Duration(seconds: s)),
        speedMps: speed,
        altitudeMeters: altitude,
        accuracyMeters: 4,
      ));
      s++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    await fix(500, speed: 0);
    var m = container.read(rideControllerProvider);
    expect(m.elevationMeters, 500);
    expect(m.climbMeters, 0);
    expect(m.elevationProfile.isEmpty, isTrue); // no ride, no profile

    await notifier.start();
    final trackId = notifier.currentTrackId!;
    for (var i = 0; i < 60; i++) {
      await fix(500 + i.toDouble());
    }
    m = container.read(rideControllerProvider);
    // Smoothed over 5 fixes, so 2 m short of the 559 m reached.
    expect(m.elevationMeters, closeTo(557, 1e-9));
    expect(m.climbMeters, closeTo(57, 1e-9));
    expect(m.elevationProfile.points.length, greaterThan(20));
    expect(m.elevationProfile.points.last.elevationMeters, closeTo(557, 1e-9));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await notifier.stop();

    final points = await db.pointsFor(trackId);
    expect(
        rideClimbMeters(
            points.map((p) => (altitude: p.altitude, speedMps: p.speedMps))),
        m.climbMeters);

    await notifier.resume(trackId);
    expect(container.read(rideControllerProvider).climbMeters, m.climbMeters);
    await notifier.stop();

    // The next ride starts from nothing.
    await notifier.start();
    m = container.read(rideControllerProvider);
    expect(m.climbMeters, 0);
    expect(m.elevationProfile.isEmpty, isTrue);
    expect(m.elevationMeters, closeTo(557, 1e-9)); // the height still shows
    await notifier.stop();
  });

  test('recorded points flag whether their speed came from a BLE sensor',
      () async {
    final notifier = container.read(recordingProvider.notifier);
    container.listen(rideControllerProvider, (_, _) {});
    await notifier.start();
    final trackId = notifier.currentTrackId!;

    final t0 = DateTime.utc(2026, 1, 1, 12);
    // No sensor yet: GPS-derived speed.
    location.emit(GeoSample(latitude: 0, longitude: 0, time: t0, speedMps: 5));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // A wheel-speed sensor comes online; subsequent points use it.
    sensors.emitSnapshot(const SensorSnapshot(wheelSpeedMps: 9));
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

    final points = await db.pointsFor(trackId);
    expect(points.length, 2);
    expect(points.first.speedFromSensor, isFalse);
    expect(points.last.speedFromSensor, isTrue);
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

  test('the active bike\'s auto-pause applies to the ride, also after a '
      'switch mid-ride', () async {
    // Touring pauses below 10 km/h, the road bike never.
    container.dispose();
    container = build(
      bikeProfiles: const BikeProfilesState(
        profiles: [
          BikeProfile(
              id: 'touring',
              name: 'Touring',
              colorArgb: 1,
              settings: BikeSettings(autoPauseSpeedKmh: 10)),
          BikeProfile(
              id: 'road',
              name: 'Road',
              colorArgb: 2,
              settings: BikeSettings(autoPauseEnabled: false)),
        ],
        activeId: 'touring',
      ),
    );
    container.listen(rideControllerProvider, (_, _) {});
    container.listen(bikeProfilesProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final notifier = container.read(recordingProvider.notifier);
    await notifier.start();

    final t0 = DateTime.utc(2026, 1, 1, 12);
    var s = 0;
    Future<void> roll(int seconds) async {
      for (final end = s + seconds; s < end; s++) {
        location.emit(GeoSample(
          latitude: 0,
          longitude: s * 0.00002, // ~2.2 m per second
          time: t0.add(Duration(seconds: s)),
          speedMps: 2, // 7.2 km/h
        ));
        await Future<void>.delayed(Duration.zero);
      }
    }

    await roll(5);
    expect(container.read(rideControllerProvider).elapsed, Duration.zero);

    await notifier.setBikeProfile('road');
    await roll(5);
    expect(container.read(rideControllerProvider).elapsed,
        const Duration(seconds: 5));
    await notifier.stop();
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

  test('tells the native GPS gate when a ride is and is not recording',
      () async {
    // Backgrounding an idle app drops the GPS request; backgrounding a
    // recording ride must not, so the native side needs the recording state.
    await container.read(recordingProvider.notifier).start();
    expect(gpsGate.calls, [true]);

    await container.read(recordingProvider.notifier).stop();
    expect(gpsGate.calls, [true, false]);
  });
}
