import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/models/ride_place.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/places/application/ride_places_providers.dart';
import 'package:cycle/features/places/presentation/ride_places_screen.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeLocationService location;
  late FakeRidePlacesStore places;
  late FakeSettingsStore settings;

  Future<void> pump(
    WidgetTester tester, {
    List<RidePlace> initial = const [],
    AppSettings app = const AppSettings(),
  }) async {
    location = FakeLocationService();
    places = FakeRidePlacesStore(initial);
    settings = FakeSettingsStore(app);
    addTearDown(location.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(location),
          ridePlacesStoreProvider.overrideWithValue(places),
          settingsStoreProvider.overrideWithValue(settings),
        ],
        child: const MaterialApp(home: RidePlacesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A current, accurate fix [north] metres north of 47 N 11 E.
  Future<void> fix(WidgetTester tester, {double north = 0}) async {
    location.emit(
      GeoSample(
        latitude: 47 + north / 111195,
        longitude: 11,
        time: DateTime.now(),
        accuracyMeters: 5,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('adds a place where the rider stands', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('placesEmpty')), findsOneWidget);

    // No fix yet: it says so instead of guessing a place.
    await tester.tap(find.byKey(const Key('addPlaceButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('placeNoFixSnack')), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(ListView)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await fix(tester);
    await tester.tap(find.byKey(const Key('addPlaceButton')));
    await tester.pumpAndSettle();
    expect(find.text('New place'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Home'), findsOneWidget);
    await tester.tap(find.byKey(const Key('placeTrigger_stop')));
    await tester.tap(find.byKey(const Key('placeRadius_100')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('placeSave')));
    await tester.pumpAndSettle();

    final saved = places.places.single;
    expect(saved.name, 'Home');
    expect(saved.trigger, PlaceTrigger.stop);
    expect(saved.radiusMeters, 100);
    expect(saved.latitude, closeTo(47, 1e-9));
    expect(find.textContaining("You're here"), findsOneWidget);
    expect(
      find.textContaining('Stops the ride when you arrive'),
      findsOneWidget,
    );

    // Further away it says how far.
    await fix(tester, north: 1500);
    expect(find.textContaining('1.50 km away'), findsOneWidget);
  });

  testWidgets('a place too far from a good fix is not added', (tester) async {
    await pump(tester);
    location.emit(
      GeoSample(
        latitude: 47,
        longitude: 11,
        time: DateTime.now(),
        accuracyMeters: 40, // indoors
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addPlaceButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('placeNoFixSnack')), findsOneWidget);
    expect(find.text('New place'), findsNothing);
  });

  testWidgets('edits, moves and deletes (with undo) a place', (tester) async {
    const home = RidePlace(id: 'p1', name: 'Home', latitude: 47, longitude: 11);
    await pump(tester, initial: [home]);

    await tester.tap(find.byKey(const Key('place_p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('placeNameField')), 'Flat');
    await tester.tap(find.byKey(const Key('placeTrigger_start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('placeSave')));
    await tester.pumpAndSettle();
    expect(places.places.single.name, 'Flat');
    expect(places.places.single.trigger, PlaceTrigger.start);

    await fix(tester, north: 300);
    await tester.tap(find.byKey(const Key('placeMenu_p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('placeMoveHere')));
    await tester.pumpAndSettle();
    expect(places.places.single.latitude, closeTo(47 + 300 / 111195, 1e-9));

    await tester.tap(find.byKey(const Key('placeMenu_p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('placeDelete')));
    await tester.pumpAndSettle();
    expect(places.places, isEmpty);
    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(places.places.single.name, 'Flat');
  });

  testWidgets('switches places off, and hints at keeping the screen on', (
    tester,
  ) async {
    const home = RidePlace(id: 'p1', name: 'Home', latitude: 47, longitude: 11);
    await pump(tester, initial: [home]);
    expect(find.byKey(const Key('placesKeepOnHint')), findsOneWidget);

    await tester.tap(find.byKey(const Key('placesEnabledSwitch')));
    await tester.pumpAndSettle();
    expect((await settings.load()).placesEnabled, isFalse);
  });

  testWidgets('no hint with the screen kept on, or only stop places', (
    tester,
  ) async {
    const work = RidePlace(
      id: 'p2',
      name: 'Work',
      latitude: 47,
      longitude: 11,
      trigger: PlaceTrigger.stop,
    );
    await pump(tester, initial: [work]);
    expect(find.byKey(const Key('placesKeepOnHint')), findsNothing);
  });
}
