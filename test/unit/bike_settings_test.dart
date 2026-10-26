import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:cycle/features/settings/application/settings_providers.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  const custom = BikeSettings(
    wheelCircumferenceMeters: 2.3,
    autoPauseEnabled: false,
    autoPauseSpeedKmh: 3.5,
    autoStartEnabled: true,
    autoStartSpeedKmh: 12,
  );

  group('BikeSettings', () {
    test('defaults are the former app-wide defaults', () {
      const d = BikeSettings();
      expect(d.wheelCircumferenceMeters, 2.105);
      expect(d.autoPauseEnabled, isTrue);
      expect(d.autoPauseSpeedKmh, 5.0);
      expect(d.autoStartEnabled, isFalse);
      expect(d.autoStartSpeedKmh, 8.0); // the speed that used to be fixed
      expect(d.autoPauseThresholdMps, closeTo(5 / 3.6, 1e-12));
    });

    test('JSON round-trips', () {
      expect(BikeSettings.fromJson(custom.toJson()), custom);
    });

    test('missing or garbage fields fall back to the defaults', () {
      expect(BikeSettings.fromJson(const {}), const BikeSettings());
      expect(
        BikeSettings.fromJson(const {
          'wheel_circumference_m': -1,
          'auto_pause': 'yes',
          'auto_pause_kmh': 'fast',
          'auto_start': 1,
          'auto_start_kmh': 0,
        }),
        const BikeSettings(),
      );
    });
  });

  group('BikeProfile with settings', () {
    test('JSON round-trips its settings and their clock', () {
      const p = BikeProfile(
        id: 'b',
        name: 'MTB',
        colorArgb: 1,
        settings: custom,
        settingsClock: '000000000000009@x',
      );
      final back = BikeProfile.fromJson(p.toJson());
      expect(back, p);
      expect(back.settings, custom);
    });

    test('a profile saved before per-bike settings has none', () {
      final p = BikeProfile.fromJson(const {'id': 'b', 'name': 'B', 'color': 1});
      expect(p.settings, isNull);
      expect(p.settingsClock, isNull);
      expect(p.toJson().containsKey('settings'), isFalse);
    });

    test('settings are part of equality', () {
      const a = BikeProfile(id: 'b', name: 'B', colorArgb: 1);
      expect(a == a.copyWith(settings: custom), isFalse);
      expect(a.copyWith(settings: custom), a.copyWith(settings: custom));
    });
  });

  group('bikeSettingsFor', () {
    const legacy = BikeSettings(wheelCircumferenceMeters: 2.2);
    const bikes = BikeProfilesState(
      profiles: [
        BikeProfile(id: 'road', name: 'Road', colorArgb: 1),
        BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2, settings: custom),
      ],
      activeId: 'mtb',
      aliases: {'old-mtb': 'mtb'},
    );

    test('a bike with settings of its own uses them', () {
      expect(bikeSettingsFor(bikes, 'mtb', legacy: legacy), custom);
    });

    test('a bike without uses the phone\'s former app-wide values', () {
      expect(bikeSettingsFor(bikes, 'road', legacy: legacy), legacy);
      // ... or the defaults on a phone that never had any.
      expect(bikeSettingsFor(bikes, 'road'), const BikeSettings());
    });

    test('no bike, or a deleted one, uses the active bike\'s', () {
      expect(bikeSettingsFor(bikes, null, legacy: legacy), custom);
      expect(bikeSettingsFor(bikes, 'deleted', legacy: legacy), custom);
    });

    test('a merged-away bike id follows its alias', () {
      expect(
          bikeSettingsFor(bikes.copyWith(activeId: 'road'), 'old-mtb'), custom);
    });

    test('before the profiles load, the legacy values or defaults', () {
      expect(bikeSettingsFor(BikeProfilesState.empty, null, legacy: legacy),
          legacy);
      expect(bikeSettingsFor(BikeProfilesState.empty, 'x'),
          const BikeSettings());
    });
  });

  group('BikeProfilesController', () {
    late ProviderContainer container;
    late FakeBikeProfilesStore store;

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    ProviderContainer build(BikeProfilesState bikes,
        {AppSettings settings = const AppSettings()}) {
      store = FakeBikeProfilesStore(bikes);
      final c = ProviderContainer(overrides: [
        bikeProfilesStoreProvider.overrideWithValue(store),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore(settings)),
      ]);
      c.listen(bikeProfilesProvider, (_, _) {});
      c.listen(activeBikeSettingsProvider, (_, _) {});
      return c;
    }

    tearDown(() => container.dispose());

    test('setSettings sets one bike\'s settings with a sync clock', () async {
      container = build(oneBike());
      await settle();
      await container
          .read(bikeProfilesProvider.notifier)
          .setSettings('bike', custom);
      final bike = (await store.load()).profiles.single;
      expect(bike.settings, custom);
      expect(bike.settingsClock, isNotNull);
      expect(container.read(activeBikeSettingsProvider), custom);
    });

    test('a new bike starts with a copy of the active bike\'s settings',
        () async {
      container = build(oneBike(custom));
      await settle();
      expect(await container.read(bikeProfilesProvider.notifier).add('Gravel'),
          isTrue);
      final gravel = container
          .read(bikeProfilesProvider)
          .profiles
          .firstWhere((p) => p.name == 'Gravel');
      expect(gravel.settings, custom);
      expect(gravel.settingsClock, isNotNull);
    });

    test('a new bike next to an upgraded one uses the same former values',
        () async {
      container = build(oneBike(),
          settings: AppSettings.fromJson(const {'wheel_circumference_m': 2.25}));
      await settle();
      await container.read(bikeProfilesProvider.notifier).add('Gravel');
      final gravel = container
          .read(bikeProfilesProvider)
          .profiles
          .firstWhere((p) => p.name == 'Gravel');
      expect(gravel.settings, isNull);
      expect(
          container.read(bikeSettingsLookupProvider)(gravel.id)
              .wheelCircumferenceMeters,
          2.25);
    });

    test('the active bike\'s settings follow a bike switch', () async {
      container = build(const BikeProfilesState(
        profiles: [
          BikeProfile(id: 'road', name: 'Road', colorArgb: 1),
          BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2, settings: custom),
        ],
        activeId: 'road',
      ));
      await settle();
      expect(container.read(activeBikeSettingsProvider), const BikeSettings());
      await container.read(bikeProfilesProvider.notifier).setActive('mtb');
      expect(container.read(activeBikeSettingsProvider), custom);
    });
  });
}
