import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/core/services/settings/settings_store.dart';
import 'package:cycle/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AppSettings JSON round-trips', () {
    const s = AppSettings(
      units: UnitSystem.imperial,
      wheelCircumferenceMeters: 2.2,
      hardwareButtonsEnabled: false,
      showStartStopButton: true,
      selectedMapFileName: 'Bayern.map',
      colorScheme: AppColorScheme.bw,
      mapZoom: 14,
      autoStartEnabled: true,
      proximityHoldEnabled: true,
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back, s);
    expect(back.autoStartEnabled, isTrue);
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

  test('auto-start and hand-over-screen are opt-in', () {
    const d = AppSettings();
    expect(d.autoStartEnabled, isFalse);
    expect(d.proximityHoldEnabled, isFalse);
    final fromOld = AppSettings.fromJson(const {'units': 'metric'});
    expect(fromOld.autoStartEnabled, isFalse);
    expect(fromOld.proximityHoldEnabled, isFalse);
  });

  test('AppSettings.fromJson tolerates missing/garbage fields', () {
    final s = AppSettings.fromJson({'units': 'nonsense'});
    expect(s.units, UnitSystem.metric);
    expect(s.wheelCircumferenceMeters, 2.105);
    expect(s.hardwareButtonsEnabled, isTrue);
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
