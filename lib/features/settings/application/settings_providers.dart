import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/settings/app_settings.dart';
import '../../../core/services/settings/settings_store.dart';

/// Persists settings. Overridable in tests.
final settingsStoreProvider =
    Provider<SettingsStore>((ref) => SharedPrefsSettingsStore());

/// Live app settings. Loads once from the store, then updates flow through
/// [SettingsController.update]. Starts at defaults until the load completes.
final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // Load asynchronously; the UI rebuilds when the stored values arrive.
    ref.read(settingsStoreProvider).load().then((loaded) => state = loaded);
    return const AppSettings();
  }

  Future<void> update(AppSettings settings) async {
    state = settings;
    await ref.read(settingsStoreProvider).save(settings);
  }

  Future<void> setUnits(UnitSystem units) =>
      update(state.copyWith(units: units));

  Future<void> setWheelCircumference(double meters) =>
      update(state.copyWith(wheelCircumferenceMeters: meters));

  Future<void> setHardwareButtons(bool enabled) =>
      update(state.copyWith(hardwareButtonsEnabled: enabled));
}
