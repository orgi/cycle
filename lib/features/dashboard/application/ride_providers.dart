import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/metrics/ride_metrics_accumulator.dart';
import '../../../core/models/geo_sample.dart';
import '../../../core/models/ride_metrics.dart';
import '../../../core/sensors/gatt.dart';
import '../../../core/sensors/sensor_service.dart';
import '../../../core/sensors/speed_fusion.dart';
import '../../../core/services/battery_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/fg_task_recording_service.dart';
import '../../../core/services/recording_foreground_service.dart';
import '../../../core/services/screen_wake_service.dart';
import '../../../core/services/settings/app_settings.dart';
import '../../sensors/application/sensor_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../tracks/application/track_repair.dart';

/// Platform GPS source. Overridden with a fake in tests.
final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);

/// Keep-screen-awake service. Overridden with a no-op in tests.
final screenWakeServiceProvider = Provider<ScreenWakeService>(
  (ref) => const WakelockScreenWakeService(),
);

/// Battery level source for the ride drain stat. No-op in tests.
final batteryServiceProvider =
    Provider<BatteryService>((ref) => NativeBatteryService());

/// Local track database. Overridden with an in-memory db in tests.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Keeps recording alive in the background: a real Android foreground service
/// (persistent notification, `location` type), started without a callback/
/// TaskHandler so the plugin doesn't spin up a second Flutter engine — see
/// FgTaskRecordingService's doc comment.
final recordingForegroundServiceProvider = Provider<RecordingForegroundService>(
  (ref) => const FgTaskRecordingService(),
);

/// Whether a ride is currently being recorded. Recording persists a [Tracks]
/// row plus a [TrackPoints] row per GPS sample, and finalises stats on stop.
final recordingProvider =
    NotifierProvider<RecordingController, bool>(RecordingController.new);

class RecordingController extends Notifier<bool> {
  int? _trackId;

  /// The id of the ride being recorded, if any.
  int? get currentTrackId => _trackId;

  @override
  bool build() => false;

  Future<void> start() async {
    if (state) return;
    await ref.read(screenWakeServiceProvider).enable();
    ref.read(rideControllerProvider.notifier).reset();
    final battery = await ref.read(batteryServiceProvider).level();
    final bikeProfileId = ref.read(bikeProfilesProvider).activeId;
    _trackId = await ref.read(appDatabaseProvider).createTrack(
          DateTime.now(),
          batteryStartPercent: battery,
          bikeProfileId: bikeProfileId,
        );
    await ref.read(recordingForegroundServiceProvider).start();
    state = true;
  }

  /// Sets the active bike profile; if a ride is currently recording, also
  /// live-corrects that ride's stamped profile (in case the wrong one was
  /// active when it started).
  Future<void> setBikeProfile(String id) async {
    await ref.read(bikeProfilesProvider.notifier).setActive(id);
    final trackId = _trackId;
    if (state && trackId != null) {
      await ref.read(appDatabaseProvider).setTrackBikeProfile(trackId, id);
    }
  }

  /// Advances to the next bike profile (wrapping). No-op with fewer than 2
  /// profiles. See [setBikeProfile].
  Future<void> cycleBikeProfile() async {
    final profiles = ref.read(bikeProfilesProvider).profiles;
    if (profiles.length < 2) return;
    final activeId = ref.read(bikeProfilesProvider).activeId;
    final i = profiles.indexWhere((p) => p.id == activeId);
    final next = profiles[(i + 1) % profiles.length];
    await setBikeProfile(next.id);
  }

  /// Resumes recording into an existing, interrupted ride — continues appending
  /// to the same track, its stats carried over.
  Future<void> resume(int trackId) async {
    if (state) return;
    await ref.read(screenWakeServiceProvider).enable();
    final points = await ref.read(appDatabaseProvider).pointsFor(trackId);
    ref.read(rideControllerProvider.notifier).resumeFrom(points);
    _trackId = trackId;
    await ref.read(recordingForegroundServiceProvider).start();
    state = true;
  }

  Future<void> stop() async {
    if (!state) return;
    state = false; // stop recording points before finalising
    final id = _trackId;
    _trackId = null;
    if (id != null) {
      final m = ref.read(rideControllerProvider);
      final battery = await ref.read(batteryServiceProvider).level();
      await ref.read(appDatabaseProvider).finalizeTrack(
            id,
            endedAt: DateTime.now(),
            distanceMeters: m.distanceMeters,
            durationSeconds: m.elapsed.inSeconds,
            avgSpeedMps: m.avgSpeedMps,
            maxSpeedMps: m.maxSpeedMps,
            batteryEndPercent: battery,
          );
    }
    await ref.read(recordingForegroundServiceProvider).stop();
    await ref.read(screenWakeServiceProvider).disable();
  }

  /// Persists one sample to the current ride (no-op when not recording).
  Future<void> recordPoint(
    GeoSample sample,
    SensorSnapshot? snapshot,
    double speedMps,
  ) async {
    final id = _trackId;
    if (!state || id == null) return;
    await ref.read(appDatabaseProvider).addPoint(
          TrackPointsCompanion.insert(
            trackId: id,
            time: sample.time,
            latitude: sample.latitude,
            longitude: sample.longitude,
            altitude: Value(sample.altitudeMeters),
            speedMps: Value(speedMps),
            heartRate: Value(snapshot?.heartRate),
            cadenceRpm: Value(snapshot?.cadenceRpm),
            power: Value(snapshot?.power),
          ),
        );
  }

