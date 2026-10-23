import 'package:cycle/app.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/routing/application/follow_route_providers.dart';
import 'package:cycle/features/routing/domain/gpx_route_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';

import '../test/support/fakes.dart';

/// A short route in Monaco (inside the bundled demo map).
const _harbourGpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Harbour test route</name><trkseg>
    <trkpt lat="43.7350" lon="7.4210"></trkpt>
    <trkpt lat="43.7365" lon="7.4225"></trkpt>
    <trkpt lat="43.7380" lon="7.4240"></trkpt>
    <trkpt lat="43.7395" lon="7.4255"></trkpt>
  </trkseg></trk>
</gpx>''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home shows the map and opens the map manager', (tester) async {
    final location = FakeLocationService();
    addTearDown(location.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
        ],
        child: const CycleApp(),
      ),
    );
    appRouter.go('/'); // shared singleton router — start from home
    await tester.pumpAndSettle();

    // The home screen renders the bundled demo (Monaco) map offline.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(MapsforgeView), findsOneWidget);
    expect(find.text('SPEED'), findsOneWidget); // stats overlay on the map
    expect(tester.takeException(), isNull);

    // Open the map manager from the app bar.
    await tester.tap(find.byKey(const Key('manageMapsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Manage maps'), findsOneWidget);
    // Maps come from OpenAndroMaps' page in the browser, not a built-in list.
    expect(find.byKey(const Key('openAndroMapsButton')), findsOneWidget);
  });

  testWidgets('follows a GPX route: overlay banner + remaining distance',
      (tester) async {
    final location = FakeLocationService();
    addTearDown(location.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [locationServiceProvider.overrideWithValue(location)],
        child: const CycleApp(),
      ),
    );
    // appRouter is a shared singleton; a previous test may have left it on
    // another screen. Make sure we start on the home/map screen.
    appRouter.go('/');
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Load the bundled demo route from the app-bar follow menu.
    await tester.tap(find.byKey(const Key('followRouteMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('followDemoItem')));
    // pumpAndSettle won't await the rootBundle load; give the async asset
    // load + route parse/render real time.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The navigation banner appears with the route's name.
    expect(find.byKey(const Key('routeBanner')), findsOneWidget);
    expect(find.text('Monaco loop'), findsOneWidget);

    // A GPS fix on the route surfaces the remaining distance.
    location.emit(GeoSample(
      latitude: 43.738358,
      longitude: 7.421606,
      time: DateTime.now(),
      speedMps: 0,
      altitudeMeters: 0,
      accuracyMeters: 5,
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('km left'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Stop following clears the banner.
    await tester.tap(find.byKey(const Key('followRouteMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('followClearItem')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('routeBanner')), findsNothing);
  });

  testWidgets('an imported route is kept: follow it again from Saved routes, '
      'it is followed again after a restart, then delete it', (tester) async {
    final location = FakeLocationService();
    addTearDown(location.dispose);
    final import = FakeRouteImportService(filesXml: {'harbour': _harbourGpx});
    final id = parseGpxRoute(_harbourGpx).fingerprint;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
          routeImportServiceProvider.overrideWithValue(import),
        ],
        child: const CycleApp(),
      ),
    );
    appRouter.go('/');
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    Future<void> menu(String item) async {
      await tester.tap(find.byKey(const Key('followRouteMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(item)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    // Import it from the routes folder: followed, and saved.
    await menu('followImportItem');
    await tester.tap(find.text('harbour'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('routeBanner')), findsOneWidget);
    expect(find.text('Harbour test route'), findsOneWidget);

    // Stop following; it's still in Saved routes, and follows from there.
    await menu('followClearItem');
    expect(find.byKey(const Key('routeBanner')), findsNothing);
    await menu('followSavedItem');
    expect(find.byKey(Key('savedRoute_$id')), findsOneWidget);
    await tester.tap(find.byKey(Key('savedRoute_$id')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeBanner')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // "Restart": a fresh app on the same database follows it again, the way
    // main() restores it at launch.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
          routeImportServiceProvider.overrideWithValue(import),
        ],
        child: const CycleApp(),
      ),
    );
    appRouter.go('/');
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(CycleApp)));
    expect(find.byKey(const Key('routeBanner')), findsNothing);
    await container.read(followRouteProvider.notifier).restore();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('routeBanner')), findsOneWidget);
    expect(find.text('Harbour test route'), findsOneWidget);

    // Stop following and delete it (also leaves the emulator's DB clean).
    await menu('followClearItem');
    await menu('followSavedItem');
    await tester.tap(find.byKey(Key('savedRouteMenu_$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('deleteRoute_$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('savedRoute_$id')), findsNothing);
    appRouter.go('/');
    await tester.pumpAndSettle();
  });
}
