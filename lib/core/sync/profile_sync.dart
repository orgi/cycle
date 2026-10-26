import 'dart:convert';

import '../models/bike_profile.dart';
import '../models/bike_settings.dart';
import '../sensors/sensor_catalog.dart';
import '../services/bike_profiles/bike_profiles_state.dart';
import 'sync_clock.dart';

/// The synced part of the bike profiles: names/colours, each bike's sensor
/// choice (by sensor name) and its settings (wheel size, auto-pause,
/// auto-start), each with its own clock; deletions; merge aliases; and the
/// [sensors] catalog. The active profile and this phone's sensor *ids*
/// stay local.
class ProfilesDoc {
  const ProfilesDoc({
    required this.profiles,
    required this.deleted,
    this.aliases = const {},
    this.sensors = SensorCatalog.empty,
  });

  final Map<String, BikeProfile> profiles;
  final Map<String, String> deleted;

  /// Merged-away id → surviving id (see [merge]).
  final Map<String, String> aliases;

  final SensorCatalog sensors;

  factory ProfilesDoc.of(BikeProfilesState s,
          [SensorCatalog sensors = SensorCatalog.empty]) =>
      ProfilesDoc(
        profiles: {for (final p in s.profiles) p.id: p},
        deleted: s.deleted,
        aliases: s.aliases,
        sensors: sensors,
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
      profiles[id] = current == null ? p : _mergeOne(current, p);
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
      // The survivor keeps the newest sensor choice and the newest settings
      // of the group.
      var survivor = profiles[ids.first]!;
      for (final id in ids.skip(1)) {
        final other = profiles[id]!;
        survivor = _compose(
          survivor,
          sensors: _sensorKey(other).compareTo(_sensorKey(survivor)) > 0
              ? other
              : survivor,
          settings: _settingsKey(other).compareTo(_settingsKey(survivor)) > 0
              ? other
              : survivor,
        );
      }
      profiles[ids.first] = survivor;
    }
    profiles.removeWhere((id, _) => aliases.containsKey(id));
    return ProfilesDoc(
      profiles: profiles,
      deleted: deleted,
      aliases: aliases,
      sensors: SensorCatalog.merge(a.sensors, b.sensors),
    );
  }

  /// Name/colour, the sensor choice and the settings are separate parts:
  /// each takes the newer of the two, so editing one on a phone never undoes
  /// another.
  static BikeProfile _mergeOne(BikeProfile x, BikeProfile y) => _compose(
        _key(y).compareTo(_key(x)) > 0 ? y : x,
        sensors: _sensorKey(y).compareTo(_sensorKey(x)) > 0 ? y : x,
        settings: _settingsKey(y).compareTo(_settingsKey(x)) > 0 ? y : x,
      );

  /// [base]'s name/colour with [sensors]' sensor choice and [settings]'
  /// settings.
  static BikeProfile _compose(BikeProfile base,
          {required BikeProfile sensors, required BikeProfile settings}) =>
      BikeProfile(
        id: base.id,
        name: base.name,
        colorArgb: base.colorArgb,
        clock: base.clock,
        sensorIds: base.sensorIds,
        sensorKeys: sensors.sensorKeys,
        sensorsClock: sensors.sensorsClock,
        settings: settings.settings,
        settingsClock: settings.settingsClock,
      );

  static String _sensorKey(BikeProfile p) {
    final keys = p.sensorKeys == null ? '*' : (p.sensorKeys!.toList()..sort()).join(',');
    return '${p.sensorsClock ?? ''}\u0001$keys';
  }

  /// Like [_key]: clock, then content. No settings (`null`, a phone that
  /// doesn't sync them yet) has no clock either, so it's the oldest.
  static String _settingsKey(BikeProfile p) =>
      '${p.settingsClock ?? ''}\u0001${jsonEncode(p.settings?.toJson())}';

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
        sensorKeys: m.sensorKeys,
        sensorsClock: m.sensorsClock,
        settings: m.settings,
        settingsClock: m.settingsClock,
      ));
    }
    final added = profiles.values.where((p) => !placed.contains(p.id)).toList()
      ..sort((x, y) => x.id.compareTo(y.id));
    for (final p in added) {
      result.add(BikeProfile(
          id: p.id,
          name: p.name,
          colorArgb: p.colorArgb,
          clock: p.clock,
          sensorKeys: p.sensorKeys,
          sensorsClock: p.sensorsClock,
          settings: p.settings,
          settingsClock: p.settingsClock));
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
      for (final id in ids) _sensorKey(profiles[id]!),
      for (final id in ids) _settingsKey(profiles[id]!),
      ...ids,
      for (final id in del) '$id=${deleted[id]}',
      for (final id in (aliases.keys.toList()..sort())) '$id>${aliases[id]}',
      sensors.signature,
    ]);
  }

  List<int> encode() => utf8.encode(jsonEncode({
        'v': 1,
        'profiles': [
          for (final p in profiles.values)
            {
              'id': p.id,
              'name': p.name,
              'color': p.colorArgb,
              'clock': p.clock,
              if (p.sensorKeys != null) 'sensor_keys': p.sensorKeys!.toList(),
              if (p.sensorsClock != null) 'sensors_clock': p.sensorsClock,
              if (p.settings != null) 'settings': p.settings!.toJson(),
              if (p.settingsClock != null) 'settings_clock': p.settingsClock,
            },
        ],
        'sensors': sensors.toJson(),
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
            sensorKeys: (raw['sensor_keys'] as List?)
                ?.map((e) => e as String)
                .toSet(),
            sensorsClock: raw['sensors_clock'] as String?,
            settings: raw['settings'] is Map
                ? BikeSettings.fromJson(
                    (raw['settings'] as Map).cast<String, dynamic>())
                : null,
            settingsClock: raw['settings_clock'] as String?,
          ),
      },
      sensors: SensorCatalog.fromJson(j['sensors'] as List?),
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
