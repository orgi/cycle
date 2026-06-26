import 'sensor_data.dart';

/// Derives wheel speed and crank cadence from consecutive CSC measurements.
///
/// CSC reports *cumulative* revolution counters plus the "last event time" of
/// the most recent revolution (in 1/1024 s units). Speed/cadence come from the
/// deltas between two measurements, handling counter/timer rollover and
/// coasting (no new revolutions → zero).
class CscCalculator {
  CscCalculator({this.wheelCircumferenceMeters = 2.105});

  /// Wheel circumference in metres (default ≈ 700x25c). A rider setting.
  final double wheelCircumferenceMeters;

  static const int _uint16 = 0x10000;
  static const int _uint32 = 0x100000000;

  int? _prevWheelRevs;
  int? _prevWheelTime;
  int? _prevCrankRevs;
  int? _prevCrankTime;
  int _crankZeroStreak = 0;
  int _wheelZeroStreak = 0;

  /// Empty intervals (no new crank/wheel revolution) tolerated before cadence/
  /// speed drops to 0. A CSC notification at ~1 Hz often lands between events at
  /// normal cadence/speed, so reporting 0 immediately makes the value flicker.
  static const int _crankZeroDropThreshold = 3;
  static const int _wheelZeroDropThreshold = 3;

  CscResult update(CscMeasurement m) {
    double? speed;
    double? cadence;

    if (m.hasWheel) {
      if (_prevWheelRevs != null) {
        final revDelta = _wrap(m.cumulativeWheelRevs! - _prevWheelRevs!, _uint32);
        final dt = _timeDeltaSeconds(_prevWheelTime!, m.lastWheelEventTime!);
        if (revDelta == 0) {
          // Hold (null → consumer keeps the last value) through brief gaps —
          // a notification between wheel events at low/steady speed otherwise
          // flickers to 0; only drop to 0 once the wheel has clearly stopped.
          _wheelZeroStreak++;
          speed = _wheelZeroStreak >= _wheelZeroDropThreshold ? 0.0 : null;
        } else if (dt > 0) {
          speed = revDelta * wheelCircumferenceMeters / dt;
          _wheelZeroStreak = 0;
        }
      }
      _prevWheelRevs = m.cumulativeWheelRevs;
      _prevWheelTime = m.lastWheelEventTime;
    }

    if (m.hasCrank) {
      if (_prevCrankRevs != null) {
        final revDelta = _wrap(m.cumulativeCrankRevs! - _prevCrankRevs!, _uint16);
        final dt = _timeDeltaSeconds(_prevCrankTime!, m.lastCrankEventTime!);
        if (revDelta == 0) {
          // Hold (return null → consumer keeps the last value) through brief
          // gaps; only drop to 0 once pedalling has clearly stopped.
          _crankZeroStreak++;
          cadence = _crankZeroStreak >= _crankZeroDropThreshold ? 0.0 : null;
        } else if (dt > 0) {
          cadence = revDelta / dt * 60.0;
          _crankZeroStreak = 0;
        }
      }
      _prevCrankRevs = m.cumulativeCrankRevs;
      _prevCrankTime = m.lastCrankEventTime;
    }

    return CscResult(speedMetersPerSecond: speed, cadenceRpm: cadence);
  }

  void reset() {
    _prevWheelRevs = null;
    _prevWheelTime = null;
    _prevCrankRevs = null;
    _prevCrankTime = null;
    _crankZeroStreak = 0;
    _wheelZeroStreak = 0;
  }

  int _wrap(int delta, int modulus) => delta < 0 ? delta + modulus : delta;

  /// Event-time delta in seconds (timer is uint16 in 1/1024 s units).
  double _timeDeltaSeconds(int prev, int now) =>
      _wrap(now - prev, _uint16) / 1024.0;
}
