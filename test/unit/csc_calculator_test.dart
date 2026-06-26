import 'package:cycle/core/sensors/csc_calculator.dart';
import 'package:cycle/core/sensors/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first measurement yields no speed/cadence (no baseline)', () {
    final calc = CscCalculator();
    final r = calc.update(const CscMeasurement(
        cumulativeWheelRevs: 100, lastWheelEventTime: 1024));
    expect(r.speedMetersPerSecond, isNull);
  });

  test('wheel speed from one revolution per second', () {
    final calc = CscCalculator(wheelCircumferenceMeters: 2.105);
    calc.update(const CscMeasurement(
        cumulativeWheelRevs: 100, lastWheelEventTime: 1024));
    // +1 rev, +1024 ticks (=1.0 s)
    final r = calc.update(const CscMeasurement(
        cumulativeWheelRevs: 101, lastWheelEventTime: 2048));
    expect(r.speedMetersPerSecond, closeTo(2.105, 0.001));
  });

  test('crank cadence of 60 rpm', () {
    final calc = CscCalculator();
    calc.update(const CscMeasurement(
        cumulativeCrankRevs: 10, lastCrankEventTime: 1024));
    final r = calc.update(const CscMeasurement(
        cumulativeCrankRevs: 11, lastCrankEventTime: 2048)); // 1 rev / 1 s
    expect(r.cadenceRpm, closeTo(60, 0.001));
  });

  final t = DateTime(2026, 1, 1, 12);

  test('no-rev notifications hold while moving recently, drop to 0 once stopped',
      () {
    final calc = CscCalculator();
    calc.update(
        const CscMeasurement(cumulativeCrankRevs: 10, lastCrankEventTime: 1024),
        now: t);
    calc.update(
        const CscMeasurement(cumulativeCrankRevs: 11, lastCrankEventTime: 2048),
        now: t.add(const Duration(seconds: 1))); // a real rev (60 rpm)
    // No new rev, but the crank moved <3 s ago → hold (null), not 0 — even for
    // several notifications in a row (the bug: this used to flicker to 0).
    for (var i = 2; i <= 5; i++) {
      final r = calc.update(
          const CscMeasurement(
              cumulativeCrankRevs: 11, lastCrankEventTime: 2048),
          now: t.add(Duration(milliseconds: 1000 + i * 300)));
      expect(r.cadenceRpm, isNull, reason: 'still moving at notification $i');
    }
    // >3 s since the last rev → clearly stopped → 0.
    final stopped = calc.update(
        const CscMeasurement(cumulativeCrankRevs: 11, lastCrankEventTime: 2048),
        now: t.add(const Duration(seconds: 5)));
    expect(stopped.cadenceRpm, 0);
  });

  test('wheel speed holds at steady speed (faster notifications than revs)', () {
    final calc = CscCalculator(wheelCircumferenceMeters: 2.0);
    calc.update(
        const CscMeasurement(cumulativeWheelRevs: 100, lastWheelEventTime: 0),
        now: t);
    calc.update(
        const CscMeasurement(cumulativeWheelRevs: 101, lastWheelEventTime: 1024),
        now: t.add(const Duration(seconds: 1))); // a real wheel event
    // Four no-rev notifications within 3 s of the last event → all hold, none 0.
    for (var i = 1; i <= 4; i++) {
      final r = calc.update(
          const CscMeasurement(
              cumulativeWheelRevs: 101, lastWheelEventTime: 1024),
          now: t.add(Duration(milliseconds: 1000 + i * 250)));
      expect(r.speedMetersPerSecond, isNull);
    }
    // Truly stopped (>3 s) → 0.
    final stopped = calc.update(
        const CscMeasurement(cumulativeWheelRevs: 101, lastWheelEventTime: 1024),
        now: t.add(const Duration(seconds: 6)));
    expect(stopped.speedMetersPerSecond, 0);
  });

  test('handles 16-bit event-time rollover', () {
    final calc = CscCalculator(wheelCircumferenceMeters: 2.0);
    calc.update(const CscMeasurement(
        cumulativeWheelRevs: 100, lastWheelEventTime: 65000));
    // time wraps: (1000 - 65000) + 65536 = 1536 ticks = 1.5 s; +3 revs
    final r = calc.update(const CscMeasurement(
        cumulativeWheelRevs: 103, lastWheelEventTime: 1000));
    expect(r.speedMetersPerSecond, closeTo(3 * 2.0 / 1.5, 0.001)); // 4.0 m/s
  });

  test('handles 32-bit wheel-revolution rollover', () {
    final calc = CscCalculator(wheelCircumferenceMeters: 2.0);
    calc.update(CscMeasurement(
        cumulativeWheelRevs: 0xFFFFFFFF, lastWheelEventTime: 1024));
    // +2 revs across the uint32 boundary, +1 s
    final r = calc.update(const CscMeasurement(
        cumulativeWheelRevs: 1, lastWheelEventTime: 2048));
    expect(r.speedMetersPerSecond, closeTo(2 * 2.0 / 1.0, 0.001)); // 4.0 m/s
  });
}
