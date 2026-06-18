import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/map/application/map_providers.dart';
import 'package:cycle/features/routing/application/follow_route_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _validGpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="t" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Loop</name><trkseg>
    <trkpt lat="43.7380" lon="7.4250"></trkpt>
    <trkpt lat="43.7390" lon="7.4250"></trkpt>
    <trkpt lat="43.7400" lon="7.4250"></trkpt>
  </trkseg></trk>
</gpx>''';

void main() {
  test('loadDemo follows the bundled route', () async {
    final import = FakeRouteImportService(assetXml: _validGpx);
    final container = ProviderContainer(
      overrides: [routeImportServiceProvider.overrideWithValue(import)],
    );
    addTearDown(container.dispose);

    expect(container.read(followRouteProvider), isNull);
    await container.read(followRouteProvider.notifier).loadDemo();
    expect(container.read(followRouteProvider)!.points.length, 3);
  });

  test('lists importable routes, follows one, clear resets', () async {
    final import = FakeRouteImportService(filesXml: {'ride': _validGpx});
    final container = ProviderContainer(
      overrides: [routeImportServiceProvider.overrideWithValue(import)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(followRouteProvider.notifier);

    final files = await notifier.importableRoutes();
    expect(files.map((f) => f.name), ['ride']);
    expect(container.read(followRouteProvider), isNull);

    await notifier.followFile(files.single);
    expect(container.read(followRouteProvider), isNotNull);

    notifier.clear();
    expect(container.read(followRouteProvider), isNull);
  });

  test('following an invalid file throws FormatException', () async {
    final import = FakeRouteImportService(filesXml: {'bad': 'nonsense'});
    final container = ProviderContainer(
      overrides: [routeImportServiceProvider.overrideWithValue(import)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(followRouteProvider.notifier);
    final files = await notifier.importableRoutes();

    expect(() => notifier.followFile(files.single), throwsFormatException);
  });

  test('routeProgressProvider tracks the latest GPS fix', () async {
    final import = FakeRouteImportService(assetXml: _validGpx);
    final location = FakeLocationService();
    addTearDown(location.dispose);
    final container = ProviderContainer(
      overrides: [
        routeImportServiceProvider.overrideWithValue(import),
        locationServiceProvider.overrideWithValue(location),
      ],
    );
    addTearDown(container.dispose);

    // Keep the position stream subscribed.
    final sub = container.listen(currentPositionProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(followRouteProvider.notifier).loadDemo();
    expect(container.read(routeProgressProvider), isNull); // no fix yet

    location.emit(GeoSample(
      latitude: 43.7390,
      longitude: 7.4250,
      time: DateTime.now(),
      speedMps: 0,
      altitudeMeters: 0,
      accuracyMeters: 5,
    ));
    await Future<void>.delayed(Duration.zero);

    final progress = container.read(routeProgressProvider);
    expect(progress, isNotNull);
    expect(progress!.offRoute, isFalse);
    expect(progress.remainingMeters, greaterThan(0));
  });
}
