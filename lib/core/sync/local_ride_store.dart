import 'package:drift/drift.dart';

import '../db/database.dart';
import 'ride_doc.dart';

/// A local ride as sync sees it: its row id plus its [RideDoc] (points not
/// loaded — see [LocalRideStore.withPoints]).
class LocalRide {
  const LocalRide(this.trackId, this.doc);
  final int trackId;
  final RideDoc doc;
}

/// Bridges the drift database and [RideDoc]s.
class LocalRideStore {
  LocalRideStore(this._db);

  final AppDatabase _db;

  /// Every syncable ride by sync key. Only finished rides (`endedAt` set) —
  /// the ride being recorded is never synced. When several rows share a start
  /// time (a duplicate moved to the trash next to its original) the live one
  /// represents the key, so removing a duplicate never reads as "deleted".
  Future<Map<int, LocalRide>> rides() async {
    final counts = await _db.pointCounts();
    final rows = await _db.allTracksIncludingDeleted();
    final byKey = <int, Track>{};
    for (final t in rows) {
      if (t.endedAt == null) continue;
      final key = t.startedAt.millisecondsSinceEpoch ~/ 1000;
      final current = byKey[key];
      if (current == null || _prefer(t, current)) byKey[key] = t;
    }
    return {
      for (final e in byKey.entries)
        e.key: LocalRide(e.value.id, docOf(e.value, counts[e.value.id] ?? 0)),
    };
  }

  /// Live beats trashed; then lowest id (the original over a later copy).
  static bool _prefer(Track a, Track b) {
    final aLive = a.deletedAt == null, bLive = b.deletedAt == null;
    if (aLive != bLive) return aLive;
    return a.id < b.id;
  }

  static RideDoc docOf(Track t, int pointCount, [List<RidePoint>? points]) =>
      RideDoc(
        startedAt: t.startedAt,
        name: t.name,
        nameClock: t.nameClock,
        bikeProfileId: t.bikeProfileId,
        bikeClock: t.bikeClock,
        deletedAt: t.deletedAt,
        deletedClock: t.deletedClock,
        geometry: RideGeometry(
          clock: t.geometryClock,
          purged: t.pointsPurged,
          pointCount: pointCount,
          endedAt: t.endedAt ?? t.startedAt,
          distanceMeters: t.distanceMeters,
          durationSeconds: t.durationSeconds,
          avgSpeedMps: t.avgSpeedMps,
          maxSpeedMps: t.maxSpeedMps,
          batteryStartPercent: t.batteryStartPercent,
          batteryEndPercent: t.batteryEndPercent,
          points: points,
        ),
      );

  /// [ride]'s doc with its points loaded, ready to upload.
  Future<RideDoc> withPoints(LocalRide ride) async {
    final points = await _db.pointsFor(ride.trackId);
    final d = ride.doc;
    return RideDoc(
      startedAt: d.startedAt,
      name: d.name,
      nameClock: d.nameClock,
      bikeProfileId: d.bikeProfileId,
      bikeClock: d.bikeClock,
      deletedAt: d.deletedAt,
      deletedClock: d.deletedClock,
      geometry: d.geometry.withPoints([
        for (final p in points)
          RidePoint(
            time: p.time,
            latitude: p.latitude,
            longitude: p.longitude,
            altitude: p.altitude,
            speedMps: p.speedMps,
            heartRate: p.heartRate,
            cadenceRpm: p.cadenceRpm,
            power: p.power,
            speedFromSensor: p.speedFromSensor,
          ),
      ]),
    );
  }

  /// Whether applying [merged] over [local] would remove or replace data on
  /// this phone — the cue for a safety backup first.
  static bool isDestructive(LocalRide? local, RideDoc merged) {
    if (local == null) return false;
    final l = local.doc;
    if (merged.isDeleted && !l.isDeleted) return true;
    return merged.geometry.orderKey != l.geometry.orderKey &&
        l.geometry.pointCount > 0;
  }

  /// Writes [merged] (whose geometry must carry its points if it differs from
  /// the local one) into the DB in one transaction, keeping the remote clocks.
  Future<void> apply(LocalRide? local, RideDoc merged) async {
    final g = merged.geometry;
    final companion = TracksCompanion(
      startedAt: Value(merged.startedAt),
      name: Value(merged.name),
      nameClock: Value(merged.nameClock),
      bikeProfileId: Value(merged.bikeProfileId),
      bikeClock: Value(merged.bikeClock),
      deletedAt: Value(merged.deletedAt),
      deletedClock: Value(merged.deletedClock),
      geometryClock: Value(g.clock),
      pointsPurged: Value(g.purged),
      endedAt: Value(g.endedAt),
      distanceMeters: Value(g.distanceMeters),
      durationSeconds: Value(g.durationSeconds),
      avgSpeedMps: Value(g.avgSpeedMps),
      maxSpeedMps: Value(g.maxSpeedMps),
      batteryStartPercent: Value(g.batteryStartPercent),
      batteryEndPercent: Value(g.batteryEndPercent),
    );
    final replaceGeometry =
        local == null || local.doc.geometry.orderKey != g.orderKey;
    if (replaceGeometry && !g.purged && g.points == null) {
      throw StateError('apply() needs the points of a changed geometry');
    }
    await _db.transaction(() async {
      final int id;
      if (local == null) {
        id = await _db.into(_db.tracks).insert(companion);
      } else {
        id = local.trackId;
        await (_db.update(_db.tracks)..where((t) => t.id.equals(id)))
            .write(companion);
      }
      if (!replaceGeometry) return;
      await (_db.delete(_db.trackPoints)..where((p) => p.trackId.equals(id)))
          .go();
      if (g.purged) return;
      await _db.batch((b) => b.insertAll(_db.trackPoints, [
            for (final p in g.points!)
              TrackPointsCompanion.insert(
                trackId: id,
                time: p.time,
                latitude: p.latitude,
                longitude: p.longitude,
                altitude: Value(p.altitude),
                speedMps: Value(p.speedMps),
                heartRate: Value(p.heartRate),
                cadenceRpm: Value(p.cadenceRpm),
                power: Value(p.power),
                speedFromSensor: Value(p.speedFromSensor),
              ),
          ]));
    });
  }
}
