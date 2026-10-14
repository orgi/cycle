import 'dart:convert';
import 'dart:io';

import 'sync_clock.dart';

/// Separates the fields of a comparison key. Must sort below every character
/// a clock can contain, so a missing clock ('') orders before any real one.
const _sep = '\u0001';

/// One synced point: `[timeMs, lat, lon, alt, speed, hr, cadence, power,
/// speedFromSensor]` — compact positional JSON, nulls kept.
class RidePoint {
  const RidePoint({
    required this.time,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speedMps,
    this.heartRate,
    this.cadenceRpm,
    this.power,
    this.speedFromSensor,
  });

  final DateTime time;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speedMps;
  final int? heartRate;
  final double? cadenceRpm;
  final int? power;
  final bool? speedFromSensor;

  List<Object?> toJson() => [
        time.millisecondsSinceEpoch,
        latitude,
        longitude,
        altitude,
        speedMps,
        heartRate,
        cadenceRpm,
        power,
        speedFromSensor,
      ];

  factory RidePoint.fromJson(List<dynamic> j) => RidePoint(
        time: DateTime.fromMillisecondsSinceEpoch(j[0] as int),
        latitude: (j[1] as num).toDouble(),
        longitude: (j[2] as num).toDouble(),
        altitude: (j[3] as num?)?.toDouble(),
        speedMps: (j[4] as num?)?.toDouble(),
        heartRate: (j[5] as num?)?.toInt(),
        cadenceRpm: (j[6] as num?)?.toDouble(),
        power: (j[7] as num?)?.toInt(),
        speedFromSensor: j.length > 8 ? j[8] as bool? : null,
      );
}

/// The geometry part: points + the stats derived from them. [points] is null
/// when only the summary is known (a local ride whose points weren't loaded);
/// [pointCount] is always set.
class RideGeometry {
  const RideGeometry({
    required this.clock,
    required this.purged,
    required this.pointCount,
    required this.endedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.avgSpeedMps,
    required this.maxSpeedMps,
    this.batteryStartPercent,
    this.batteryEndPercent,
    this.points,
  });

  final String? clock;

  /// The ride was deleted long enough ago that its points were dropped. A
  /// purged copy beats an unpurged one with the same clock, so the purge
  /// spreads (and the full copies on the server get pruned). Restoring a ride
  /// re-stamps the clock, so restored points beat a purged copy.
  final bool purged;
  final int pointCount;
  final DateTime endedAt;
  final double distanceMeters;
  final int durationSeconds;
  final double avgSpeedMps;
  final double maxSpeedMps;
  final int? batteryStartPercent;
  final int? batteryEndPercent;
  final List<RidePoint>? points;

  /// Total order used to pick a winner: clock, then purged, then the copy
  /// with more data. Content tie-breaks keep the choice deterministic for
  /// rides last edited before sync existed (no clock on either side).
  String get orderKey => '${clock ?? ''}$_sep${purged ? 1 : 0}$_sep'
      '${pointCount.toString().padLeft(9, '0')}$_sep'
      '${(distanceMeters * 10).round().toString().padLeft(12, '0')}';

  RideGeometry withPoints(List<RidePoint>? points) => RideGeometry(
        clock: clock,
        purged: purged,
        pointCount: pointCount,
        endedAt: endedAt,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        avgSpeedMps: avgSpeedMps,
        maxSpeedMps: maxSpeedMps,
        batteryStartPercent: batteryStartPercent,
        batteryEndPercent: batteryEndPercent,
        points: points,
      );
}

/// One ride as synced. Identity is [startedAt] (whole seconds), the same key
/// every import already dedups on. Each part is versioned on its own, so a
/// rename on one phone and a bike change on another both survive a merge.
class RideDoc {
  const RideDoc({
    required this.startedAt,
    required this.name,
    required this.nameClock,
    required this.bikeProfileId,
    required this.bikeClock,
    required this.deletedAt,
    required this.deletedClock,
    required this.geometry,
  });

  static const formatVersion = 1;

  final DateTime startedAt;
  final String name;
  final String? nameClock;
  final String? bikeProfileId;
  final String? bikeClock;

  /// When the ride was moved to the trash; null = live. Effective only if
  /// [deletedClock] is newer than every other part (see [merge]).
  final DateTime? deletedAt;
  final String? deletedClock;
  final RideGeometry geometry;

  /// Sync key: start time in whole epoch seconds.
  int get key => startedAt.millisecondsSinceEpoch ~/ 1000;

  bool get isDeleted => deletedAt != null;

  String get _nameKey => '${nameClock ?? ''}$_sep$name';
  String get _bikeKey => '${bikeClock ?? ''}$_sep${bikeProfileId ?? ''}';
  String get _deletedKey =>
      '${deletedClock ?? ''}$_sep${deletedAt?.millisecondsSinceEpoch ?? ''}';

  /// Everything that decides a merge, in one comparable string: two docs with
  /// the same signature are interchangeable.
  String get signature => jsonEncode([_nameKey, _bikeKey, _deletedKey, geometry.orderKey]);

