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
}
