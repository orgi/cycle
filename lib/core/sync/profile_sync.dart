import 'dart:convert';

import '../models/bike_profile.dart';
import '../services/bike_profiles/bike_profiles_state.dart';
import 'sync_clock.dart';

/// The synced part of the bike profiles: names/colours with their clocks,
/// deletions, and merge aliases. The active profile and per-bike sensor
/// selection stay local.
class ProfilesDoc {
  const ProfilesDoc({
    required this.profiles,
    required this.deleted,
    this.aliases = const {},
  });

  final Map<String, BikeProfile> profiles;
  final Map<String, String> deleted;

  /// Merged-away id → surviving id (see [merge]).
  final Map<String, String> aliases;

  factory ProfilesDoc.of(BikeProfilesState s) => ProfilesDoc(
        profiles: {for (final p in s.profiles) p.id: p},
        deleted: s.deleted,
        aliases: s.aliases,
      );

  /// Newest edit wins per profile; a deletion wins over edits older than it.
  ///
  /// **Same name = same bike.** A bike created separately on two phones has
  /// two ids; showing both is just a duplicate (seen on real phones: every
  /// bike twice). Live profiles whose names match (trimmed, ignoring case)
  /// are merged into the one with the smallest id, and the others become
  /// aliases of it — rides recorded against an alias are read as the
  /// survivor. The survivor is chosen the same way on every phone, and
  /// aliases only ever accumulate, so the merge stays order-independent.
  static ProfilesDoc merge(ProfilesDoc a, ProfilesDoc b) {
    final deleted = <String, String>{...a.deleted};
    b.deleted.forEach((id, clock) =>
        deleted[id] = SyncClock.max(deleted[id], clock)!);
    final aliases = <String, String>{...a.aliases};
    b.aliases.forEach((from, to) {
      final current = aliases[from];
      aliases[from] = current == null || to.compareTo(current) < 0 ? to : current;
    });
    final profiles = <String, BikeProfile>{...a.profiles};
    b.profiles.forEach((id, p) {
      final current = profiles[id];
      if (current == null || _key(p).compareTo(_key(current)) > 0) {
        profiles[id] = p;
      }
    });
    profiles.removeWhere(
        (id, p) => SyncClock.compare(deleted[id], p.clock) > 0);

    final byName = <String, List<String>>{};
    for (final p in profiles.values) {
      if (aliases.containsKey(p.id)) continue;
      (byName[normalizeName(p.name)] ??= []).add(p.id);
    }
    for (final ids in byName.values) {
      if (ids.length < 2) continue;
      ids.sort();
      for (final id in ids.skip(1)) {
        aliases[id] = ids.first;
      }
    }
    profiles.removeWhere((id, _) => aliases.containsKey(id));
    return ProfilesDoc(profiles: profiles, deleted: deleted, aliases: aliases);
  }

  static String normalizeName(String name) => name.trim().toLowerCase();

  /// Follows [aliases] (possibly chained) to the surviving id.
  static String? resolve(Map<String, String> aliases, String? id) {
    var current = id;
    for (var i = 0; current != null && i < 16; i++) {
      final next = aliases[current];
      if (next == null) return current;
      current = next;
    }
    return current;
  }

  /// Clock first, then content as a deterministic tie-break. '\u0001' sorts
  /// below every clock character, so a missing clock is the oldest.
  static String _key(BikeProfile p) =>
      '${p.clock ?? ''}\u0001${p.name}\u0001${p.colorArgb}';

  /// Applies this merged doc to the local state: keeps local order and
  /// sensor selections (a merged-away profile's selection is folded into its
  /// survivor), appends new profiles, fixes a deleted/merged active id.
  BikeProfilesState applyTo(BikeProfilesState local) {
    // Sensor selections re-keyed to surviving ids: the union of the merged
    // profiles' selections, or null ("all sensors") if any of them had that.
    final members = <String, List<BikeProfile>>{};
    for (final p in local.profiles) {
      (members[resolve(aliases, p.id)!] ??= []).add(p);
    }
    Set<String>? sensorsOf(String id) {
      final ps = members[id] ?? const <BikeProfile>[];
      if (ps.isEmpty || ps.any((p) => p.sensorIds == null)) return null;
      return {for (final p in ps) ...p.sensorIds!};
    }

    final result = <BikeProfile>[];
    final placed = <String>{};
    for (final p in local.profiles) {
      final id = resolve(aliases, p.id)!;
      final m = profiles[id];
      if (m == null || !placed.add(id)) continue;
      result.add(BikeProfile(
        id: id,
        name: m.name,
        colorArgb: m.colorArgb,
        clock: m.clock,
        sensorIds: sensorsOf(id),
      ));
    }
    final added = profiles.values.where((p) => !placed.contains(p.id)).toList()
      ..sort((x, y) => x.id.compareTo(y.id));
    for (final p in added) {
      result.add(BikeProfile(
          id: p.id, name: p.name, colorArgb: p.colorArgb, clock: p.clock));
    }
    final active = resolve(aliases, local.activeId);
    final activeId =
        result.any((p) => p.id == active) ? active : result.firstOrNull?.id;
    return BikeProfilesState(
        profiles: result, activeId: activeId, deleted: deleted, aliases: aliases);
  }

  /// Comparable fingerprint: equal ⇔ nothing to exchange.
  String get signature {
    final ids = profiles.keys.toList()..sort();
    final del = deleted.keys.toList()..sort();
    return jsonEncode([
      for (final id in ids) _key(profiles[id]!),
      ...ids,
      for (final id in del) '$id=${deleted[id]}',
      for (final id in (aliases.keys.toList()..sort())) '$id>${aliases[id]}',
    ]);
  }

  List<int> encode() => utf8.encode(jsonEncode({
        'v': 1,
        'profiles': [
          for (final p in profiles.values)
            {'id': p.id, 'name': p.name, 'color': p.colorArgb, 'clock': p.clock},
        ],
        'deleted': deleted,
        'aliases': aliases,
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
      aliases: {
        for (final e in ((j['aliases'] as Map?) ?? const {}).entries)
          e.key as String: e.value as String,
      },
    );
  }
}