  /// Whether merging [other] into this doc changes nothing — i.e. the copy
  /// [other] came from holds nothing this one lacks and can be dropped.
  bool covers(RideDoc other) => merge(this, other).signature == signature;

  /// This doc without its points — what's cached per remote file.
  Map<String, dynamic> toMetaJson() {
    final j = toJson();
    (j['geometry'] as Map<String, dynamic>)['points'] = const [];
    return j;
  }

  static RideDoc fromMetaJson(String json) =>
      RideDoc.fromJson(jsonDecode(json) as Map<String, dynamic>);

  /// Part-by-part "newest edit wins" merge. Commutative and associative (each
  /// part is a max over a total order), so every phone converges on the same
  /// result whatever order the copies arrive in.
  ///
  /// Delete vs. edit: an edit made after the deletion brings the ride back —
  /// a later edit on another phone is never silently thrown away.
  static RideDoc merge(RideDoc a, RideDoc b) {
    final nameFrom = a._nameKey.compareTo(b._nameKey) >= 0 ? a : b;
    final bikeFrom = a._bikeKey.compareTo(b._bikeKey) >= 0 ? a : b;
    final delFrom = a._deletedKey.compareTo(b._deletedKey) >= 0 ? a : b;
    final geometry = a.geometry.orderKey.compareTo(b.geometry.orderKey) >= 0
        ? a.geometry
        : b.geometry;

    // The deletion is cleared but its clock kept: rewriting the clock (e.g.
    // to the edit's) would make the result depend on merge order, and phones
    // would stop converging. A cleared deletion sorts just below the original
    // one with the same clock, so re-merging the original clears it again.
    var deletedAt = delFrom.deletedAt;
    final deletedClock = delFrom.deletedClock;
    if (deletedAt != null && !geometry.purged) {
      final lastEdit = SyncClock.max(
          SyncClock.max(nameFrom.nameClock, bikeFrom.bikeClock), geometry.clock);
      if (SyncClock.compare(lastEdit, deletedClock) > 0) deletedAt = null;
    }
    return RideDoc(
      startedAt: a.startedAt,
      name: nameFrom.name,
      nameClock: nameFrom.nameClock,
      bikeProfileId: bikeFrom.bikeProfileId,
      bikeClock: bikeFrom.bikeClock,
      deletedAt: deletedAt,
      deletedClock: deletedClock,
      geometry: geometry,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': formatVersion,
        'started_at': startedAt.millisecondsSinceEpoch,
        'name': {'value': name, 'clock': nameClock},
        'bike': {'value': bikeProfileId, 'clock': bikeClock},
        'deleted': {
          'at': deletedAt?.millisecondsSinceEpoch,
          'clock': deletedClock,
        },
        'geometry': {
          'clock': geometry.clock,
          'purged': geometry.purged,
          'ended_at': geometry.endedAt.millisecondsSinceEpoch,
          'distance_m': geometry.distanceMeters,
          'duration_s': geometry.durationSeconds,
          'avg_mps': geometry.avgSpeedMps,
          'max_mps': geometry.maxSpeedMps,
          'battery_start': geometry.batteryStartPercent,
          'battery_end': geometry.batteryEndPercent,
          'point_count': geometry.pointCount,
          'points': [for (final p in geometry.points ?? const []) p.toJson()],
        },
      };

  factory RideDoc.fromJson(Map<String, dynamic> j) {
    final v = j['v'] as int? ?? 0;
    if (v > formatVersion) {
      throw FormatException('Ride written by a newer app version (format $v)');
    }
    final name = j['name'] as Map<String, dynamic>;
    final bike = j['bike'] as Map<String, dynamic>;
    final del = j['deleted'] as Map<String, dynamic>;
    final g = j['geometry'] as Map<String, dynamic>;
    final points = [
      for (final p in g['points'] as List) RidePoint.fromJson(p as List),
    ];
    DateTime? ms(Object? v) =>
        v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
    return RideDoc(
      startedAt: ms(j['started_at'])!,
      name: name['value'] as String,
      nameClock: name['clock'] as String?,
      bikeProfileId: bike['value'] as String?,
      bikeClock: bike['clock'] as String?,
      deletedAt: ms(del['at']),
      deletedClock: del['clock'] as String?,
      geometry: RideGeometry(
        clock: g['clock'] as String?,
        purged: g['purged'] as bool? ?? false,
        pointCount: (g['point_count'] as int?) ?? points.length,
        endedAt: ms(g['ended_at'])!,
        distanceMeters: (g['distance_m'] as num).toDouble(),
        durationSeconds: (g['duration_s'] as num).toInt(),
        avgSpeedMps: (g['avg_mps'] as num).toDouble(),
        maxSpeedMps: (g['max_mps'] as num).toDouble(),
        batteryStartPercent: (g['battery_start'] as num?)?.toInt(),
        batteryEndPercent: (g['battery_end'] as num?)?.toInt(),
        points: points,
      ),
    );
  }

  /// Gzipped JSON, the on-server form.
  List<int> encode() => gzip.encode(utf8.encode(jsonEncode(toJson())));

  static RideDoc decode(List<int> bytes) =>
      RideDoc.fromJson(jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>);
}
