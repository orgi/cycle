import 'dart:math' as math;

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

  group('fitMapView', () {
    // World width/height in px at zoom z: 256·2^z. The box's extent at the
    // returned zoom must fit the screen minus padding, and one level more
    // must not (it's the largest that fits).
    double mercY(double lat) =>
        math.log(math.tan(math.pi / 4 + lat * math.pi / 360));
    ({double w, double h}) extentPx(
            double minLat, double maxLat, double minLon, double maxLon, int z) =>
        (
          w: (maxLon - minLon) / 360 * 256 * math.pow(2, z),
          h: (mercY(maxLat) - mercY(minLat)) / (2 * math.pi) * 256 * math.pow(2, z),
        );

    test('a north–south ride at 48°N fits — degrees of latitude are longer '
        'on the map there', () {
      // 0.1° × 0.1° near Munich: on the map it's ~1.5× taller than wide.
      final v = fitMapView(
          minLat: 48.10, maxLat: 48.20, minLon: 11.50, maxLon: 11.60,
          width: 400, height: 400, paddingPx: 0);
      final e = extentPx(48.10, 48.20, 11.50, 11.60, v.zoom);
      expect(e.h, lessThanOrEqualTo(400));
      expect(e.w, lessThanOrEqualTo(400));
      final more = extentPx(48.10, 48.20, 11.50, 11.60, v.zoom + 1);
      expect(more.h > 400 || more.w > 400, isTrue);
      // Treating latitude like longitude would have said zoom 12, where the
      // ride is ~436 px tall: its ends cut off on a 400 px map.
      expect(v.zoom, 11);
    });

    test('padding is left free; the centre is the box\'s middle on the map',
        () {
      final v = fitMapView(
          minLat: 47.0, maxLat: 49.0, minLon: 10.0, maxLon: 12.0,
          width: 1000, height: 600, paddingPx: 50);
      final e = extentPx(47.0, 49.0, 10.0, 12.0, v.zoom);
      expect(e.h, lessThanOrEqualTo(500));
      expect(e.w, lessThanOrEqualTo(900));
      expect(v.longitude, 11.0);
      // The Mercator middle lies a little north of the plain average.
      expect(v.latitude, greaterThan(48.0));
      expect(mercY(v.latitude), closeTo((mercY(47) + mercY(49)) / 2, 1e-9));
    });

    test('a tiny or zero-size ride stays within the zoom range', () {
      final dot = fitMapView(
          minLat: 48.1, maxLat: 48.1, minLon: 11.5, maxLon: 11.5,
          width: 400, height: 800);
      expect(dot.zoom, 17);
      final world = fitMapView(
          minLat: -60, maxLat: 70, minLon: -170, maxLon: 170,
          width: 300, height: 300);
      expect(world.zoom, 3);
      final noRoom = fitMapView(
          minLat: 48.1, maxLat: 48.2, minLon: 11.5, maxLon: 11.6,
          width: 0, height: 0);
      expect(noRoom.zoom, inInclusiveRange(3, 17));
    });
  });
}
