import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/metrics/elevation.dart';
import '../../../core/metrics/ride_metrics_accumulator.dart';
import '../../../core/models/bike_settings.dart';
import '../../../core/models/geo_sample.dart';
import '../../../core/models/ride_metrics.dart';
import '../../../core/sensors/gatt.dart';
import '../../../core/sensors/sensor_service.dart';
import '../../../core/sensors/speed_fusion.dart';
import '../../../core/battery_test/simulated_zigzag.dart';
import '../../../core/controls/ride_continuation.dart';
import '../../../core/services/apple_location_service.dart';
import '../../../core/services/battery_service.dart';
import '../../../core/services/location_power_control.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/native_location_service.dart';
import '../../../core/services/fg_task_recording_service.dart';
import '../../../core/services/haptics_service.dart';
import '../../../core/services/recording_foreground_service.dart';
import '../../../core/services/screen_wake_service.dart';
import '../../../core/services/simulated_ride_location_service.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/gps_accuracy_filter.dart';
import '../../health/application/apple_health_providers.dart';
import '../../sensors/application/sensor_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../tracks/application/track_repair.dart';

/// The device's real GPS.
///
/// Android uses the native continuous `LocationManager` stream
/// ([NativeLocationService]) — geolocator's polling cold-restarts the GPS and
/// its stream doesn't engage the receiver on the target hardware (see that
/// class + CLAUDE.md). iOS uses one continuous Core Location stream
/// ([AppleLocationService]). Other platforms fall back to geolocator polling.
final deviceLocationServiceProvider = Provider<LocationService>(
  (ref) => switch (defaultTargetPlatform) {
    TargetPlatform.android => NativeLocationService(),
    TargetPlatform.iOS => AppleLocationService(),
    _ => GeolocatorLocationService(),
  },
);

/// The simulated ride of a running battery runtime test, or null. Set and
/// cleared by `BatteryTestController`; while set, the app's positions come from
/// it (see [locationServiceProvider]) and no real ride can be recorded.
final simulatedRideProvider =
    NotifierProvider<SimulatedRideController, SimulatedZigzag?>(
        SimulatedRideController.new);

class SimulatedRideController extends Notifier<SimulatedZigzag?> {
  @override
  SimulatedZigzag? build() => null;

  void set(SimulatedZigzag? route) => state = route;
}

/// The position source the whole app reads (map, ride metrics, auto-start):
/// the real GPS, or — during a battery runtime test — a simulated ride with the
/// real GPS still running underneath. Overridden with a fake in tests.
final locationServiceProvider = Provider<LocationService>((ref) {
  final device = ref.watch(deviceLocationServiceProvider);
  final route = ref.watch(simulatedRideProvider);
  if (route == null) return device;
  final simulated = SimulatedRideLocationService(device, route);
  ref.onDispose(simulated.dispose);
  return simulated;
});

/// Tells the native layer whether a ride is recording, so the continuous GPS
/// request is held while a backgrounded ride records and dropped when the app
/// is backgrounded with no ride running. On iOS the gate lives in Dart, in the
/// location service itself ([AppleLocationService]). No-op elsewhere.
final locationPowerControlProvider = Provider<LocationPowerControl>((ref) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return const NativeLocationPowerControl();
  }
  // The real GPS — unwrapped from a battery test's simulated ride.
  final effective = ref.watch(locationServiceProvider);
  final service = effective is SimulatedRideLocationService
      ? effective.device
      : effective;
  return service is LocationPowerControl
      ? service as LocationPowerControl
      : const NoopLocationPowerControl();
});

/// Keep-screen-awake service. Overridden with a no-op in tests.
final screenWakeServiceProvider = Provider<ScreenWakeService>(
  (ref) => WakelockScreenWakeService(),
);

/// Vibration that confirms ride start/stop/bike switch. Overridable in tests.
final hapticsServiceProvider =
    Provider<HapticsService>((ref) => const NativeHapticsService());

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
/// FgTaskRecordingService's doc comment. iOS has no foreground services — a
/// backgrounded ride stays alive through `UIBackgroundModes: location` and the
/// continuous Core Location stream instead — so it gets the no-op.
final recordingForegroundServiceProvider = Provider<RecordingForegroundService>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? const NoopRecordingForegroundService()
      : const FgTaskRecordingService(),
);

