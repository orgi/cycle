import '../models/geo_sample.dart';
import '../models/ride_metrics.dart';
import '../utils/geo.dart';

/// Folds a sequence of [GeoSample]s into running [RideMetrics].
///
/// Pure Dart and stateful-by-design: feed it each new sample with [add] and it
/// returns the updated snapshot. Lives outside the Riverpod/UI layers so the
/// distance/speed maths can be unit-tested in isolation.
class RideMetricsAccumulator {
  RideMetricsAccumulator({
    this.autoPauseEnabled = false,
    this.autoPauseThresholdMps = 5.0 / 3.6, // 5 km/h
  });

  /// When enabled, samples below [autoPauseThresholdMps] don't add to moving
  /// time or distance (so red lights / breaks are excluded from time + average).
  bool autoPauseEnabled;
  double autoPauseThresholdMps;

  GeoSample? _last;
  DateTime? _startTime;
  double _distanceMeters = 0;
  double _maxSpeedMps = 0;
  int _movingMillis = 0;
  bool _paused = false;
  final List<GeoSample> _window = [];

  /// Whether the ride is currently auto-paused (last sample below threshold).
  bool get paused => _paused;

  // Rolling-window speed fallback. The GPS chip's reported velocity regresses
  // toward zero when the signal is poor (under tree cover), so it reads *low*.
  // When accuracy is poor we instead use the speed implied by how far we've
  // actually moved over the last few seconds, which keeps tracking as long as
  // the position advances. (Tunable — these are field-test knobs.)
  static const double _windowSeconds = 5.0;
  static const double _windowMinMeters = 8.0; // below this = stopped / jitter
  static const double _poorAccuracyMeters = 18.0; // canopy / weak signal
  static const double _maxPlausibleMps =
      30.0; // reject GPS teleports (108 km/h)

  RideMetrics add(GeoSample sample) {
    _startTime ??= sample.time;

    var current = _gpsSpeedOrZero(sample);
    final last = _last;
    var leg = 0.0;
    var dtSeconds = 0.0;
    if (last != null) {
      leg = haversineMeters(
        last.latitude,
        last.longitude,
        sample.latitude,
        sample.longitude,
      );
      dtSeconds = sample.time.difference(last.time).inMilliseconds / 1000.0;
      // Prefer the GPS-reported speed; fall back to distance/time.
      if (sample.speedMps == null || sample.speedMps! < 0) {
        current = dtSeconds > 0 ? leg / dtSeconds : 0.0;
      }
    }

    // When the fix is inaccurate (typically under tree cover) the chip speed is
    // unreliable and reads low; use the larger of it and the position-window
    // speed so we don't under-report while actually moving. With a good fix we
    // keep the chip value (responsive, and correct when braking on open roads).
    final windowed = _windowedSpeed(sample);
    if (windowed != null &&
        sample.accuracyMeters != null &&
        sample.accuracyMeters! > _poorAccuracyMeters &&
        windowed > current) {
      current = windowed;
    }

    if (current > _maxSpeedMps) {
      _maxSpeedMps = current;
    }

    // Auto-pause: below the threshold, don't grow moving time or distance, so a
    // stop at a light / a break is excluded from the timer and the average.
    // (max speed still tracks the true peak above.)
    _paused = autoPauseEnabled && current < autoPauseThresholdMps;
    if (last != null && !_paused) {
      // Integrate *speed* over time rather than differencing raw positions.
      // Position-differencing is what causes the "coastline paradox"
      // overcount: GPS jitter adds spurious zig-zag length on *every* leg,
      // not just while stationary, so a minimum-leg-distance gate (tried and
      // reverted here) does nothing once real per-sample movement already
      // clears it — which is the normal case for a continuously-moving bike
      // ride (field data: Cycle read ~5% long vs. a reference recording of
      // the same ride even with no individual bad/spike fixes). `current`
      // (the GPS chip's own Doppler-measured speed, falling back to the
      // position-window speed under poor accuracy) doesn't have that bias:
      // Doppler velocity is measured directly from the carrier signal, not
      // by differencing two noisy fixes a second apart. When no GPS speed is
      // reported at all, `current` above already fell back to `leg /
      // dtSeconds`, so `current * dtSeconds` reduces to the raw leg in that
      // case — no separate fallback branch needed here.
      _distanceMeters += current * dtSeconds;
      _movingMillis += (dtSeconds * 1000).round();
    }
    _last = sample;

    final elapsed = Duration(milliseconds: _movingMillis);
    final elapsedSeconds = _movingMillis / 1000.0;
    final avg = elapsedSeconds > 0 ? _distanceMeters / elapsedSeconds : 0.0;

    return RideMetrics(
      distanceMeters: _distanceMeters,
      currentSpeedMps: current,
      avgSpeedMps: avg,
      maxSpeedMps: _maxSpeedMps,
      elapsed: elapsed,
      paused: _paused,
    );
  }

  /// Resets all running totals so the accumulator can be reused for a new ride.
  void reset() {
    _last = null;
    _startTime = null;
    _distanceMeters = 0;
    _maxSpeedMps = 0;
    _movingMillis = 0;
    _paused = false;
    _window.clear();
  }

  /// Resumes an interrupted ride: seed the running totals from the points that
  /// were already recorded, and start a **fresh leg** (`_last = null`) so the
  /// dead-time gap while the app was gone isn't counted as distance or time.
  void resumeWith({
    required double distanceMeters,
    required int movingMillis,
    required double maxSpeedMps,
  }) {
    _distanceMeters = distanceMeters;
    _movingMillis = movingMillis;
    _maxSpeedMps = maxSpeedMps;
    _last = null;
    _startTime = null;
    _paused = false;
    _window.clear();
  }

  double _gpsSpeedOrZero(GeoSample s) =>
      (s.speedMps != null && s.speedMps! >= 0) ? s.speedMps! : 0.0;

  /// Speed (m/s) from straight-line displacement over the last [_windowSeconds],
  /// or `null` when there isn't enough data / the result is implausible. Uses
  /// displacement (start→now), not summed legs, so per-fix jitter cancels out
  /// and a stationary rider doesn't accumulate phantom speed.
  double? _windowedSpeed(GeoSample sample) {
    _window.add(sample);
    while (_window.length > 2 &&
        sample.time.difference(_window.first.time).inMilliseconds / 1000.0 >
            _windowSeconds) {
      _window.removeAt(0);
    }
    if (_window.length < 2) return null;
    final first = _window.first;
    final seconds = sample.time.difference(first.time).inMilliseconds / 1000.0;
    if (seconds <= 0) return null;
    final disp = haversineMeters(
      first.latitude,
      first.longitude,
      sample.latitude,
      sample.longitude,
    );
    if (disp < _windowMinMeters) return 0.0; // not really moving
    final speed = disp / seconds;
    if (speed > _maxPlausibleMps) return null; // teleport / bad fix
    return speed;
  }
}
