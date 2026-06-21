import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/services/map_storage_service.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapsforge_flutter_core/model.dart' show BoundingBox;

void main() {
  // Alps (big, southern Bavaria + the Alpine arc) and Bayern (smaller, all of
  // Bavaria) overlap over southern Bavaria.
  const alps = InstalledMap(
      fileName: 'Alps.map', path: '/m/Alps.map', sizeBytes: 1);
  const bayern = InstalledMap(
      fileName: 'Bayern.map', path: '/m/Bayern.map', sizeBytes: 1);
  final bounds = {
    alps.path: BoundingBox(43.0, 5.0, 48.5, 16.0), // min/max lat, min/max lon
    bayern.path: BoundingBox(47.2, 8.9, 50.6, 13.9),
  };
  GeoSample at(double lat, double lon) =>
      GeoSample(latitude: lat, longitude: lon, time: DateTime(2026));

  test('no maps installed -> null (bundled demo)', () {
    expect(
      pickMapPath(installed: const [], selected: null, position: at(48, 11), bounds: const {}),
      isNull,
    );
  });

  test('manual selection wins when still installed', () {
    expect(
      pickMapPath(
        installed: [alps, bayern],
        selected: 'Bayern.map',
        position: at(46.0, 7.0), // only Alps covers this
        bounds: bounds,
      ),
      bayern.path,
    );
  });

  test('stale manual selection (not installed) falls through to auto', () {
    expect(
      pickMapPath(
        installed: [alps, bayern],
        selected: 'Deleted.map',
        position: at(49.5, 11.0), // northern Bavaria — only Bayern covers
        bounds: bounds,
      ),
      bayern.path,
    );
  });

  test('auto picks the smallest map covering the position (Bayern in Alps)', () {
    // Munich is inside both Alps and Bayern; the smaller (Bayern) wins.
    expect(
      pickMapPath(
        installed: [alps, bayern],
        selected: null,
        position: at(48.14, 11.58),
        bounds: bounds,
      ),
      bayern.path,
    );
  });

  test('auto picks the only covering map outside the smaller one', () {
    // Switzerland — inside Alps only.
    expect(
      pickMapPath(
        installed: [alps, bayern],
        selected: null,
        position: at(46.2, 7.4),
        bounds: bounds,
      ),
      alps.path,
    );
  });

  test('no position -> first installed map', () {
    expect(
      pickMapPath(installed: [alps, bayern], selected: null, position: null, bounds: bounds),
      alps.path,
    );
  });

  test('position outside every map -> first installed map', () {
    expect(
      pickMapPath(
        installed: [alps, bayern],
        selected: null,
        position: at(0, 0),
        bounds: bounds,
      ),
      alps.path,
    );
  });
}