/// How long a manual start waits for a current GPS fix when it might continue
/// the ride stopped last (see [RecordingController.start]). Overridable so
/// tests needn't wait in real time.
final continueFixWaitProvider =
    Provider<Duration>((ref) => const Duration(seconds: 15));

/// A message about a ride for the home screen to show once: a ride a place
/// started or stopped, or a manual start that continued the last ride.
class RideNotice {
  const RideNotice(this.message, {this.offerNewRide = false});
  final String message;

  /// Offers "New ride", which undoes a continuation
  /// ([RecordingController.startNewRideInstead]).
  final bool offerNewRide;
}

/// The latest [RideNotice], or null. Each notice is a new object, so the same
/// message twice is shown twice.
final rideNoticeProvider =
    NotifierProvider<RideNoticeController, RideNotice?>(
        RideNoticeController.new);

class RideNoticeController extends Notifier<RideNotice?> {
  @override
  RideNotice? build() => null;

  void show(RideNotice notice) => state = notice;
}

/// Whether a ride is currently being recorded. Recording persists a [Tracks]
/// row plus a [TrackPoints] row per GPS sample, and finalises stats on stop.
final recordingProvider =
    NotifierProvider<RecordingController, bool>(RecordingController.new);

class RecordingController extends Notifier<bool> {
  /// [SyncMeta] key: the id of the ride stopped last — the one a manual start
  /// may continue, and whose Apple Health save waits until it can't be.
  static const lastStoppedRideKey = 'last_stopped_ride';

  int? _trackId;
  bool _starting = false;
  ({Track before, DateTime lastPointAt})? _continued;
  Timer? _healthSave;

  /// The id of the ride being recorded, if any.
  int? get currentTrackId => _trackId;

  @override
  bool build() {
    ref.onDispose(() => _healthSave?.cancel());
    return false;
  }

  /// Confirms [feedback] by vibration (if enabled). Fired up front, not after
  /// the DB/foreground-service work, so it's felt the instant the trigger
  /// registers; unawaited, so it never delays the ride itself.
  void _confirm(RideFeedback feedback) {
    if (!ref.read(settingsProvider).vibrateOnStartStop) return;
    unawaited(ref.read(hapticsServiceProvider).confirm(feedback));
  }

