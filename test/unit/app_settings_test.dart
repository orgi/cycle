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
    expect(back.mapZoom, 14);
  });

  test('the ride map style is the app\'s unless set; it round-trips and can '
      'be cleared', () {
    const app = AppSettings(colorScheme: AppColorScheme.light);
    expect(app.rideMapStyle, isNull);
    expect(app.rideMapScheme, AppColorScheme.light);
    expect(app.toJson(), isNot(contains('ride_map_style')));

    final own = app.copyWith(rideMapStyle: AppColorScheme.detailed);
    expect(own.rideMapScheme, AppColorScheme.detailed);
    final back = AppSettings.fromJson(own.toJson());
    expect(back, own);
    expect(back.rideMapStyle, AppColorScheme.detailed);
    // Other edits keep it; null puts it back to the app's.
    expect(own.copyWith(mapZoom: 12).rideMapStyle, AppColorScheme.detailed);
    expect(own.copyWith(rideMapStyle: null).rideMapScheme, AppColorScheme.light);
    // A removed Elements choice reads like the app's own setting does.
    expect(AppSettings.fromJson({'ride_map_style': 'elementsDark'}).rideMapStyle,
        AppColorScheme.detailedDark);
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

  test('keep screen on, continue a ride and places: defaults and round trip',
      () {
    const d = AppSettings();
    expect(d.keepScreenOnMinutes, 0); // off: only a ride holds the screen
    expect(d.continueRideWithinMinutes, 30);
    expect(d.continueRideWindow, const Duration(minutes: 30));
    expect(d.placesEnabled, isTrue);
    // An older build's settings have none of them: the same defaults.
    expect(AppSettings.fromJson(const {'units': 'metric'}), d);

    final s = d.copyWith(
        keepScreenOnMinutes: 15,
        continueRideWithinMinutes: 0,
        placesEnabled: false);
    expect(s.continueRideWindow, isNull);
    expect(AppSettings.fromJson(s.toJson()), s);
    expect(
        AppSettings.fromJson(
                {'keep_screen_on_min': -3, 'continue_ride_min': 'x'})
            .copyWith(),
        d);
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

  test('a stored Start/Stop button choice (before 0.12) is ignored', () {
    // The button is gone: rides start and stop on the TIME tile.
    final s = AppSettings.fromJson(const {
      'show_start_stop_button': true,
      'hardware_buttons': false,
    });
    expect(s, const AppSettings(hardwareButtonsEnabled: false));
    expect(s.toJson().containsKey('show_start_stop_button'), isFalse);
  });
}
