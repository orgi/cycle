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

  test('a brief gap with no new crank rev holds (null), not 0 flicker', () {
    final calc = CscCalculator();
    calc.update(const CscMeasurement(
        cumulativeCrankRevs: 10, lastCrankEventTime: 1024));
    calc.update(const CscMeasurement(
        cumulativeCrankRevs: 11, lastCrankEventTime: 2048)); // 60 rpm
    // Notification with no new crank revolution → hold (null), not 0.
    final r1 = calc.update(const CscMeasurement(
        cumulativeCrankRevs: 11, lastCrankEventTime: 2048));
    expect(r1.cadenceRpm, isNull);
    final r2 = calc.update(const CscMeasurement(
        cumulativeCrankRevs: 11, lastCrankEventTime: 2048));
    expect(r2.cadenceRpm, isNull);
    // Sustained gap → cadence finally drops to 0 (rider stopped pedalling).
    final r3 = calc.update(const CscMeasurement(
        cumulativeCrankRevs: 11, lastCrankEventTime: 2048));
    expect(r3.cadenceRpm, 0);
  });

  test('a brief gap with no new wheel rev holds (null), not 0 flicker', () {
    final calc = CscCalculator();
    calc.update(const CscMeasurement(
        cumulativeWheelRevs: 100, lastWheelEventTime: 1024));
    // Notifications with no new wheel revolution → hold (null), not 0.
    final r1 = calc.update(const CscMeasurement(
        cumulativeWheelRevs: 100, lastWheelEventTime: 1024));
    expect(r1.speedMetersPerSecond, isNull);
    final r2 = calc.update(const CscMeasurement(
        cumulativeWheelRevs: 100, lastWheelEventTime: 1024));
    expect(r2.speedMetersPerSecond, isNull);
    // Sustained gap → speed finally drops to 0 (wheel stopped).
    final r3 = calc.update(const CscMeasurement(
        cumulativeWheelRevs: 100, lastWheelEventTime: 1024));
    expect(r3.speedMetersPerSecond, 0);
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
