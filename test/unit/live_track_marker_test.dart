import 'package:cycle/features/map/presentation/live_track_marker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_core/model.dart';
import 'package:mapsforge_flutter_core/projection.dart';

void main() {
  // ~1 m steps near Munich.
  const lat0 = 48.137;
  const lon0 = 11.575;
  const metreLat = 1 / 111320.0;
  final metreLon = 1 / (111320.0 * 0.66783); // cos(48.137°)

  LatLong at({double north = 0, double east = 0}) =>
      LatLong(lat0 + north * metreLat, lon0 + east * metreLon);

  LiveTrackMarker marker() =>
      LiveTrackMarker(color: 0xffffffff, arrowColor: 0xff000000);

  test('appending a fix never moves what is already drawn', () {
    final m = marker();
    for (var i = 0; i <= 300; i += 5) {
      m.add(at(east: i.toDouble(), north: (i % 20 == 0) ? 3 : 0));
    }
    final z16 = PixelProjection(16);
    m.ensureProjected(z16);
    final pixelsBefore = m.pixels;
    final arrowsBefore = m.arrows;

    for (var i = 305; i <= 600; i += 5) {
      m.add(at(east: i.toDouble()));
    }
    m.ensureProjected(z16);

    expect(m.pixels.take(pixelsBefore.length), pixelsBefore);
    final arrowsAfter = m.arrows.take(arrowsBefore.length).toList();
    for (var i = 0; i < arrowsBefore.length; i++) {
      expect(arrowsAfter[i].x, arrowsBefore[i].x);
      expect(arrowsAfter[i].y, arrowsBefore[i].y);
      expect(arrowsAfter[i].ux, arrowsBefore[i].ux);
      expect(arrowsAfter[i].uy, arrowsBefore[i].uy);
    }
    expect(m.arrows.length, greaterThan(arrowsBefore.length));
  });

  test('a short out-and-back (wrong turn) is drawn, not simplified away', () {
    final m = marker()
      ..add(at())
      ..add(at(east: 100))
      ..add(at(east: 100, north: 5))
      ..add(at(east: 100, north: 10)) // 10 m up the wrong road
      ..add(at(east: 100, north: 5))
      ..add(at(east: 100))
      ..add(at(east: 200));
    final z = PixelProjection(14); // zoomed out: 10 m is only a few pixels
    m.ensureProjected(z);
    expect(m.pixels, hasLength(7)); // every point kept
    expect(m.pixels[3], z.latLonToPixel(at(east: 100, north: 10)));
  });

  test('chevrons sit every 90 m at zoom 16, starting half a step in', () {
    final m = marker()
      ..add(at())
      ..add(at(east: 1000));
    m.ensureProjected(PixelProjection(16));
    // 45, 135, …, 945 m
    expect(m.arrows, hasLength(11));
    final a = m.arrows.first;
    expect(a.ux, closeTo(1, 1e-6)); // pointing east, the travel direction
    expect(a.uy, closeTo(0, 1e-6));
  });

  test('a zoom change re-lays the chevrons at the same on-screen spacing', () {
    final m = marker()
      ..add(at())
      ..add(at(east: 1000));
    m.ensureProjected(PixelProjection(17));
    expect(m.arrows, hasLength(22)); // 45 m apart, from 22.5 m
    m.ensureProjected(PixelProjection(16));
    expect(m.arrows, hasLength(11));
  });

  test('setAll / clear / last', () {
    final m = marker();
    expect(m.last, isNull);
    m.setAll([at(), at(east: 10), at(east: 20)]);
    expect(m.length, 3);
    expect(m.last, at(east: 20));
    m.ensureProjected(PixelProjection(16));
    m.clear();
    expect(m.length, 0);
    m.ensureProjected(PixelProjection(16));
    expect(m.pixels, isEmpty);
    expect(m.arrows, isEmpty);
  });

  test('stays paintable while empty, so it picks up the first fixes', () {
    final m = marker();
    final box = const BoundingBox(48, 11, 49, 12);
    expect(m.shouldPaint(box, 16), isTrue);
  });
}