  /// Starts a ride. A [manual] start (the button, a volume key, the hand over
  /// the screen — not auto-start or a place) continues the ride stopped last
  /// instead, if it stopped recently right here (`shouldContinueRide`, the
  /// "Continue a stopped ride" setting): an accidental stop is undone by
  /// starting again. Without a current fix it waits up to
  /// [continueFixWaitProvider] for one, then starts a new ride.
  Future<void> start({bool manual = false}) async {
    if (state || _starting) return;
    // A battery runtime test feeds simulated positions: never record those as
    // a ride (volume keys, auto-start and the button all come through here).
    if (ref.read(simulatedRideProvider) != null) return;
    _starting = true;
    try {
      _confirm(RideFeedback.started);
      // Flag the ride to the native GPS gate FIRST, before anything that can
      // push the activity through onPause (the foreground service can raise a
      // notification-permission dialog) — otherwise that pause sees "not
      // recording" and drops the GPS request mid-ride.
      await ref.read(locationPowerControlProvider).setRecordingActive(true);
      ({Track before, DateTime lastPointAt})? stopped;
      try {
        if (manual) stopped = await _continuableRide();
      } on Object catch (e) {
        debugPrint('continue a stopped ride: $e'); // a new ride, then
      }
      if (stopped != null) {
        await _resumeInto(stopped.before.id);
        _continued = stopped;
        ref.read(rideNoticeProvider.notifier).show(RideNotice(
            'Continued the ride stopped at '
            '${formatClock(stopped.before.endedAt!)}',
            offerNewRide: true));
      } else {
        await _startNew();
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _startNew() async {
    await ref.read(screenWakeServiceProvider).enable(ScreenWakeService.ownerRecording);
    ref.read(rideControllerProvider.notifier).reset();
    // The ride stopped last can't be continued any more.
    unawaited(settleStoppedRide(force: true));
    final battery = await ref.read(batteryServiceProvider).level();
    final bikeProfileId = ref.read(bikeProfilesProvider).activeId;
    _trackId = await ref.read(appDatabaseProvider).createTrack(
          DateTime.now(),
          batteryStartPercent: battery,
          bikeProfileId: bikeProfileId,
        );
    await ref.read(recordingForegroundServiceProvider).start();
    // Ride starting/resuming: re-arm the bounded direct-connect retry window so
    // a sensor that wasn't ready at app launch (just mounted / waking on the
    // bike) gets picked up now, without the user tapping.
    await ref.read(sensorServiceProvider).retryConnections();
    state = true;
  }

  /// The ride stopped last, with when its last point was recorded, if a
  /// manual start now should continue it.
  Future<({Track before, DateTime lastPointAt})?> _continuableRide() async {
    final window = ref.read(settingsProvider).continueRideWindow;
    if (window == null) return null;
    final db = ref.read(appDatabaseProvider);
    final id = int.tryParse(await db.meta(lastStoppedRideKey) ?? '');
    final track = id == null ? null : await db.track(id);
    final stoppedAt = track?.endedAt;
    if (track == null || stoppedAt == null || track.deletedAt != null) {
      return null;
    }
    // Too long ago: no need to wait for a fix to know.
    if (DateTime.now().difference(stoppedAt) > window) return null;
    final last = await db.lastPoint(track.id);
    if (last == null) return null;
    final here = await _currentFix();
    final resume = shouldContinueRide(
      stoppedAt: stoppedAt,
      lastLatitude: last.latitude,
      lastLongitude: last.longitude,
      here: here,
      now: DateTime.now(),
      window: window,
    );
    return resume ? (before: track, lastPointAt: last.time) : null;
  }

  /// The latest fix if it is current (`isCurrentFix`), else the next current
  /// one within [continueFixWaitProvider], else null.
  Future<GeoSample?> _currentFix() async {
    final last = ref.read(rideControllerProvider.notifier).lastFix;
    if (last != null && isCurrentFix(last, DateTime.now())) return last;
    final found = Completer<GeoSample?>();
    final sub = ref.read(locationServiceProvider).positions().listen(
      (s) {
        if (!found.isCompleted && isCurrentFix(s, DateTime.now())) {
          found.complete(s);
        }
      },
      onError: (Object _) {},
    );
    final timeout = Timer(ref.read(continueFixWaitProvider), () {
      if (!found.isCompleted) found.complete(null);
    });
    try {
      return await found.future;
    } finally {
      timeout.cancel();
      await sub.cancel();
    }
  }

  /// Undoes a continuation (the "New ride" action of its notice): the
  /// continued ride is put back the way it was stopped — the points recorded
  /// since are dropped, they were seconds at the same place — and a new ride
  /// starts instead.
  Future<void> startNewRideInstead() async {
    final continued = _continued;
    final before = continued?.before;
    if (!state || continued == null || _trackId != before!.id) return;
    _continued = null;
    state = false;
    _trackId = null;
    final db = ref.read(appDatabaseProvider);
    await db.deletePointsAfter(before.id, continued.lastPointAt);
    await db.finalizeTrack(
      before.id,
      endedAt: before.endedAt!,
      distanceMeters: before.distanceMeters,
      durationSeconds: before.durationSeconds,
      avgSpeedMps: before.avgSpeedMps,
      maxSpeedMps: before.maxSpeedMps,
      batteryEndPercent: before.batteryEndPercent,
    );
    await _startNew();
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
    _confirm(RideFeedback.bikeProfileChanged);
    await setBikeProfile(next.id);
  }

  /// Resumes recording into an existing, interrupted ride — continues appending
  /// to the same track, its stats carried over.
  Future<void> resume(int trackId) async {
    if (state || _starting) return;
    // See start(): the gate is told before anything that can pause the activity.
    await ref.read(locationPowerControlProvider).setRecordingActive(true);
    await _resumeInto(trackId);
  }

  /// Records into [trackId] again, open until the next [stop] (see
  /// [AppDatabase.reopenTrack]).
  Future<void> _resumeInto(int trackId) async {
    await ref.read(screenWakeServiceProvider).enable(ScreenWakeService.ownerRecording);
    final db = ref.read(appDatabaseProvider);
    await db.reopenTrack(trackId);
    final points = await db.pointsFor(trackId);
    final bike = (await db.track(trackId))?.bikeProfileId;
    ref
        .read(rideControllerProvider.notifier)
        .resumeFrom(points, ref.read(bikeSettingsLookupProvider)(bike));
    _trackId = trackId;
    await ref.read(recordingForegroundServiceProvider).start();
    // Ride starting/resuming: re-arm the bounded direct-connect retry window so
    // a sensor that wasn't ready at app launch (just mounted / waking on the
    // bike) gets picked up now, without the user tapping.
    await ref.read(sensorServiceProvider).retryConnections();
    state = true;
  }

  Future<void> stop() async {
    if (!state) return;
    state = false; // stop recording points before finalising
    _confirm(RideFeedback.stopped);
    final id = _trackId;
    _trackId = null;
    _continued = null;
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
      // The ride a manual start may continue; Apple Health gets it once it
      // can't be continued any more.
      await ref.read(appDatabaseProvider).setMeta(lastStoppedRideKey, '$id');
      unawaited(settleStoppedRide());
    }
    await ref.read(recordingForegroundServiceProvider).stop();
    // No ride: the GPS request may now be dropped whenever the app goes to the
    // background (it stays on while the app is in the foreground).
    await ref.read(locationPowerControlProvider).setRecordingActive(false);
    await ref.read(screenWakeServiceProvider).disable(ScreenWakeService.ownerRecording);
  }

  /// Saves the ride stopped last to Apple Health (if that's switched on) once
  /// it can't be continued any more — or now, with [force] (a new ride has
  /// started). Until then it schedules itself for when the "Continue a
  /// stopped ride" window ends: a workout can't be extended afterwards, and
  /// Strava imports it from Health right away, so saving at the stop would
  /// leave a continued ride's first part as a ride of its own. Also run at
  /// launch and whenever the app comes back to the foreground
  /// (`stoppedRideSettlerProvider`): iOS suspends the app, so the timer alone
  /// may fire late or never. Unawaited by callers and never throwing.
  Future<void> settleStoppedRide({bool force = false}) async {
    _healthSave?.cancel();
    _healthSave = null;
    try {
      final db = ref.read(appDatabaseProvider);
      final id = int.tryParse(await db.meta(lastStoppedRideKey) ?? '');
      if (id == null) return;
      if (state && _trackId == id) return; // continued: settled at its stop
      final endedAt = (await db.track(id))?.endedAt;
      final window = ref.read(settingsProvider).continueRideWindow;
      if (!force && endedAt != null && window != null) {
        final left = endedAt.add(window).difference(DateTime.now());
        if (left > Duration.zero) {
          _healthSave = Timer(left, () => unawaited(settleStoppedRide()));
          return;
        }
      }
      if (!await ref.read(appleHealthExporterProvider).saveIfEnabled(id)) {
        return; // tried and failed: again next time
      }
      if (await db.meta(lastStoppedRideKey) == '$id') {
        await db.clearMeta(lastStoppedRideKey);
      }
    } on Object catch (e) {
      debugPrint('settleStoppedRide: $e');
    }
  }

  /// Persists one sample to the current ride (no-op when not recording).
  Future<void> recordPoint(
    GeoSample sample,
    SensorSnapshot? snapshot,
    double speedMps,
    bool speedFromSensor,
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
            speedFromSensor: Value(speedFromSensor),
          ),
        );
  }

