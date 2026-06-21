import 'package:cycle/core/utils/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('haversineMeters', () {
    test('one degree of longitude at the equator is ~111.2 km', () {
      final d = haversineMeters(0, 0, 0, 1);
      expect(d, closeTo(111195, 50));
    });

    test('one degree of latitude is ~111.2 km', () {
      final d = haversineMeters(0, 0, 1, 0);
      expect(d, closeTo(111195, 50));
    });

    test('identical points are zero distance', () {
      expect(haversineMeters(52.5, 13.4, 52.5, 13.4), 0);
    });

    test('a short ~100 m leg is measured accurately', () {
      // 100 m east at the equator ≈ 0.00089932 degrees of longitude.
      final d = haversineMeters(0, 0, 0, 0.00089932);
      expect(d, closeTo(100, 1));
    });
  });

  group('bearingDegrees', () {
    test('cardinal directions (0=N, 90=E, 180=S, 270=W)', () {
      expect(bearingDegrees(0, 0, 1, 0), closeTo(0, 0.5)); // north
      expect(bearingDegrees(0, 0, 0, 1), closeTo(90, 0.5)); // east
      expect(bearingDegrees(1, 0, 0, 0), closeTo(180, 0.5)); // south
      expect(bearingDegrees(0, 1, 0, 0), closeTo(270, 0.5)); // west
    });

    test('is always normalised to [0, 360)', () {
      final b = bearingDegrees(52.5, 13.4, 52.4, 13.3); // south-west
      expect(b, greaterThanOrEqualTo(0));
      expect(b, lessThan(360));
      expect(b, closeTo(213, 3));
    });
  });
}
