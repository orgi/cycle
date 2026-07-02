import '../models/geo_sample.dart';
import 'geo.dart';

/// Drops GPS "teleport" outliers: a fix that would imply an impossible speed
/// from the last *accepted* position. These spikes come from multipath
/// reflections (common in the evening when a low sun bounces the signal off
/// buildings) and show up as the track darting out and back.
///
/// Crucially it keeps the last **good** sample as the reference, so a dropped
/// spike doesn't poison the next leg — the following real fix is measured across
/// the gap (correct distance) instead of out-and-back to the spike (which both
/// inflates the drawn track and, because the huge legs are rejected while time
/// keeps running, drags the average speed down).
class GpsOutlierFilter {
  GpsOutlierFilter({this.maxSpeedMps = 30.0}); // ~108 km/h — above any real ride

  final double maxSpeedMps;
  GeoSample? _lastGood;

  /// Whether [sample] is a plausible next fix. `true` → keep it (and it becomes
  /// the new reference); `false` → it's an outlier, drop it and keep the
  /// previous good sample as the reference.
  bool accept(GeoSample sample) {
    final prev = _lastGood;
    if (prev == null) {
      _lastGood = sample;
      return true;
    }
    final dtSeconds = sample.time.difference(prev.time).inMilliseconds / 1000.0;
    if (dtSeconds <= 0) {
      // Same/earlier timestamp — can't judge a speed; accept and re-anchor so
      // we never get stuck dropping everything on a clock quirk.
      _lastGood = sample;
      return true;
    }
    final meters = haversineMeters(
        prev.latitude, prev.longitude, sample.latitude, sample.longitude);
    if (meters / dtSeconds > maxSpeedMps) {
      return false; // implausible jump → outlier
    }
    _lastGood = sample;
    return true;
  }

  void reset() => _lastGood = null;
}