  /// The on-screen button: a manual start or a stop.
  Future<void> toggle() => state ? stop() : start(manual: true);
}

/// Live ride metrics derived from the location stream.
final rideControllerProvider =
    NotifierProvider<RideController, RideMetrics>(RideController.new);

class RideController extends Notifier<RideMetrics> {
  final RideMetricsAccumulator _accumulator = RideMetricsAccumulator();
  // The ride's climb and profile; the shown height runs whether or not a
  // ride records.
  final RideElevation _elevation = RideElevation();
  final AltitudeSmoother _altitude = AltitudeSmoother();
  final SpeedFusion _fusion = SpeedFusion();
  double _maxSpeedMps = 0;
  SensorSnapshot? _latestSnapshot;
  StreamSubscription<GeoSample>? _subscription;
  GeoSample? _lastFix;

  /// The latest fix, whatever its accuracy, or null before the first.
  GeoSample? get lastFix => _lastFix;

  @override
  RideMetrics build() {
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
    _lastFix = sample;
    // Only a recording ride (or a battery test's simulated one) accumulates
    // time/distance/avg/max. When idle we still show the live current speed,
    // but the ride totals stay at zero so e.g. the timer does not run before
    // the rider taps Start.
    final altitude = sample.altitudeMeters;
    // An inaccurate fix's height is no better than its position.
    if (altitude != null && isAccurateEnough(sample)) _altitude.add(altitude);
    if (!_accumulating) {
      final gps = (sample.speedMps != null && sample.speedMps! >= 0)
          ? sample.speedMps!
          : 0.0;
      _fusion.updateGps(gps);
      final now = DateTime.now();
      state = RideMetrics.zero().copyWith(
          currentSpeedMps: _fusion.fused(now),
          speedFromSensor: _fusion.isUsingBle(now),
          elevationMeters: _altitude.value);
      return;
    }
    // A fix too inaccurate to record (typically while standing still, when
    // the chip's estimate drifts past 10 m) still updates the displayed speed,
    // but never the ride's distance/time/max or its saved points.
    if (!isAccurateEnough(sample)) {
      if (sample.speedMps != null && sample.speedMps! >= 0) {
        _fusion.updateGps(sample.speedMps!);
      }
      final now = DateTime.now();
      state = state.copyWith(
          currentSpeedMps: _fusion.fused(now),
          speedFromSensor: _fusion.isUsingBle(now));
      return;
    }
    // The active bike's auto-pause, read per fix so an edit or a bike switch
    // (also mid-ride: the ride's bike changed) applies from the next one. Not
    // a ref.listen: that is paused while another screen covers the home
    // screen, the only thing keeping this provider listened to.
    _applyAutoPause(ref.read(activeBikeSettingsProvider));
    final metrics = _accumulator.add(sample);
    _fusion.updateGps(metrics.currentSpeedMps);
    final now = DateTime.now();
    final fused = _fusedSpeed(now);
    final fromSensor = _fusion.isUsingBle(now);
    // The speed the point is saved with, so the saved ride's climb matches.
    _elevation.add(altitude, metrics.distanceMeters, fused);
    state = metrics.copyWith(
        currentSpeedMps: fused,
        maxSpeedMps: _maxSpeedMps,
        speedFromSensor: fromSensor,
        elevationMeters: _altitude.value,
        climbMeters: _elevation.climbMeters,
        elevationProfile: _elevation.profile);
    // A battery test's simulated ride is never saved as a ride (it writes its
    // points to its own scratch database).
    if (!ref.read(recordingProvider)) return;
    unawaited(ref
        .read(recordingProvider.notifier)
        .recordPoint(sample, _latestSnapshot, fused, fromSensor));
  }

