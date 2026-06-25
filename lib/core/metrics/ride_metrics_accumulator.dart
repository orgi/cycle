import '../models/geo_sample.dart';
import '../models/ride_metrics.dart';
import '../utils/geo.dart';

/// Folds a sequence of [GeoSample]s into running [RideMetrics].
///
/// Pure Dart and stateful-by-design: feed it each new sample with [add] and it
/// returns the updated snapshot. Lives outside the Riverpod/UI layers so the
/// distance/speed maths can be unit-tested in isolation.
class RideMetricsAccumulator {
  GeoSample? _last;
  DateTime? _startTime;
  double _distanceMeters = 0;
  double _maxSpeedMps = 0;
  final List<GeoSample> _window = [];

  /// Ignore implausibly large jumps between samples (e.g. GPS teleports) so a
  /// single bad fix does not corrupt total distance. 200 m between two
  /// consecutive fixes at typical 1 Hz cycling cadence is already generous.
  static const double _maxLegMeters = 200;

  // Rolling-window speed fallback. The GPS chip's reported velocity regresses
  // toward zero when the signal is poor (under tree cover), so it reads *low*.
  // When accuracy is poor we instead use the speed implied by how far we've
  // actually moved over the last few seconds, which keeps tracking as long as
  // the position advances. (Tunable — these are field-test knobs.)
  static const double _windowSeconds = 5.0;
  static const double _windowMinMeters = 8.0; // below this = stopped / jitter
  static const double _poorAccuracyMeters = 18.0; // canopy / weak signal
  static const double _maxPlausibleMps = 30.0; // reject GPS teleports (108 km/h)

  RideMetrics add(GeoSample sample) {
    _startTime ??= sample.time;

    var current = _gpsSpeedOrZero(sample);
    final last = _last;
    if (last != null) {
      final leg = haversineMeters(
        last.latitude,
        last.longitude,
        sample.latitude,
        sample.longitude,
      );
      if (leg <= _maxLegMeters) {
        _distanceMeters += leg;
      }
      // Prefer the GPS-reported speed; fall back to distance/time.
      if (sample.speedMps == null || sample.speedMps! < 0) {
        final dtSeconds =
            sample.time.difference(last.time).inMilliseconds / 1000.0;
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
    _last = sample;

    final elapsed = sample.time.difference(_startTime!);
    final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
    final avg = elapsedSeconds > 0 ? _distanceMeters / elapsedSeconds : 0.0;

    return RideMetrics(
      distanceMeters: _distanceMeters,
      currentSpeedMps: current,
      avgSpeedMps: avg,
      maxSpeedMps: _maxSpeedMps,
      elapsed: elapsed,
    );
  }

  /// Resets all running totals so the accumulator can be reused for a new ride.
  void reset() {
    _last = null;
    _startTime = null;
    _distanceMeters = 0;
    _maxSpeedMps = 0;
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
        first.latitude, first.longitude, sample.latitude, sample.longitude);
    if (disp < _windowMinMeters) return 0.0; // not really moving
    final speed = disp / seconds;
    if (speed > _maxPlausibleMps) return null; // teleport / bad fix
    return speed;
  }
}
