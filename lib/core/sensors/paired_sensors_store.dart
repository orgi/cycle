import 'package:shared_preferences/shared_preferences.dart';

/// Persists the BLE device ids the user has paired, so they can be reconnected
/// automatically on the next app launch. Behind an interface for tests.
abstract class PairedSensorsStore {
  Future<List<String>> load();
  Future<void> save(List<String> deviceIds);
}

class SharedPrefsPairedSensorsStore implements PairedSensorsStore {
  static const _key = 'paired.sensors';

  @override
  Future<List<String>> load() async =>
      (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];

  @override
  Future<void> save(List<String> deviceIds) async =>
      (await SharedPreferences.getInstance()).setStringList(_key, deviceIds);
}
