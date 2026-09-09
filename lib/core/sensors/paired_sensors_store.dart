import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sensor_service.dart';

/// Persists the sensors the user has paired (id, name, kinds), so they can be
/// recognised and reconnected automatically on the next app launch without a
/// fresh scan. Behind an interface for tests.
abstract class PairedSensorsStore {
  Future<List<PairedSensor>> load();
  Future<void> save(List<PairedSensor> sensors);
}

class SharedPrefsPairedSensorsStore implements PairedSensorsStore {
  // Pre-kinds format: a plain List<String> of device ids. Still read for
  // migration (kinds unknown until reconnect) but no longer written.
  static const _legacyKey = 'paired.sensors';
  static const _key = 'paired.sensors.v2';

  @override
  Future<List<PairedSensor>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List;
        return [
          for (final e in decoded)
            PairedSensor.fromJson(e as Map<String, dynamic>),
        ];
      } catch (_) {
        // fall through to legacy/empty below
      }
    }
    final legacyIds = prefs.getStringList(_legacyKey) ?? const [];
    return [
      for (final id in legacyIds) PairedSensor(id: id, name: id, kinds: const {}),
    ];
  }

  @override
  Future<void> save(List<PairedSensor> sensors) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final s in sensors) s.toJson()]));
  }
}
