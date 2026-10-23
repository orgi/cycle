import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../db/database.dart';

/// Separates the fields of a comparison key; sorts below every character a
/// clock can contain, so a missing clock ('') orders before any real one.
const _sep = '\u0001';

/// One saved route as synced, without its GPX (which is stored once on the
/// server, named by [id]). Two parts are versioned on their own: the name
/// ([nameClock]) and whether it's deleted ([deletedClock], which every import
/// stamps too, so the newest of "deleted" and "imported" wins).
class RouteEntry {
  const RouteEntry({
    required this.id,
    required this.name,
    required this.nameClock,
    required this.importedAt,
    required this.deletedAt,
    required this.deletedClock,
    required this.distanceMeters,
  });

  /// A fingerprint of the route's geometry (`FollowRoute.fingerprint`).
  final String id;
  final String name;
  final String? nameClock;
  final DateTime importedAt;
  final DateTime? deletedAt;
  final String? deletedClock;
  final double distanceMeters;

  bool get isDeleted => deletedAt != null;

  factory RouteEntry.ofRow(SavedRouteInfo r) => RouteEntry(
        id: r.id,
        name: r.name,
        nameClock: r.nameClock,
        importedAt: r.importedAt,
        deletedAt: r.deletedAt,
        deletedClock: r.deletedClock,
        distanceMeters: r.distanceMeters,
      );

  /// The row to store. Without [gpx] a stored GPX is kept; a deleted route
  /// drops it.
  SavedRoutesCompanion toRow([String? gpx]) => SavedRoutesCompanion(
        id: Value(id),
        name: Value(name),
        nameClock: Value(nameClock),
        gpx: isDeleted
            ? const Value(null)
            : (gpx == null ? const Value.absent() : Value(gpx)),
        distanceMeters: Value(distanceMeters),
        importedAt: Value(importedAt),
        deletedAt: Value(deletedAt),
        deletedClock: Value(deletedClock),
      );

  String get _nameKey => '${nameClock ?? ''}$_sep$name';

  // A deletion beats a live copy with the same clock.
  String get _deletedKey =>
      '${deletedClock ?? ''}$_sep${deletedAt?.millisecondsSinceEpoch ?? ''}';

  /// Newest name and newest deleted-state win; [importedAt] is the earliest.
  /// Commutative and associative, so phones converge in any order.
  static RouteEntry merge(RouteEntry a, RouteEntry b) {
    final n = a._nameKey.compareTo(b._nameKey) >= 0 ? a : b;
    final d = a._deletedKey.compareTo(b._deletedKey) >= 0 ? a : b;
    return RouteEntry(
      id: a.id,
      name: n.name,
      nameClock: n.nameClock,
      importedAt: a.importedAt.isBefore(b.importedAt) ? a.importedAt : b.importedAt,
      deletedAt: d.deletedAt,
      deletedClock: d.deletedClock,
      distanceMeters:
          a.distanceMeters >= b.distanceMeters ? a.distanceMeters : b.distanceMeters,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': {'value': name, 'clock': nameClock},
        'imported_at': importedAt.millisecondsSinceEpoch,
        'deleted': {'at': deletedAt?.millisecondsSinceEpoch, 'clock': deletedClock},
        'distance': distanceMeters,
      };

  factory RouteEntry.fromJson(Map<String, dynamic> j) {
    final name = j['name'] as Map<String, dynamic>;
    final del = j['deleted'] as Map<String, dynamic>;
    final deletedMs = del['at'] as int?;
    return RouteEntry(
      id: j['id'] as String,
      name: name['value'] as String,
      nameClock: name['clock'] as String?,
      importedAt: DateTime.fromMillisecondsSinceEpoch(j['imported_at'] as int),
      deletedAt:
          deletedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(deletedMs),
      deletedClock: del['clock'] as String?,
      distanceMeters: (j['distance'] as num).toDouble(),
    );
  }

  /// Equal for equal content; used to spot what changed.
  String get signature => jsonEncode(toJson());
}

/// A device's view of every saved route (`routes/index/<deviceId>.json` on
/// the server), merged from all devices' files like the bike profiles.
class RoutesIndex {
  const RoutesIndex(this.routes);

  static const formatVersion = 1;

  final Map<String, RouteEntry> routes;

  factory RoutesIndex.ofRows(Iterable<SavedRouteInfo> rows) =>
      RoutesIndex({for (final r in rows) r.id: RouteEntry.ofRow(r)});

  static RoutesIndex merge(RoutesIndex a, RoutesIndex b) {
    final routes = <String, RouteEntry>{...a.routes};
    b.routes.forEach((id, e) {
      final current = routes[id];
      routes[id] = current == null ? e : RouteEntry.merge(current, e);
    });
    return RoutesIndex(routes);
  }

  String get signature => jsonEncode([
        for (final id in routes.keys.toList()..sort()) routes[id]!.toJson(),
      ]);

  List<int> encode() => utf8.encode(jsonEncode({
        'v': formatVersion,
        'routes': [for (final e in routes.values) e.toJson()],
      }));

  static RoutesIndex decode(List<int> bytes) {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } on Object catch (e) {
      throw FormatException('Unreadable route index: $e');
    }
    final v = j['v'] as int? ?? 0;
    if (v > formatVersion) {
      throw FormatException('Route index written by a newer app version (format $v)');
    }
    return RoutesIndex({
      for (final raw in j['routes'] as List)
        (raw as Map<String, dynamic>)['id'] as String: RouteEntry.fromJson(raw),
    });
  }
}

/// A route's GPX as stored on the server: gzipped UTF-8.
List<int> encodeRouteGpx(String gpx) => gzip.encode(utf8.encode(gpx));

String decodeRouteGpx(List<int> bytes) {
  try {
    return utf8.decode(gzip.decode(bytes));
  } on Object catch (e) {
    throw FormatException('Unreadable route GPX: $e');
  }
}