  /// Ride totals run while a ride records, and during a battery test so its
  /// DIST/AVG/MAX work (and cost) like a ride's.
  bool get _accumulating =>
      ref.read(recordingProvider) || ref.read(simulatedRideProvider) != null;

  void _onSnapshot(SensorSnapshot snapshot) {
    _latestSnapshot = snapshot;
    final wheelSpeed = snapshot.wheelSpeedMps;
    if (wheelSpeed == null) return;
    final now = DateTime.now();
    _fusion.updateBle(wheelSpeed, now);
    // When idle, show live speed only; while recording, also track the max.
    if (!_accumulating) {
      state = RideMetrics.zero().copyWith(
          currentSpeedMps: _fusion.fused(now),
          speedFromSensor: _fusion.isUsingBle(now),
          elevationMeters: _altitude.value);
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
  /// [bike] is the settings of the bike the ride was recorded on.
  void resumeFrom(List<TrackPoint> points, BikeSettings bike) {
    _elevation.reset();
    final m = computeStatsFromPoints(points, bike, elevation: _elevation);
    _maxSpeedMps = m.maxSpeedMps;
    _accumulator.resumeWith(
      distanceMeters: m.distanceMeters,
      movingMillis: m.elapsed.inMilliseconds,
      maxSpeedMps: m.maxSpeedMps,
    );
    state = m.copyWith(currentSpeedMps: 0, speedFromSensor: false);
  }

  void _applyAutoPause(BikeSettings s) {
    _accumulator.autoPauseEnabled = s.autoPauseEnabled;
    _accumulator.autoPauseThresholdMps = s.autoPauseThresholdMps;
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
    _elevation.reset();
    _maxSpeedMps = 0;
    state = RideMetrics.zero().copyWith(elevationMeters: _altitude.value);
  }
}

/// Thin read-only view the dashboard watches. Overriding this with a fixed
/// value in widget tests avoids touching the location stream entirely.
final rideMetricsProvider = Provider<RideMetrics>(
  (ref) => ref.watch(rideControllerProvider),
);
