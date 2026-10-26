import 'package:cycle/core/models/bike_settings.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/core/services/settings/settings_store.dart';
import 'package:cycle/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AppSettings JSON round-trips', () {
    const s = AppSettings(
      units: UnitSystem.imperial,
      hardwareButtonsEnabled: false,
      showStartStopButton: true,
      selectedMapFileName: 'Bayern.map',
      colorScheme: AppColorScheme.bw,
      mapZoom: 14,
      proximityHoldEnabled: true,
      legacyBikeSettings: BikeSettings(wheelCircumferenceMeters: 2.2),
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back, s);
    expect(back.proximityHoldEnabled, isTrue);
    expect(back.colorScheme, AppColorScheme.bw);
    expect(back.showStartStopButton, isTrue);
    expect(back.mapZoom, 14);
  });

  test('colorScheme defaults to dark and tolerates an unknown value', () {
    expect(const AppSettings().colorScheme, AppColorScheme.dark);
    expect(AppSettings.fromJson({'color_scheme': 'nonsense'}).colorScheme,
        AppColorScheme.dark);
  });

  test('a removed Elements choice becomes the detailed map of the same brightness',
      () {
    expect(AppSettings.fromJson({'color_scheme': 'elements'}).colorScheme,
        AppColorScheme.detailed);
    expect(AppSettings.fromJson({'color_scheme': 'elementsDark'}).colorScheme,
        AppColorScheme.detailedDark);
    // ... and is saved under the new name from then on.
    expect(
        AppSettings.fromJson({'color_scheme': 'elementsDark'})
            .toJson()['color_scheme'],
        'detailedDark');
  });

  test('selectedMapFileName defaults to null (auto) and copyWith can clear it',
      () {
    const auto = AppSettings();
    expect(auto.selectedMapFileName, isNull);
    expect(auto.toJson().containsKey('selected_map'), isFalse);

    final pinned = auto.copyWith(selectedMapFileName: 'Alps.map');
    expect(pinned.selectedMapFileName, 'Alps.map');
    // An unrelated copyWith preserves the selection.
    expect(pinned.copyWith(units: UnitSystem.imperial).selectedMapFileName,
        'Alps.map');
    // Explicit null resets to automatic.
    expect(pinned.copyWith(selectedMapFileName: null).selectedMapFileName,
        isNull);
  });

  test('hand-over-screen is opt-in', () {
    expect(const AppSettings().proximityHoldEnabled, isFalse);
    expect(AppSettings.fromJson(const {'units': 'metric'}).proximityHoldEnabled,
        isFalse);
  });

  test('AppSettings.fromJson tolerates missing/garbage fields', () {
    final s = AppSettings.fromJson({'units': 'nonsense'});
    expect(s.units, UnitSystem.metric);
    expect(s.hardwareButtonsEnabled, isTrue);
  });

  group('legacy (pre per-bike) wheel / auto-pause / auto-start', () {
    // What 0.7.x wrote: these four were app-wide settings.
    const old = {
      'units': 'metric',
      'wheel_circumference_m': 2.2,
      'auto_pause': false,
      'auto_pause_kmh': 3.5,
      'auto_start': true,
    };

    test('are read from an older build\'s settings', () {
      expect(
        AppSettings.fromJson(old).legacyBikeSettings,
        const BikeSettings(
          wheelCircumferenceMeters: 2.2,
          autoPauseEnabled: false,
          autoPauseSpeedKmh: 3.5,
          autoStartEnabled: true,
        ),
      );
    });

    test('survive saving other settings (and stay readable by old builds)',
        () {
      final saved = AppSettings.fromJson(old)
          .copyWith(units: UnitSystem.imperial, mapZoom: 12)
          .toJson();
      for (final key in ['wheel_circumference_m', 'auto_pause',
          'auto_pause_kmh', 'auto_start']) {
        expect(saved[key], old[key], reason: key);
      }
      expect(AppSettings.fromJson(saved).legacyBikeSettings!.autoPauseSpeedKmh,
          3.5);
    });

    test('are absent on a fresh install', () {
      expect(const AppSettings().legacyBikeSettings, isNull);
      expect(AppSettings.fromJson(const {'units': 'metric'}).legacyBikeSettings,
          isNull);
      expect(const AppSettings().toJson().containsKey('wheel_circumference_m'),
          isFalse);
    });
  });

  test('SharedPrefsSettingsStore persists and defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPrefsSettingsStore();

    expect(await store.load(), const AppSettings()); // defaults

    await store.save(const AppSettings(units: UnitSystem.imperial));
    expect((await store.load()).units, UnitSystem.imperial);
  });

  group('unit conversion', () {
    test('metric leaves values unchanged', () {
      expect(speedInUnits(30, UnitSystem.metric), 30);
      expect(distanceInUnits(10, UnitSystem.metric), 10);
    });

    test('imperial converts km->mi and km/h->mph', () {
      expect(speedInUnits(32.18688, UnitSystem.imperial), closeTo(20, 1e-3));
      expect(distanceInUnits(1.609344, UnitSystem.imperial), closeTo(1, 1e-6));
    });

    test('formatSpeed/formatDistance render the converted value', () {
      expect(formatSpeed(32.18688, UnitSystem.imperial), '20.00');
      expect(formatDistance(16.09344, UnitSystem.imperial), '10.00');
      expect(formatSpeed(30, UnitSystem.metric), '30.00');
    });
  });

  group('startStopButtonVisible', () {
    const defaults = AppSettings();

    test('hidden by default where the volume keys work (Android)', () {
      expect(defaults.startStopButtonVisible(volumeKeysSupported: true),
          isFalse);
    });

    test('iOS: hidden only while the hand-over-screen hold is on', () {
      expect(
          defaults.startStopButtonVisible(
              volumeKeysSupported: false, proximityHoldSupported: true),
          isTrue);
      final hold = defaults.copyWith(proximityHoldEnabled: true);
      expect(
          hold.startStopButtonVisible(
              volumeKeysSupported: false, proximityHoldSupported: true),
          isFalse);
      expect(
          hold
              .copyWith(showStartStopButton: true)
              .startStopButtonVisible(
                  volumeKeysSupported: false, proximityHoldSupported: true),
          isTrue);
    });

    test('always shown where the volume keys cannot start a ride (iOS)', () {
      // Otherwise a fresh iOS install has no way at all to start a ride.
      expect(defaults.startStopButtonVisible(volumeKeysSupported: false),
          isTrue);
    });

    test('shown when requested or when the volume keys are switched off', () {
      expect(
          defaults
              .copyWith(showStartStopButton: true)
              .startStopButtonVisible(volumeKeysSupported: true),
          isTrue);
      expect(
          defaults
              .copyWith(hardwareButtonsEnabled: false)
              .startStopButtonVisible(volumeKeysSupported: true),
          isTrue);
    });
  });
}
