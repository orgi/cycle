import 'package:cycle/core/metrics/ride_profile.dart';
import 'package:cycle/core/utils/geo.dart';
import 'package:flutter_test/flutter_test.dart';

/// [n] points going north from 48°N, ~111 m apart, heights 100, 110, ….
RideProfile northward(int n, {bool heights = true}) => RideProfile([
      for (var i = 0; i < n; i++)
        (latitude: 48 + i * 0.001, longitude: 11.0, altitude: heights ? 100.0 + i * 10 : null),
    ]);

void main() {
  test('distances add up from the start, standing still adds nothing', () {
    final p = RideProfile([
      (latitude: 48.0, longitude: 11.0, altitude: 500.0),
      (latitude: 48.001, longitude: 11.0, altitude: null),
      (latitude: 48.001, longitude: 11.0, altitude: 505.0), // stopped
      (latitude: 48.002, longitude: 11.0, altitude: 510.0),
    ]);
    final leg = haversineMeters(48, 11, 48.001, 11);
    expect(p.distances[0], 0);
    expect(p.distances[1], closeTo(leg, 1e-6));
    expect(p.distances[2], p.distances[1]);
    expect(p.totalMeters, closeTo(2 * leg, 1e-6));
    expect(p.hasAltitude, isTrue);
    expect(p.altitudeRange, (low: 500.0, high: 510.0));
  });

  test('indexAt: the point nearest a distance, clamped to the ride', () {
    final p = northward(5); // 0, ~111, ~222, ~333, ~445 m
    final step = p.distances[1];
    expect(p.indexAt(0), 0);
    expect(p.indexAt(step * 0.4), 0);
    expect(p.indexAt(step * 0.6), 1);
    expect(p.indexAt(step * 2), 2);
    expect(p.indexAt(-50), 0);
    expect(p.indexAt(1e9), 4);
    expect(RideProfile(const []).indexAt(10), -1);
  });

  test('nearest: the track point by a tap, only within the given distance',
      () {
    final p = northward(5);
    // 30 m east of the third point.
    final lonOffset = 30 / (111320 * 0.6691); // cos(48°)
    expect(p.nearest(48.002, 11.0 + lonOffset, maxMeters: 50), 2);
    expect(p.nearest(48.002, 11.0 + lonOffset, maxMeters: 20), isNull);
    expect(p.nearest(48.0035, 11.0, maxMeters: 100), anyOf(3, 4));
    expect(p.nearest(48.0031, 11.0, maxMeters: 100), 3);
  });

  test('elevation samples: thinned for long rides, first and last kept, no '
      'points without a height', () {
    final long = northward(5000);
    final s = long.elevationSamples(maxPoints: 600);
    expect(s, hasLength(600));
    expect(s.first.meters, 0);
    expect(s.last.meters, long.totalMeters);
    expect(s.last.altitude, 100.0 + 4999 * 10);
    for (var i = 1; i < s.length; i++) {
      expect(s[i].meters, greaterThan(s[i - 1].meters));
    }
    expect(northward(10).elevationSamples(), hasLength(10));
    expect(northward(10, heights: false).elevationSamples(), isEmpty);
    expect(northward(10, heights: false).altitudeRange, isNull);
    expect(northward(10, heights: false).hasAltitude, isFalse);
  });
}
