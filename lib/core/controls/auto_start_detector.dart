import '../models/geo_sample.dart';

/// Decides when to start a ride automatically from GPS speed, so a rider in
/// gloves never has to touch the phone to begin recording.
///
/// Starts once the speed has stayed at or above [startSpeedKmh] for
/// [sustain] (a single jittery fix, or walking/pushing the bike, never
/// qualifies). Stopping stays manual.
///
/// After a ride ends it is **disarmed** until the rider has been nearly
/// stationary (below [rearmBelowKmh]) for [rearmAfter]. Otherwise stopping a
/// ride while still rolling — or rolling off right after pressing Stop at the
/// front door — would instantly start a new one. A fresh detector (app start)
/// is armed.
class AutoStartDetector {
  AutoStartDetector({
    this.startSpeedKmh = 8,
    this.sustain = const Duration(seconds: 5),
    this.rearmBelowKmh = 3,
    this.rearmAfter = const Duration(seconds: 60),
  });

  final double startSpeedKmh;
  final Duration sustain;
  final double rearmBelowKmh;
  final Duration rearmAfter;

  bool _armed = true;
  DateTime? _fastSince;
  DateTime? _slowSince;

  bool get isArmed => _armed;

  /// Feeds one fix; returns true when a ride should be started now.
  bool update(GeoSample sample, {required bool recording}) {
    if (recording) {
      _armed = false;
      _fastSince = null;
      _slowSince = null;
      return false;
    }
    final speed = sample.speedMps;
    if (speed == null || speed < 0) return false;
    final kmh = speed * 3.6;

    if (!_armed) {
      if (kmh < rearmBelowKmh) {
        _slowSince ??= sample.time;
        if (sample.time.difference(_slowSince!) >= rearmAfter) {
          _armed = true;
          _slowSince = null;
        }
      } else {
        _slowSince = null;
      }
      return false;
    }

    if (kmh >= startSpeedKmh) {
      _fastSince ??= sample.time;
      if (sample.time.difference(_fastSince!) >= sustain) {
        _armed = false;
        _fastSince = null;
        return true;
      }
    } else {
      _fastSince = null;
    }
    return false;
  }
}
