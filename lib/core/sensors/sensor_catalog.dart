import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'gatt.dart';

/// One of the rider's sensors as known across all their phones.
///
/// A sensor's Bluetooth id is *not* portable: Android uses the sensor's fixed
/// address (the same on every Android phone), but iOS hands every app a random
/// per-iPhone identifier instead. So sensors are matched across phones by
/// **name** ([key]: trimmed, lower-case) — cycling sensors advertise names
/// with a serial number (e.g. "HRM-Pro:123456"), which makes them unique in
/// practice. [address] is set only when an Android phone paired it, so other
/// Android phones can link it directly, without a scan.
class KnownSensor {
  const KnownSensor({
    required this.name,
    required this.kinds,
    this.address,
    this.clock,
    this.removed = false,
  });

  final String name;
  final Set<SensorKind> kinds;
  final String? address;

  /// Sync clock of the last pair/remove (`SyncClock`); null = oldest.
  final String? clock;

  /// Removed ("forgotten") — kept as a marker so other phones forget it too.
  final bool removed;

  String get key => keyOf(name);

  static String keyOf(String name) => name.trim().toLowerCase();

  KnownSensor copyWith({
    String? name,
    Set<SensorKind>? kinds,
    String? address,
    String? clock,
    bool? removed,
  }) =>
      KnownSensor(
        name: name ?? this.name,
        kinds: kinds ?? this.kinds,
        address: address ?? this.address,
        clock: clock ?? this.clock,
        removed: removed ?? this.removed,
      );

  /// Total order for "newest wins": clock, then content (deterministic ties).
  String get orderKey {
    final k = kinds.map((e) => e.name).toList()..sort();
    return '${clock ?? ''}\u0001${removed ? 1 : 0}\u0001$name\u0001'
        '${k.join(',')}\u0001${address ?? ''}';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'kinds': [for (final k in kinds) k.name],
        if (address != null) 'address': address,
        if (clock != null) 'clock': clock,
        if (removed) 'removed': true,
      };

  factory KnownSensor.fromJson(Map<String, dynamic> j) => KnownSensor(
        name: j['name'] as String,
        kinds: {
          for (final raw in (j['kinds'] as List? ?? const []))
            for (final k in SensorKind.values)
              if (k.name == raw) k,
        },
        address: j['address'] as String?,
        clock: j['clock'] as String?,
        removed: j['removed'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is KnownSensor && other.orderKey == orderKey;

  @override
  int get hashCode => orderKey.hashCode;
}

/// All known sensors by [KnownSensor.key]. Synced with the bike profiles.
class SensorCatalog {
  const SensorCatalog([this.entries = const {}]);

  static const empty = SensorCatalog();

  final Map<String, KnownSensor> entries;

  /// Sensors not removed.
  Iterable<KnownSensor> get active => entries.values.where((s) => !s.removed);

  KnownSensor? operator [](String key) => entries[key];

  SensorCatalog put(KnownSensor s) => SensorCatalog({...entries, s.key: s});

  /// Newest pair/remove wins per sensor. Commutative and associative.
  static SensorCatalog merge(SensorCatalog a, SensorCatalog b) {
    final out = <String, KnownSensor>{...a.entries};
    b.entries.forEach((key, s) {
      final current = out[key];
      if (current == null || s.orderKey.compareTo(current.orderKey) > 0) {
        out[key] = s;
      }
    });
    return SensorCatalog(out);
  }

  String get signature {
    final keys = entries.keys.toList()..sort();
    return jsonEncode([for (final k in keys) entries[k]!.orderKey]);
  }

  List<Map<String, dynamic>> toJson() =>
      [for (final s in entries.values) s.toJson()];

  factory SensorCatalog.fromJson(List<dynamic>? j) {
    final sensors = [
      for (final raw in j ?? const [])
        KnownSensor.fromJson(raw as Map<String, dynamic>),
    ];
    return SensorCatalog({for (final s in sensors) s.key: s});
  }

  @override
  bool operator ==(Object other) =>
      other is SensorCatalog && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// Persists the [SensorCatalog]. Behind an interface for tests.
abstract class SensorCatalogStore {
  Future<SensorCatalog> load();
  Future<void> save(SensorCatalog catalog);
}

class SharedPrefsSensorCatalogStore implements SensorCatalogStore {
  static const _key = 'sensor.catalog';

  @override
  Future<SensorCatalog> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return SensorCatalog.empty;
    try {
      return SensorCatalog.fromJson(jsonDecode(raw) as List);
    } catch (_) {
      return SensorCatalog.empty;
    }
  }

  @override
  Future<void> save(SensorCatalog catalog) async =>
      (await SharedPreferences.getInstance())
          .setString(_key, jsonEncode(catalog.toJson()));
}

class MemorySensorCatalogStore implements SensorCatalogStore {
  MemorySensorCatalogStore([this._catalog = SensorCatalog.empty]);
  SensorCatalog _catalog;
  @override
  Future<SensorCatalog> load() async => _catalog;
  @override
  Future<void> save(SensorCatalog catalog) async => _catalog = catalog;
}
