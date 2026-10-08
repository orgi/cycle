import 'dart:convert';

import '../models/bike_profile.dart';
import '../services/bike_profiles/bike_profiles_state.dart';
import 'sync_clock.dart';

/// The synced part of the bike profiles: names/colours with their clocks, and
/// deletions. The active profile and per-bike sensor selection stay local.
class ProfilesDoc {
  const ProfilesDoc({required this.profiles, required this.deleted});

  final Map<String, BikeProfile> profiles;
  final Map<String, String> deleted;

  factory ProfilesDoc.of(BikeProfilesState s) => ProfilesDoc(
        profiles: {for (final p in s.profiles) p.id: p},
        deleted: s.deleted,
      );

  /// Newest edit wins per profile; a deletion wins over edits older than it.
  /// Commutative/associative, so every phone ends up with the same set.
  static ProfilesDoc merge(ProfilesDoc a, ProfilesDoc b) {
    final deleted = <String, String>{...a.deleted};
    b.deleted.forEach((id, clock) =>
        deleted[id] = SyncClock.max(deleted[id], clock)!);
    final profiles = <String, BikeProfile>{...a.profiles};
    b.profiles.forEach((id, p) {
      final current = profiles[id];
      if (current == null || _key(p).compareTo(_key(current)) > 0) {
        profiles[id] = p;
      }
    });
    profiles.removeWhere(
        (id, p) => SyncClock.compare(deleted[id], p.clock) > 0);
    return ProfilesDoc(profiles: profiles, deleted: deleted);
  }

  /// Clock first, then content as a deterministic tie-break. '\u0001' sorts
  /// below every clock character, so a missing clock is the oldest.
  static String _key(BikeProfile p) =>
      '${p.clock ?? ''}\u0001${p.name}\u0001${p.colorArgb}';

  /// Applies this merged doc to the local state: keeps local order and
  /// sensor selections, appends new profiles, fixes a deleted active id.
  BikeProfilesState applyTo(BikeProfilesState local) {
    final result = <BikeProfile>[];
    for (final p in local.profiles) {
      final m = profiles[p.id];
      if (m == null) continue;
      result.add(BikeProfile(
        id: p.id,
        name: m.name,
        colorArgb: m.colorArgb,
        clock: m.clock,
        sensorIds: p.sensorIds,
      ));
    }
    final known = local.profiles.map((p) => p.id).toSet();
    final added = profiles.values.where((p) => !known.contains(p.id)).toList()
      ..sort((x, y) => x.id.compareTo(y.id));
    for (final p in added) {
      result.add(BikeProfile(
          id: p.id, name: p.name, colorArgb: p.colorArgb, clock: p.clock));
    }
    final activeId = result.any((p) => p.id == local.activeId)
        ? local.activeId
        : result.firstOrNull?.id;
    return BikeProfilesState(
        profiles: result, activeId: activeId, deleted: deleted);
  }

  /// Comparable fingerprint: equal ⇔ nothing to exchange.
  String get signature {
    final ids = profiles.keys.toList()..sort();
    final del = deleted.keys.toList()..sort();
    return jsonEncode([
      for (final id in ids) _key(profiles[id]!),
      ...ids,
      for (final id in del) '$id=${deleted[id]}',
    ]);
  }

  List<int> encode() => utf8.encode(jsonEncode({
        'v': 1,
        'profiles': [
          for (final p in profiles.values)
            {'id': p.id, 'name': p.name, 'color': p.colorArgb, 'clock': p.clock},
        ],
        'deleted': deleted,
      }));

  static ProfilesDoc decode(List<int> bytes) {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return ProfilesDoc(
      profiles: {
        for (final raw in j['profiles'] as List)
          (raw as Map)['id'] as String: BikeProfile(
            id: raw['id'] as String,
            name: raw['name'] as String,
            colorArgb: raw['color'] as int,
            clock: raw['clock'] as String?,
          ),
      },
      deleted: {
        for (final e in ((j['deleted'] as Map?) ?? const {}).entries)
          e.key as String: e.value as String,
      },
    );
  }
}