  Future<void> toggle() => state ? stop() : start();
}

/// Live ride metrics derived from the location stream.
final rideControllerProvider =
    NotifierProvider<RideController, RideMetrics>(RideController.new);

class RideController extends Notifier<RideMetrics> {
  final RideMetricsAccumulator _accumulator = RideMetricsAccumulator();
  final SpeedFusion _fusion = SpeedFusion();
  double _maxSpeedMps = 0;
  SensorSnapshot? _latestSnapshot;
  StreamSubscription<GeoSample>? _subscription;

  @override
  RideMetrics build() {
    // Auto-pause config from settings, kept in sync as the user changes it.
    _applyAutoPause(ref.read(settingsProvider));
    ref.listen(settingsProvider, (_, next) => _applyAutoPause(next));
    final service = ref.watch(locationServiceProvider);
    // Request location permission (no-op on the emulator where it's pre-granted;
    // shows the system dialog on a real device).
    unawaited(service.ensurePermission());
    _subscription = service.positions().listen(
          _onSample,
          // Keep the stream alive on a transient platform error.
          onError: (Object _) {},
          cancelOnError: false,
        );
    // Fold BLE wheel speed into the displayed speed as it arrives.
    ref.listen(sensorSnapshotProvider, (_, next) => next.whenData(_onSnapshot));
    // When the wheel-speed sensor drops, forget its speed so the display falls
    // straight back to GPS instead of holding the last (now stale) BLE value.
    ref.listen(connectedSensorsProvider, (_, next) {
      next.whenData((sensors) {
        final hasSpeed = sensors.any(
            (s) => s.connected && s.kinds.contains(SensorKind.speedCadence));
        if (!hasSpeed) {
          _fusion.clearBle();
          state = state.copyWith(
              currentSpeedMps: _fusedSpeed(DateTime.now()),
              speedFromSensor: false);
        }
      });
    });
    ref.onDispose(() => _subscription?.cancel());
    return const RideMetrics.zero();
  }

  void _onSample(GeoSample sample) {
    // Only a recording ride accumulates time/distance/avg/max. When idle we
    // still show the live current speed, but the ride totals stay at zero so
    // e.g. the timer does not run before the rider taps Start.
    if (!ref.read(recordingProvider)) {
      final gps = (sample.speedMps != null && sample.speedMps! >= 0)
          ? sample.speedMps!
          : 0.0;
      _fusion.updateGps(gps);
      final now = DateTime.now();
      state = RideMetrics.zero().copyWith(
          currentSpeedMps: _fusion.fused(now),
          speedFromSensor: _fusion.isUsingBle(now));
      return;
    }
    final metrics = _accumulator.add(sample);
    _fusion.updateGps(metrics.currentSpeedMps);
    final now = DateTime.now();
    final fused = _fusedSpeed(now);
    state = metrics.copyWith(
        currentSpeedMps: fused,
        maxSpeedMps: _maxSpeedMps,
        speedFromSensor: _fusion.isUsingBle(now));
    unawaited(ref
        .read(recordingProvider.notifier)
        .recordPoint(sample, _latestSnapshot, fused));
  }

  void _onSnapshot(SensorSnapshot snapshot) {
    _latestSnapshot = snapshot;
    final wheelSpeed = snapshot.wheelSpeedMps;
    if (wheelSpeed == null) return;
    final now = DateTime.now();
    _fusion.updateBle(wheelSpeed, now);
    // When idle, show live speed only; while recording, also track the max.
    if (!ref.read(recordingProvider)) {
      state = RideMetrics.zero().copyWith(
          currentSpeedMps: _fusion.fused(now),
          speedFromSensor: _fusion.isUsingBle(now));
      return;
    }
    state = state.copyWith(
      currentSpeedMps: _fusedSpeed(now),
      maxSpeedMps: _maxSpeedMps,
      speedFromSensor: _fusion.isUsingBle(now),
    );
  }

  /// Preloads the metrics from an interrupted ride's [points] so a resumed ride
  /// continues from where it left off (the dead-time gap is not counted).
  void resumeFrom(List<TrackPoint> points) {
    final m = computeStatsFromPoints(points, ref.read(settingsProvider));
    _maxSpeedMps = m.maxSpeedMps;
    _accumulator.resumeWith(
      distanceMeters: m.distanceMeters,
      movingMillis: m.elapsed.inMilliseconds,
      maxSpeedMps: m.maxSpeedMps,
    );
    state = m.copyWith(currentSpeedMps: 0, speedFromSensor: false);
  }

  void _applyAutoPause(AppSettings s) {
    _accumulator.autoPauseEnabled = s.autoPauseEnabled;
    _accumulator.autoPauseThresholdMps = s.autoPauseSpeedKmh / 3.6;
  }

  /// Fused (BLE-preferred) speed, also tracking the running max.
  double _fusedSpeed(DateTime now) {
    final fused = _fusion.fused(now);
    if (fused > _maxSpeedMps) _maxSpeedMps = fused;
    return fused;
  }

  /// Clears all running totals (called when a new ride starts).
  void reset() {
    _accumulator.reset();
    _fusion.reset();
    _maxSpeedMps = 0;
    state = const RideMetrics.zero();
  }
}

/// Thin read-only view the dashboard watches. Overriding this with a fixed
/// value in widget tests avoids touching the location stream entirely.
final rideMetricsProvider = Provider<RideMetrics>(
  (ref) => ref.watch(rideControllerProvider),
);
