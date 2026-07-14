import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'bike_profiles_state.dart';

/// Persists [BikeProfilesState]. Behind an interface so tests inject a fake.
abstract class BikeProfilesStore {
  Future<BikeProfilesState> load();
  Future<void> save(BikeProfilesState state);
}

class SharedPrefsBikeProfilesStore implements BikeProfilesStore {
  static const _key = 'bike.profiles';

  @override
  Future<BikeProfilesState> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return BikeProfilesState.empty;
    try {
      return BikeProfilesState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return BikeProfilesState.empty;
    }
  }

  @override
  Future<void> save(BikeProfilesState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.toJson()));
  }
}
