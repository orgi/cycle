import 'dart:io';

import 'package:cycle/features/routing/domain/gpx_route_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the bundled Monaco demo route', () {
    final xml =
        File('assets/routes/monaco_loop.gpx').readAsStringSync();
    final route = parseGpxRoute(xml);

    expect(route.name, 'Monaco loop');
    expect(route.points.length, greaterThan(100));
    // The loop is well over a kilometre long.
    expect(route.totalMeters, greaterThan(1000));
    // Points carry monotonically non-decreasing cumulative distance.
    for (var i = 1; i < route.points.length; i++) {
      expect(
        route.points[i].distanceFromStartMeters,
        greaterThanOrEqualTo(route.points[i - 1].distanceFromStartMeters),
      );
    }
  });

  test('falls back to <rte> route points and the fallback name', () {
    const xml = '''
<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <rte>
    <rtept lat="43.7380" lon="7.4250"></rtept>
    <rtept lat="43.7390" lon="7.4250"></rtept>
  </rte>
</gpx>''';
    final route = parseGpxRoute(xml, fallbackName: 'imported');
    expect(route.name, 'imported');
    expect(route.points.length, 2);
  });

  test('prefers the track name when present', () {
    const xml = '''
<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>My ride</name><trkseg>
    <trkpt lat="43.7380" lon="7.4250"></trkpt>
    <trkpt lat="43.7390" lon="7.4250"></trkpt>
  </trkseg></trk>
</gpx>''';
    expect(parseGpxRoute(xml).name, 'My ride');
  });

  test('throws FormatException on a GPX without usable points', () {
    const xml = '''
<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
</gpx>''';
    expect(() => parseGpxRoute(xml), throwsFormatException);
  });

  test('throws FormatException on non-GPX text', () {
    expect(() => parseGpxRoute('not xml at all'), throwsFormatException);
  });
}
