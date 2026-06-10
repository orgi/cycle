import 'package:cycle/core/metrics/ride_metrics_accumulator.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:flutter_test/flutter_test.dart';

GeoSample sampleAt(
  DateTime t, {
  double lat = 0,
  double lon = 0,
  double? speed,
}) =>
    GeoSample(latitude: lat, longitude: lon, time: t, speedMps: speed);

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

  test('first sample has zero distance and zero elapsed', () {
    final acc = RideMetricsAccumulator();
    final m = acc.add(sampleAt(t0, speed: 5));
    expect(m.distanceMeters, 0);
    expect(m.elapsed, Duration.zero);
    expect(m.currentSpeedMps, 5);
    expect(m.maxSpeedMps, 5);
    expect(m.avgSpeedMps, 0); // no elapsed time yet
  });

  test('accumulates distance and computes average over elapsed time', () {
    final acc = RideMetricsAccumulator();
    acc.add(sampleAt(t0, lat: 0, lon: 0, speed: 5));
    // ~100 m east, 10 s later, GPS reports 8 m/s.
    final m = acc.add(
      sampleAt(t0.add(const Duration(seconds: 10)),
          lat: 0, lon: 0.00089932, speed: 8),
    );
    expect(m.distanceMeters, closeTo(100, 1));
    expect(m.currentSpeedMps, 8); // prefers GPS-reported speed
    expect(m.maxSpeedMps, 8);
    expect(m.avgSpeedMps, closeTo(10, 0.2)); // 100 m / 10 s
  });

  test('falls back to distance/time when GPS speed is missing', () {
    final acc = RideMetricsAccumulator();
    acc.add(sampleAt(t0, lat: 0, lon: 0));
    final m = acc.add(
      sampleAt(t0.add(const Duration(seconds: 10)), lat: 0, lon: 0.00089932),
    );
    expect(m.currentSpeedMps, closeTo(10, 0.2)); // 100 m / 10 s
  });

  test('ignores implausible GPS jumps when totalling distance', () {
    final acc = RideMetricsAccumulator();
    acc.add(sampleAt(t0, lat: 0, lon: 0));
    // ~1000 km jump between two consecutive fixes — discard the leg.
    final m = acc.add(
      sampleAt(t0.add(const Duration(seconds: 1)), lat: 9, lon: 0),
    );
    expect(m.distanceMeters, 0);
  });

  test('reset clears all running totals', () {
    final acc = RideMetricsAccumulator();
    acc.add(sampleAt(t0, lat: 0, lon: 0, speed: 5));
    acc.add(sampleAt(t0.add(const Duration(seconds: 10)),
        lat: 0, lon: 0.00089932, speed: 8));
    acc.reset();
    final m = acc.add(sampleAt(t0.add(const Duration(minutes: 1)), speed: 3));
    expect(m.distanceMeters, 0);
    expect(m.elapsed, Duration.zero);
    expect(m.maxSpeedMps, 3);
  });
}
