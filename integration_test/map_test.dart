import 'package:cycle/app.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mapsforge_flutter/mapsforge.dart';

import '../test/support/fakes.dart';

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
    expect(find.text('Alps'), findsOneWidget);
    expect(find.byKey(const Key('download_Alps')), findsOneWidget);
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
}
