import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/ride_place.dart';

/// Persists the [RidePlace]s. Behind an interface so tests inject a fake.
abstract class RidePlacesStore {
  Future<List<RidePlace>> load();
  Future<void> save(List<RidePlace> places);
}

class SharedPrefsRidePlacesStore implements RidePlacesStore {
  static const _key = 'ride.places';

  @override
  Future<List<RidePlace>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const [];
    try {
      return decodeRidePlaces(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<RidePlace> places) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final p in places) p.toJson()]),
    );
  }
}

/// The places in a stored JSON list; entries that aren't usable are skipped.
List<RidePlace> decodeRidePlaces(Object? json) => [
  if (json is List)
    for (final e in json)
      if (e is Map) ?RidePlace.fromJson(e.cast<String, dynamic>()),
];
