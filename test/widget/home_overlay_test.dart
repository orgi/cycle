import 'package:cycle/core/metrics/elevation.dart';
import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/models/home_layout.dart';
import 'package:cycle/core/models/ride_metrics.dart';
import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/map/application/home_layout_providers.dart';
import 'package:cycle/features/map/presentation/home_overlay.dart';
import 'package:cycle/features/routing/application/follow_route_providers.dart';
import 'package:cycle/features/routing/domain/follow_route.dart';
import 'package:cycle/features/routing/domain/route_navigator.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _Following extends FollowRouteController {
  _Following(this.route);
  final FollowRoute route;
  @override
  FollowRoute? build() => route;
}

void main() {
  const top = HomeArea.top, bottom = HomeArea.bottom;
  final metrics = RideMetrics.zero().copyWith(
    distanceMeters: 12340,
    elevationMeters: 612.4,
    climbMeters: 412,
  );

  late FakeBikeProfilesStore store;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    HomeLayout layout = HomeLayout.standard,
    Set<SensorKind> sensors = const {},
    RideMetrics? ride,
    List overrides = const [],
  }) async {
    store = FakeBikeProfilesStore(BikeProfilesState(
      profiles: [
        BikeProfile(
            id: 'road',
            name: 'Road',
            colorArgb: 1,
            settings: BikeSettings(homeLayout: layout)),
        const BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2),
      ],
      activeId: 'road',
    ));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        bikeProfilesStoreProvider.overrideWithValue(store),
        rideMetricsProvider.overrideWithValue(ride ?? metrics),
        sensorSnapshotProvider.overrideWith(
            (ref) => Stream.value(const SensorSnapshot(heartRate: 142))),
        ...overrides.cast(),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Positioned.fill(
              child: HomeOverlay(
                bottomInset: 0,
                visibleSensors: sensors,
                onTileTap: (_) => null,
              ),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    container =
        ProviderScope.containerOf(tester.element(find.byType(HomeOverlay)));
  }

  Finder tileAt(HomeArea a, int row, int i) =>
      find.byKey(Key('homeTile_${a.name}_${row}_$i'));

  Future<HomeLayout> savedLayout() async => (await store.load())
      .profiles
      .firstWhere((p) => p.id == 'road')
      .settings!
      .homeLayout;

  /// Picks the option [key] in the tile picker (scrolled into view first).
  Future<void> choose(WidgetTester tester, String key) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
    final g = await tester.startGesture(tester.getCenter(from));
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    await g.moveTo(tester.getCenter(to));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets(
      'the standard layout: SPEED/TIME on top, DIST/AVG/MAX below; '
      'sensor tiles only for the bike\'s sensors', (tester) async {
    await pump(tester, sensors: {SensorKind.heartRate});
    for (final label in ['SPEED', 'TIME', 'DIST', 'AVG', 'MAX', 'HR']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('142'), findsOneWidget); // the heart rate
    expect(find.text('CAD'), findsNothing);
    expect(find.text('PWR'), findsNothing);
    // HR keeps a third of the row, centred, rather than stretching.
    final hr = tester.getSize(tileAt(bottom, 0, 0));
    final dist = tester.getSize(tileAt(bottom, 1, 0));
    expect(hr.width, closeTo(dist.width, 0.5));
    expect(tester.getCenter(tileAt(bottom, 0, 0)).dx,
        closeTo(tester.getCenter(tileAt(bottom, 1, 1)).dx, 0.5));
  });

  testWidgets(
      'a zero-size first frame (Android) lays out, and the next one '
      'shows the tiles', (tester) async {
    Widget app(double width) => ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
            bikeProfilesStoreProvider
                .overrideWithValue(FakeBikeProfilesStore(oneBike())),
            rideMetricsProvider.overrideWithValue(metrics),
          ],
          child: MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 500,
                child: HomeOverlay(
                  bottomInset: 0,
                  visibleSensors: const {},
                  onTileTap: (_) => null,
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(320));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const Key('homeTile_bottom_1_0'))).width,
        closeTo((304 - 12) / 3, 0.5));
  });

  testWidgets('ELEV and CLIMB show the height and the ride\'s climb',
      (tester) async {
    await pump(tester,
        layout: HomeLayout.standard
            .replace(const TilePos(bottom, 1, 1), HomeTile.elevation)
            .replace(const TilePos(bottom, 1, 2), HomeTile.climb));
    expect(find.text('ELEV'), findsOneWidget);
    expect(find.text('612'), findsOneWidget);
    expect(find.text('CLIMB'), findsOneWidget);
    expect(find.text('412'), findsOneWidget);
    expect(find.text('AVG'), findsNothing);
  });

  testWidgets('no height yet: ELEV shows a dash', (tester) async {
    await pump(tester,
        ride: const RideMetrics.zero(),
        layout: const HomeLayout(top: [
          [HomeTile.elevation]
        ], bottom: []));
    expect(find.text('—'), findsOneWidget);
  });

  group('editing', () {
    testWidgets('long-press starts it; tap a tile to change what it shows',
        (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('homeNewRow_top_0')), findsNothing);
      await tester.longPress(tileAt(top, 0, 1));
      await tester.pumpAndSettle();
      expect(container.read(homeLayoutEditingProvider), isTrue);
      // Every sensor tile shows while editing, so it can be moved.
      expect(find.text('CAD'), findsOneWidget);
      expect(find.byKey(const Key('homeNewRow_top_0')), findsOneWidget);

      await tester.tap(tileAt(bottom, 1, 2)); // MAX
      await tester.pumpAndSettle();
      await choose(tester, 'homeTileOption_climb');
      expect(find.text('CLIMB'), findsOneWidget);
      expect(find.text('MAX'), findsNothing);
      expect((await savedLayout()).bottom[1],
          [HomeTile.distance, HomeTile.avgSpeed, HomeTile.climb]);
      // Only the active bike's layout changed.
      expect(
          (await store.load())
              .profiles
              .firstWhere((p) => p.id == 'mtb')
              .settings,
          isNull);
    });

    testWidgets('drag a tile onto another to swap them', (tester) async {
      await pump(tester);
      await tester.longPress(tileAt(top, 0, 0));
      await tester.pumpAndSettle();
      await drag(tester, tileAt(top, 0, 1), tileAt(bottom, 1, 0)); // TIME→DIST
      final saved = await savedLayout();
      expect(saved.top, [
        [HomeTile.speed, HomeTile.distance]
      ]);
      expect(saved.bottom[1],
          [HomeTile.time, HomeTile.avgSpeed, HomeTile.maxSpeed]);
    });

    testWidgets(
        'drag a tile onto the bin to remove it, onto "+ row" for a '
        'row of its own', (tester) async {
      await pump(tester);
      await tester.longPress(tileAt(top, 0, 0));
      await tester.pumpAndSettle();
      // While dragging, the bin shows in the middle.
      final g = await tester.startGesture(tester.getCenter(tileAt(top, 0, 1)));
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(find.byKey(const Key('homeBin')), findsOneWidget);
      await g.moveTo(tester.getCenter(find.byKey(const Key('homeBin'))));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('TIME'), findsNothing);
      expect(find.byKey(const Key('homeBin')), findsNothing);
      expect((await savedLayout()).top, [
        [HomeTile.speed]
      ]);

      // MAX into a new row at the very top.
      await drag(tester, tileAt(bottom, 1, 2),
          find.byKey(const Key('homeNewRow_top_0')));
      final saved = await savedLayout();
      expect(saved.top, [
        [HomeTile.maxSpeed],
        [HomeTile.speed],
      ]);
      expect(saved.bottom[1], [HomeTile.distance, HomeTile.avgSpeed]);
    });

    testWidgets('"+" adds a tile to a row with room, "+ row" a new row',
        (tester) async {
      await pump(tester);
      await tester.longPress(tileAt(top, 0, 0));
      await tester.pumpAndSettle();
      // The top row has room for a third tile; the full bottom ones don't.
      expect(find.byKey(const Key('homeRowAdd_bottom_1')), findsNothing);
      await tester.tap(find.byKey(const Key('homeRowAdd_top_0')));
      await tester.pumpAndSettle();
      // Wide tiles need a row of their own: not offered here.
      expect(
          find.byKey(const Key('homeTileOption_ride_profile')), findsNothing);
      await choose(tester, 'homeTileOption_elev');
      expect((await savedLayout()).top.first,
          [HomeTile.speed, HomeTile.time, HomeTile.elevation]);

      await tester.tap(find.byKey(const Key('homeNewRow_bottom_2')));
      await tester.pumpAndSettle();
      await choose(tester, 'homeTileOption_ride_profile');
      expect((await savedLayout()).bottom.last, [HomeTile.rideProfile]);
      expect(find.text('RIDE'), findsOneWidget);
      expect(find.text('Starts with the ride'), findsOneWidget);
    });

    testWidgets('remove from the picker; back finishes editing',
        (tester) async {
      await pump(tester);
      await tester.longPress(tileAt(top, 0, 0));
      await tester.pumpAndSettle();
      await tester.tap(tileAt(bottom, 1, 0));
      await tester.pumpAndSettle();
      await choose(tester, 'homeTileRemove');
      expect(find.text('DIST'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(container.read(homeLayoutEditingProvider), isFalse);
      expect(find.byKey(const Key('homeNewRow_top_0')), findsNothing);
      expect(find.text('CAD'), findsNothing); // the bike has no such sensor
    });
  });

  group('elevation profiles', () {
    final ride = RideMetrics.zero().copyWith(
      climbMeters: 85,
      elevationProfile: ElevationProfile([
        for (var i = 0; i <= 50; i++)
          ProfilePoint(i * 100.0, 500 + (i < 30 ? i * 3.0 : 90 - (i - 30))),
      ]),
    );
    const rideRow = HomeLayout(top: [], bottom: [
      [HomeTile.rideProfile]
    ]);

    testWidgets('the ride\'s: climb so far, lowest and highest point',
        (tester) async {
      await pump(tester, layout: rideRow, ride: ride);
      expect(find.text('RIDE'), findsOneWidget);
      expect(find.text('↑ 85 m'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('590'), findsOneWidget);
    });

    final route = FollowRoute.fromGpxPoints('Alps', [
      for (var i = 0; i <= 10; i++)
        (
          lat: 47 + i * 0.001,
          lon: 11.0,
          ele: 600.0 + (i <= 5 ? i * 20 : 100 - (i - 5) * 10),
          time: null,
        ),
    ]);
    const routeRow = HomeLayout(top: [], bottom: [
      [HomeTile.routeProfile]
    ]);

    testWidgets('the route\'s: climb and distance still ahead', (tester) async {
      final halfway = route.points[2].distanceFromStartMeters;
      await pump(tester, layout: routeRow, overrides: [
        followRouteProvider.overrideWith(() => _Following(route)),
        routeProgressProvider.overrideWithValue(RouteProgress(
          nearestSegmentIndex: 2,
          crossTrackMeters: 3,
          traveledMeters: halfway,
          remainingMeters: route.totalMeters - halfway,
          offRoute: false,
        )),
      ]);
      expect(find.text('ROUTE'), findsOneWidget);
      // 100 m of climb, 40 of it done.
      expect(find.textContaining('↑ 60 m to go'), findsOneWidget);
      expect(find.textContaining('0.89 km'), findsOneWidget);
    });

    testWidgets(
        'the route\'s is hidden when no route is followed (shown '
        'while editing)', (tester) async {
      await pump(tester, layout: routeRow);
      expect(find.text('ROUTE'), findsNothing);
      container.read(homeLayoutEditingProvider.notifier).set(true);
      await tester.pumpAndSettle();
      expect(find.text('Shown while following a route'), findsOneWidget);
    });

    testWidgets('a route without heights says so', (tester) async {
      final flat = FollowRoute.fromCoordinates(
          'Flat', const [(47.0, 11.0), (47.001, 11.0)]);
      await pump(tester, layout: routeRow, overrides: [
        followRouteProvider.overrideWith(() => _Following(flat)),
        routeProgressProvider.overrideWithValue(null),
      ]);
      expect(find.text('This route has no heights'), findsOneWidget);
    });
  });
}
