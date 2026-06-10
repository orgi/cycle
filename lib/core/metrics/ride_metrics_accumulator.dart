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

  /// Ignore implausibly large jumps between samples (e.g. GPS teleports) so a
  /// single bad fix does not corrupt total distance. 200 m between two
  /// consecutive fixes at typical 1 Hz cycling cadence is already generous.
  static const double _maxLegMeters = 200;

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
  }

  double _gpsSpeedOrZero(GeoSample s) =>
      (s.speedMps != null && s.speedMps! >= 0) ? s.speedMps! : 0.0;
}
