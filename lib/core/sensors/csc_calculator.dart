import 'sensor_data.dart';

/// Derives wheel speed and crank cadence from consecutive CSC measurements.
///
/// CSC reports *cumulative* revolution counters plus the "last event time" of
/// the most recent revolution (in 1/1024 s units). Speed/cadence come from the
/// deltas between two measurements, handling counter/timer rollover.
///
/// A notification can arrive with no new revolution since the last one — even at
/// a steady riding speed, because some sensors notify *faster* than the wheel
/// turns. Reporting 0 in that case makes the value flicker to zero. So when
/// there's no new revolution we **hold** (return null → the consumer keeps the
/// last value) as long as the wheel/crank actually moved within the last few
/// seconds (wall-clock), and only report 0 once it has clearly stopped. The
/// previous version counted empty *notifications*, which broke when the
/// notification rate exceeded the revolution rate.
class CscCalculator {
  CscCalculator({this.wheelCircumferenceMeters = 2.105});

  /// Wheel circumference in metres (default ≈ 700x25c). A rider setting.
  final double wheelCircumferenceMeters;

  static const int _uint16 = 0x10000;
  static const int _uint32 = 0x100000000;

  /// How long after the last real revolution we keep holding the last value
  /// before declaring the wheel/crank stopped (speed/cadence → 0).
  static const Duration _moveHold = Duration(seconds: 3);

  int? _prevWheelRevs;
  int? _prevWheelTime;
  int? _prevCrankRevs;
  int? _prevCrankTime;
  DateTime? _lastWheelMoveAt;
  DateTime? _lastCrankMoveAt;

  /// [now] is injectable for tests; defaults to the wall clock.
  CscResult update(CscMeasurement m, {DateTime? now}) {
    final at = now ?? DateTime.now();
    double? speed;
    double? cadence;

    if (m.hasWheel) {
      if (_prevWheelRevs != null) {
        final revDelta = _wrap(m.cumulativeWheelRevs! - _prevWheelRevs!, _uint32);
        final dt = _timeDeltaSeconds(_prevWheelTime!, m.lastWheelEventTime!);
        if (revDelta == 0) {
          final moved = _lastWheelMoveAt;
          // Hold while it moved recently; only drop to 0 once truly stopped.
          speed = (moved != null && at.difference(moved) < _moveHold) ? null : 0.0;
        } else if (dt > 0) {
          speed = revDelta * wheelCircumferenceMeters / dt;
          _lastWheelMoveAt = at;
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
          final moved = _lastCrankMoveAt;
          cadence =
              (moved != null && at.difference(moved) < _moveHold) ? null : 0.0;
        } else if (dt > 0) {
          cadence = revDelta / dt * 60.0;
          _lastCrankMoveAt = at;
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
    _lastWheelMoveAt = null;
    _lastCrankMoveAt = null;
  }

  int _wrap(int delta, int modulus) => delta < 0 ? delta + modulus : delta;

  /// Event-time delta in seconds (timer is uint16 in 1/1024 s units).
  double _timeDeltaSeconds(int prev, int now) =>
      _wrap(now - prev, _uint16) / 1024.0;
}
