import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/models/home_layout.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/map/application/home_layout_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/features/settings/presentation/bike_profiles_screen.dart';
import 'package:cycle/features/settings/presentation/bike_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';

void main() {
  const twoBikes = BikeProfilesState(
    profiles: [
      BikeProfile(id: 'road', name: 'Road', colorArgb: 1),
      BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2),
    ],
    activeId: 'road',
  );

  Future<FakeBikeProfilesStore> pump(
    WidgetTester tester, {
    required String bikeId,
    BikeProfilesState bikes = twoBikes,
    AppSettings settings = const AppSettings(),
  }) async {
    final store = FakeBikeProfilesStore(bikes);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(FakeSettingsStore(settings)),
        bikeProfilesStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(home: BikeSettingsScreen(bikeId: bikeId)),
    ));
    await tester.pumpAndSettle();
    return store;
  }

  BikeProfile saved(BikeProfilesState s, String id) =>
      s.profiles.firstWhere((p) => p.id == id);

  testWidgets('edits one bike\'s wheel size, auto-pause and auto-start',
      (tester) async {
    final store = await pump(tester, bikeId: 'mtb');
    expect(find.text('MTB'), findsOneWidget);
    // Not the active bike.
    expect(find.byKey(const Key('bikeSettingsActiveNote')), findsNothing);
    expect(find.text('2105 mm — used for BLE speed sensors'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wheelCircumferenceTile')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('wheelCircumferenceField')), '2300');
    await tester.tap(find.byKey(const Key('wheelCircumferenceSave')));
    await tester.pumpAndSettle();
    expect(find.text('2300 mm — used for BLE speed sensors'), findsOneWidget);

    await tester.tap(find.byKey(const Key('autoPauseSpeedTile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('autoPauseSpeedField')), '3.5');
    await tester.tap(find.byKey(const Key('autoPauseSpeedSave')));
    await tester.pumpAndSettle();
    expect(find.text('3.5 km/h'), findsOneWidget);

    // The start speed can only be edited once auto-start is on.
    expect(
        tester
            .widget<ListTile>(find.byKey(const Key('autoStartSpeedTile')))
            .enabled,
        isFalse);
    await tester.tap(find.byKey(const Key('autoStartSwitch')));
    await tester.pumpAndSettle();
    expect(find.text('8 km/h'), findsOneWidget);
    await tester.tap(find.byKey(const Key('autoStartSpeedTile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('autoStartSpeedField')), '12');
    await tester.tap(find.byKey(const Key('autoStartSpeedSave')));
    await tester.pumpAndSettle();
    expect(find.text('12 km/h'), findsOneWidget);

    await tester.tap(find.byKey(const Key('autoPauseSwitch')));
    await tester.pumpAndSettle();
    // The threshold can't be edited while auto-pause is off.
    expect(
        tester
            .widget<ListTile>(find.byKey(const Key('autoPauseSpeedTile')))
            .enabled,
        isFalse);

    final state = await store.load();
    final mtb = saved(state, 'mtb');
    expect(
      mtb.settings,
      const BikeSettings(
        wheelCircumferenceMeters: 2.3,
        autoPauseEnabled: false,
        autoPauseSpeedKmh: 3.5,
        autoStartEnabled: true,
        autoStartSpeedKmh: 12,
      ),
    );
    expect(mtb.settingsClock, isNotNull); // synced to the bike's other phones
    expect(saved(state, 'road').settings, isNull); // the other bike untouched
  });

  testWidgets('rejects an implausible wheel circumference', (tester) async {
    final store = await pump(tester, bikeId: 'road');
    await tester.tap(find.byKey(const Key('wheelCircumferenceTile')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('wheelCircumferenceField')), '21');
    await tester.tap(find.byKey(const Key('wheelCircumferenceSave')));
    await tester.pumpAndSettle();
    expect(saved(await store.load(), 'road').settings, isNull);
  });

  testWidgets(
      'takes a walking speed for auto-start (hiking), but not one GPS drift '
      'reaches standing still', (tester) async {
    final store = await pump(tester,
        bikeId: 'mtb',
        bikes: twoBikes.copyWith(profiles: [
          twoBikes.profiles.first,
          const BikeProfile(
              id: 'mtb',
              name: 'MTB',
              colorArgb: 2,
              settings: BikeSettings(autoStartEnabled: true)),
        ]));
    Future<double> enter(String input) async {
      await tester.tap(find.byKey(const Key('autoStartSpeedTile')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('autoStartSpeedField')), input);
      await tester.tap(find.byKey(const Key('autoStartSpeedSave')));
      await tester.pumpAndSettle();
      return saved(await store.load(), 'mtb').settings!.autoStartSpeedKmh;
    }

    expect(await enter('3'), 3);
    expect(find.text('3 km/h'), findsOneWidget);
    for (final input in ['1.5', '41', 'fast']) {
      expect(await enter(input), 3, reason: input);
    }
  });

  testWidgets(
      'a bike from before per-bike settings starts from the old app-wide '
      'values', (tester) async {
    final store = await pump(
      tester,
      bikeId: 'road',
      settings: AppSettings.fromJson(const {
        'wheel_circumference_m': 2.2,
        'auto_pause': true,
        'auto_pause_kmh': 4.0,
        'auto_start': false,
      }),
    );
    expect(find.byKey(const Key('bikeSettingsActiveNote')), findsOneWidget);
    expect(find.text('2200 mm — used for BLE speed sensors'), findsOneWidget);
    expect(find.text('4 km/h'), findsOneWidget);

    await tester.tap(find.byKey(const Key('autoStartSwitch')));
    await tester.pumpAndSettle();
    // Only auto-start changed; the rest is what the phone used before.
    expect(
      saved(await store.load(), 'road').settings,
      const BikeSettings(
        wheelCircumferenceMeters: 2.2,
        autoPauseSpeedKmh: 4.0,
        autoStartEnabled: true,
      ),
    );
  });

  testWidgets('a bike that no longer exists', (tester) async {
    await pump(tester, bikeId: 'gone');
    expect(find.text('This bike no longer exists.'), findsOneWidget);
  });

  testWidgets('the bike list\'s menu opens that bike\'s settings',
      (tester) async {
    final router = GoRouter(initialLocation: '/bike-profiles', routes: [
      GoRoute(
        path: '/bike-profiles',
        builder: (context, state) => const BikeProfilesScreen(),
      ),
      GoRoute(
        path: '/bike-profiles/:id',
        builder: (context, state) =>
            BikeSettingsScreen(bikeId: state.pathParameters['id']!),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        bikeProfilesStoreProvider
            .overrideWithValue(FakeBikeProfilesStore(twoBikes)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bikeProfileMenu_mtb')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bike settings'));
    await tester.pumpAndSettle();
    expect(find.byType(BikeSettingsScreen), findsOneWidget);
    expect(find.byKey(const Key('wheelCircumferenceTile')), findsOneWidget);
    expect(find.text('MTB'), findsOneWidget);
  });

  group('home screen tiles', () {
    testWidgets('a bike with the standard tiles; only the active one is '
        'edited on the map', (tester) async {
      await pump(tester, bikeId: 'mtb');
      await tester.scrollUntilVisible(
          find.byKey(const Key('homeLayoutTile')), 100);
      expect(find.text('Standard tiles'), findsOneWidget);
      expect(find.byKey(const Key('homeLayoutEdit')), findsNothing);
      expect(find.textContaining('Make this bike active'), findsOneWidget);
      expect(find.byKey(const Key('homeLayoutReset')), findsNothing);
    });

    testWidgets('own tiles can be reset to the standard ones', (tester) async {
      final own = HomeLayout.standard.addRow(HomeArea.top, 1, HomeTile.climb);
      final store = await pump(tester,
          bikeId: 'road',
          bikes: twoBikes.copyWith(profiles: [
            BikeProfile(
                id: 'road',
                name: 'Road',
                colorArgb: 1,
                settings: BikeSettings(homeLayout: own)),
            twoBikes.profiles.last,
          ]));
      final reset = find.byKey(const Key('homeLayoutReset'));
      await tester.scrollUntilVisible(reset, 100);
      expect(find.text('Your own tiles'), findsOneWidget);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(saved(await store.load(), 'road').settings!.homeLayout,
          HomeLayout.standard);
      expect(find.text('Standard tiles'), findsOneWidget);
      expect(reset, findsNothing);
    });

    testWidgets('"Edit" goes to the map, editing', (tester) async {
      final router = GoRouter(initialLocation: '/bike-profiles/road', routes: [
        GoRoute(path: '/', builder: (context, state) => const Text('home')),
        GoRoute(
          path: '/bike-profiles/:id',
          builder: (context, state) =>
              BikeSettingsScreen(bikeId: state.pathParameters['id']!),
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          bikeProfilesStoreProvider
              .overrideWithValue(FakeBikeProfilesStore(twoBikes)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      final edit = find.byKey(const Key('homeLayoutEdit'));
      await tester.scrollUntilVisible(edit, 100);
      final container = ProviderScope.containerOf(tester.element(edit));
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(container.read(homeLayoutEditingProvider), isTrue);
    });
  });

  test('bikeSettingsSummary', () {
    expect(bikeSettingsSummary(const BikeSettings()),
        'Wheel 2105 mm · auto-pause below 5 km/h · auto-start off');
    expect(
        bikeSettingsSummary(const BikeSettings(
            autoPauseEnabled: false, autoStartEnabled: true)),
        'Wheel 2105 mm · auto-pause off · auto-start above 8 km/h');
    expect(
        bikeSettingsSummary(const BikeSettings(
            autoStartEnabled: true, autoStartSpeedKmh: 12.5)),
        'Wheel 2105 mm · auto-pause below 5 km/h · '
        'auto-start above 12.5 km/h');
  });
}
