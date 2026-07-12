import 'package:cycle/core/metrics/ride_metrics_accumulator.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/models/ride_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

GeoSample sampleAt(
  DateTime t, {
  double lat = 0,
  double lon = 0,
  double? speed,
}) => GeoSample(latitude: lat, longitude: lon, time: t, speedMps: speed);

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
    // Position implies ~10 m/s, but GPS reports 8 m/s — distance is driven by
    // the *reported* speed (Doppler), not the position delta (see below), so
    // it comes out at 8 m/s × 10 s, not the position-implied 100 m.
    final m = acc.add(
      sampleAt(
        t0.add(const Duration(seconds: 10)),
        lat: 0,
        lon: 0.00089932,
        speed: 8,
      ),
    );
    expect(m.distanceMeters, closeTo(80, 1));
    expect(m.currentSpeedMps, 8); // prefers GPS-reported speed
    expect(m.maxSpeedMps, 8);
    expect(m.avgSpeedMps, closeTo(8, 0.2)); // 80 m / 10 s
  });

  test('falls back to distance/time when GPS speed is missing', () {
    final acc = RideMetricsAccumulator();
    acc.add(sampleAt(t0, lat: 0, lon: 0));
    final m = acc.add(
      sampleAt(t0.add(const Duration(seconds: 10)), lat: 0, lon: 0.00089932),
    );
    expect(m.currentSpeedMps, closeTo(10, 0.2)); // 100 m / 10 s
  });

  test('adds every leg\'s distance — bad-fix rejection lives upstream now', () {
    // The accumulator itself no longer second-guesses individual legs (no
    // flat distance cap): field data showed it discarded genuine large-but-
    // plausible legs (e.g. after a real GPS gap of tens of seconds) as often
    // as it caught anything wrong. Rejecting bad fixes is now the live
    // accuracy filter's job (`gps_accuracy_filter.dart`), upstream of this
    // accumulator — so by the time a sample reaches `add`, it's assumed kept.
    final acc = RideMetricsAccumulator();
    acc.add(sampleAt(t0, lat: 0, lon: 0));
    final m = acc.add(
      sampleAt(t0.add(const Duration(seconds: 1)), lat: 9, lon: 0),
    );
    expect(m.distanceMeters, greaterThan(0));
  });

  test('GPS position jitter while stationary does not accumulate distance', () {
    // A stationary rider's raw fixes wobble a few metres around the true
    // position by noise alone — but the GPS chip's own Doppler-measured
    // speed correctly reads ~0 regardless (it isn't derived from the noisy
    // position fixes), so integrating *that* over time keeps distance at 0.
    final acc = RideMetricsAccumulator();
    final jitterLon = 0.000018; // ~2 m east at the equator
    acc.add(sampleAt(t0, lat: 0, lon: 0, speed: 0));
    acc.add(
      sampleAt(
        t0.add(const Duration(seconds: 1)),
        lat: 0,
        lon: jitterLon,
        speed: 0,
      ),
    );
    acc.add(
      sampleAt(t0.add(const Duration(seconds: 2)), lat: 0, lon: 0, speed: 0),
    );
    final m = acc.add(
      sampleAt(
        t0.add(const Duration(seconds: 3)),
        lat: 0,
        lon: jitterLon,
        speed: 0,
      ),
    );
    expect(m.distanceMeters, 0);
  });

  test(
    'GPS position jitter while riding at speed does not inflate distance',
    () {
      // The bug this guards against: summing the haversine leg between every
      // raw 1 Hz fix overcounts distance from jitter alone, even while
      // genuinely moving (not just when stationary) — a naive fix that only
      // gates *tiny* legs does nothing here, since real per-sample movement at
      // riding speed already clears any sane gate. Distance must instead track
      // the reported (Doppler) speed, which is unaffected by the position
      // noise laid on top of it, so it comes out to exactly speed × time even
      // though the raw positions zig-zag.
      final acc = RideMetricsAccumulator();
      const forwardStep = 0.000045; // ~5 m east at the equator per second
      const jitter = 0.00003; // ~3 m north/south jitter, alternating
      late RideMetrics m;
      for (var i = 0; i <= 9; i++) {
        m = acc.add(
          sampleAt(
            t0.add(Duration(seconds: i)),
            lat: (i.isEven ? jitter : -jitter),
            lon: forwardStep * i,
            speed: 5,
          ),
        );
      }
      expect(m.distanceMeters, closeTo(5 * 9, 0.5)); // speed × time, not more
    },
  );

  test('slow real movement is captured in full, with no delay', () {
    // Nothing gates or defers a leg based on its size any more — every
    // sample's reported speed counts immediately, so genuinely slow riding
    // (well under typical GPS jitter magnitude) isn't shortchanged.
    final acc = RideMetricsAccumulator();
    late RideMetrics m;
    for (var i = 0; i <= 9; i++) {
      m = acc.add(sampleAt(t0.add(Duration(seconds: i)), speed: 1.0));
    }
    expect(m.distanceMeters, closeTo(1.0 * 9, 0.01));
  });

  test('reset clears all running totals', () {
    final acc = RideMetricsAccumulator();
    acc.add(sampleAt(t0, lat: 0, lon: 0, speed: 5));
    acc.add(
      sampleAt(
        t0.add(const Duration(seconds: 10)),
        lat: 0,
        lon: 0.00089932,
        speed: 8,
      ),
    );
    acc.reset();
    final m = acc.add(sampleAt(t0.add(const Duration(minutes: 1)), speed: 3));
    expect(m.distanceMeters, 0);
    expect(m.elapsed, Duration.zero);
    expect(m.maxSpeedMps, 3);
  });

  // Rolling-window speed fallback for poor-accuracy fixes (e.g. under trees).
  GeoSample acc(DateTime t, double lon, double speed, double accuracy) =>
      GeoSample(
        latitude: 0,
        longitude: lon,
        time: t,
        speedMps: speed,
        accuracyMeters: accuracy,
      );
  const step = 0.00008983; // ~10 m east at the equator per 1 s ⇒ 10 m/s

  test(
    'poor accuracy: uses the position-window speed when the chip reads low',
    () {
      final a = RideMetricsAccumulator();
      late RideMetrics m;
      for (var i = 0; i <= 6; i++) {
        // chip insists 2 m/s, but we are really moving ~10 m/s, accuracy 30 m.
        m = a.add(acc(t0.add(Duration(seconds: i)), step * i, 2, 30));
      }
      expect(m.currentSpeedMps, greaterThan(8));
    },
  );

  test('good accuracy: keeps the chip speed (window not applied)', () {
    final a = RideMetricsAccumulator();
    late RideMetrics m;
    for (var i = 0; i <= 6; i++) {
      m = a.add(acc(t0.add(Duration(seconds: i)), step * i, 2, 5));
    }
    expect(m.currentSpeedMps, closeTo(2, 0.5));
  });

  test('poor accuracy but stationary: no phantom speed', () {
    final a = RideMetricsAccumulator();
    late RideMetrics m;
    for (var i = 0; i <= 6; i++) {
      m = a.add(acc(t0.add(Duration(seconds: i)), 0, 0, 30));
    }
    expect(m.currentSpeedMps, 0);
  });

  group('auto-pause', () {
    const east100m = 0.00089932; // ~100 m east at the equator

    test('excludes below-threshold time and distance from moving totals', () {
      final a = RideMetricsAccumulator(autoPauseEnabled: true); // 5 km/h
      a.add(sampleAt(t0, lon: 0, speed: 10));
      // +10 s, moving fast (10 m/s) → accrues 100 m
      final m1 = a.add(
        sampleAt(t0.add(const Duration(seconds: 10)), lon: east100m, speed: 10),
      );
      expect(m1.paused, isFalse);
      expect(m1.distanceMeters, closeTo(100, 1));
      expect(m1.elapsed, const Duration(seconds: 10));

      // +10 s, stopped at a light (speed 0) → paused, no accrual
      final m2 = a.add(
        sampleAt(t0.add(const Duration(seconds: 20)), lon: east100m, speed: 0),
      );
      expect(m2.paused, isTrue);
      expect(m2.distanceMeters, closeTo(100, 1)); // unchanged
      expect(m2.elapsed, const Duration(seconds: 10)); // timer frozen

      // +10 s, moving again (10 m/s) → resumes, another 100 m
      final m3 = a.add(
        sampleAt(
          t0.add(const Duration(seconds: 30)),
          lon: east100m * 2,
          speed: 10,
        ),
      );
      expect(m3.paused, isFalse);
      expect(m3.distanceMeters, closeTo(200, 1));
      expect(m3.elapsed, const Duration(seconds: 20)); // 10 s stop excluded
      expect(m3.avgSpeedMps, closeTo(10, 0.3)); // 200 m / 20 s moving
    });

    test('disabled: below-threshold samples still count', () {
      final a = RideMetricsAccumulator(autoPauseEnabled: false);
      // Genuinely slow (1 m/s, under the 5 km/h ≈ 1.39 m/s threshold) but
      // auto-pause is off, so it still accrues at that (slow) rate.
      a.add(sampleAt(t0, lon: 0, speed: 1));
      final m = a.add(
        sampleAt(t0.add(const Duration(seconds: 10)), lon: east100m, speed: 1),
      );
      expect(m.paused, isFalse);
      expect(m.distanceMeters, closeTo(10, 0.5));
      expect(m.elapsed, const Duration(seconds: 10));
    });

    test('reset clears the paused state', () {
      final a = RideMetricsAccumulator(autoPauseEnabled: true);
      a.add(sampleAt(t0, speed: 0));
      final paused = a.add(
        sampleAt(t0.add(const Duration(seconds: 1)), speed: 0),
      );
      expect(paused.paused, isTrue);
      a.reset();
      expect(a.paused, isFalse);
    });
  });

  test('resumeWith seeds totals and does not count the dead-time gap', () {
    final a = RideMetricsAccumulator()
      ..resumeWith(distanceMeters: 500, movingMillis: 100000, maxSpeedMps: 9);
    // First sample after a long gap only re-anchors — no gap distance/time.
    final m0 = a.add(
      sampleAt(t0.add(const Duration(minutes: 30)), lon: 0.01, speed: 10),
    );
    expect(m0.distanceMeters, 500); // unchanged by the gap
    expect(m0.elapsed, const Duration(milliseconds: 100000));
    // Continuing adds to the carried-over totals.
    final m1 = a.add(
      sampleAt(
        t0.add(const Duration(minutes: 30, seconds: 10)),
        lon: 0.01 + 0.00089932, // ~100 m further, 10 s later
        speed: 10,
      ),
    );
    expect(m1.distanceMeters, closeTo(600, 1));
    expect(m1.elapsed, const Duration(milliseconds: 110000));
  });
}
