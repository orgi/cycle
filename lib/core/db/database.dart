import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../services/backup_service.dart';
import '../sync/sync_clock.dart';
import 'migration_backup.dart';

part 'database.g.dart';

/// One recorded ride.
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant('Ride'))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  RealColumn get distanceMeters => real().withDefault(const Constant(0))();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  RealColumn get avgSpeedMps => real().withDefault(const Constant(0))();
  RealColumn get maxSpeedMps => real().withDefault(const Constant(0))();
  // Battery level (%) at start/stop, for the drain stat.
  IntColumn get batteryStartPercent => integer().nullable()();
  IntColumn get batteryEndPercent => integer().nullable()();
  // Which bike this ride was recorded on (BikeProfile.id from bike_profiles
  // prefs — not a SQL foreign key, profiles live outside this DB). Null for
  // rides recorded before profiles existed, or if the profile was deleted.
  TextColumn get bikeProfileId => text().nullable()();

  // Sync (schema v5). A ride is synced as four independently-versioned parts —
  // name, bike, geometry (points + stats) and deleted — each with its own
  // clock (`SyncClock`: zero-padded epoch ms + '@' + device id, so plain
  // string comparison orders them). Null = never edited since v5, which sorts
  // before every real clock. See `lib/core/sync/ride_doc.dart`.
  TextColumn get nameClock => text().nullable()();
  TextColumn get bikeClock => text().nullable()();
  TextColumn get geometryClock => text().nullable()();
  TextColumn get deletedClock => text().nullable()();

  // Trash: a deleted ride keeps its row (and, until purged, its points) with
  // [deletedAt] set, hidden from every list, restorable from "Recently
  // deleted" for the retention period. After that its points are purged and
  // [pointsPurged] is set, but the row stays as a tiny marker so sync knows the
  // ride was deleted and an outdated phone can't bring it back.
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get pointsPurged =>
      boolean().withDefault(const Constant(false))();
}

/// A single sample within a ride (position + optional sensor values).
class TrackPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get time => dateTime()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get altitude => real().nullable()();
  RealColumn get speedMps => real().nullable()();
  IntColumn get heartRate => integer().nullable()();
  RealColumn get cadenceRpm => real().nullable()();
  IntColumn get power => integer().nullable()();
  // Whether speedMps at this point came from a BLE wheel-speed sensor (true)
  // or GPS (false). Null for points recorded before this was tracked — those
  // can't be retroactively classified, since the source itself wasn't stored,
  // only the resulting number.
  BoolColumn get speedFromSensor => boolean().nullable()();
}

/// Remote sync files this device has already seen, with the ETag it saw and
/// the file's ride without points (`RideDoc.toMetaJson`) — so an unchanged
/// file is never downloaded again, yet can still be compared and pruned.
class SyncRemoteFiles extends Table {
  TextColumn get path => text()();
  TextColumn get etag => text().nullable()();
  TextColumn get meta => text()();

  @override
  Set<Column> get primaryKey => {path};
}

/// Small key/value store that must live with the ride data (e.g. this
/// installation's sync device id, used in every edit clock).
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Tracks, TrackPoints, SyncRemoteFiles, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => kSchemaVersion;

  static const kSchemaVersion = 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(tracks, tracks.batteryStartPercent);
            await m.addColumn(tracks, tracks.batteryEndPercent);
          }
          if (from < 3) {
            await m.addColumn(tracks, tracks.bikeProfileId);
          }
          if (from < 4) {
            await m.addColumn(trackPoints, trackPoints.speedFromSensor);
          }
          if (from < 5) {
            await m.addColumn(tracks, tracks.nameClock);
            await m.addColumn(tracks, tracks.bikeClock);
            await m.addColumn(tracks, tracks.geometryClock);
            await m.addColumn(tracks, tracks.deletedClock);
            await m.addColumn(tracks, tracks.deletedAt);
            await m.addColumn(tracks, tracks.pointsPurged);
            await m.createTable(syncRemoteFiles);
            await m.createTable(syncMeta);
          }
        },
        beforeOpen: (_) async {
          // Required for the trackPoints → tracks ON DELETE CASCADE to fire.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _open() => LazyDatabase(() async {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/cycle.sqlite');
        // Never migrate the only copy of someone's rides: snapshot it first.
        await backupBeforeMigration(
          file,
          kSchemaVersion,
          backupsDir: () async => Directory(
              '${(await BackupService.defaultRoot()).path}/backups'),
        );
        return NativeDatabase.createInBackground(file);
      });

  // --- Sync clocks -----------------------------------------------------------

  String? _deviceId;

  /// This installation's sync device id — generated once and stored in the DB
  /// itself, so it's available synchronously to every edit below.
  Future<String> deviceId() async {
    final cached = _deviceId;
    if (cached != null) return cached;
    final row = await (select(syncMeta)..where((m) => m.key.equals('device_id')))
        .getSingleOrNull();
    if (row != null) return _deviceId = row.value;
    final id = newDeviceId();
    await into(syncMeta).insertOnConflictUpdate(
        SyncMetaCompanion.insert(key: 'device_id', value: id));
    return _deviceId = id;
  }

  /// Overridable "now" for tests.
  DateTime Function() now = DateTime.now;

  /// A fresh edit clock for this device.
  Future<String> stamp() async => SyncClock.format(now(), await deviceId());

  Future<String?> meta(String key) async =>
      (await (select(syncMeta)..where((m) => m.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  Future<void> setMeta(String key, String value) => into(syncMeta)
      .insertOnConflictUpdate(SyncMetaCompanion.insert(key: key, value: value));

  Future<int> createTrack(DateTime startedAt,
      {String name = 'Ride',
      int? batteryStartPercent,
      String? bikeProfileId}) async {
    final clock = await stamp();
    return into(tracks).insert(
      TracksCompanion.insert(
        startedAt: startedAt,
        name: Value(name),
        batteryStartPercent: Value(batteryStartPercent),
        bikeProfileId: Value(bikeProfileId),
        nameClock: Value(clock),
        bikeClock: Value(clock),
        geometryClock: Value(clock),
      ),
    );
  }

  Future<void> addPoint(TrackPointsCompanion point) =>
      into(trackPoints).insert(point);

  /// Backfills a single point's heart rate/cadence — used to add sensor data
  /// to already-imported OruxMaps rides (see `OruxMapsImportService`'s
  /// backfill pass) without touching position/altitude/speed or re-importing
  /// the whole ride.
  Future<void> updatePointSensor(
    int pointId, {
    int? heartRate,
    double? cadenceRpm,
  }) => (update(trackPoints)..where((p) => p.id.equals(pointId))).write(
    TrackPointsCompanion(
      heartRate: Value(heartRate),
      cadenceRpm: Value(cadenceRpm),
    ),
  );

  Future<void> finalizeTrack(
    int trackId, {
    required DateTime endedAt,
    required double distanceMeters,
    required int durationSeconds,
    required double avgSpeedMps,
    required double maxSpeedMps,
    int? batteryEndPercent,
  }) async {
    final clock = await stamp();
    await (update(tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(
        endedAt: Value(endedAt),
        distanceMeters: Value(distanceMeters),
        durationSeconds: Value(durationSeconds),
        avgSpeedMps: Value(avgSpeedMps),
        maxSpeedMps: Value(maxSpeedMps),
        batteryEndPercent: Value(batteryEndPercent),
        geometryClock: Value(clock),
      ),
    );
  }

  /// Marks a ride's points/stats as edited (for sync) after a direct point
  /// edit that doesn't go through [finalizeTrack]/[updateTrackStats], e.g. the
  /// OruxMaps sensor backfill.
  Future<void> touchGeometry(int trackId) async {
    final clock = await stamp();
    await (update(tracks)..where((t) => t.id.equals(trackId)))
        .write(TracksCompanion(geometryClock: Value(clock)));
  }

  Future<void> renameTrack(int trackId, String name) async {
    final clock = await stamp();
    await (update(tracks)..where((t) => t.id.equals(trackId))).write(
        TracksCompanion(name: Value(name), nameClock: Value(clock)));
  }

  /// Sets (or clears, with null) which bike a ride is attributed to — used
  /// both when starting a ride and to live-correct an in-progress one, and
  /// from the ride-detail screen to correct an already-finalised ride.
  Future<void> setTrackBikeProfile(int trackId, String? bikeProfileId) async {
    final clock = await stamp();
    await (update(tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(
          bikeProfileId: Value(bikeProfileId), bikeClock: Value(clock)),
    );
  }

  /// Bulk-assigns every ride (no `where` — including ones already on another
  /// bike) to [bikeProfileId], e.g. "put all my past rides on Cube". Returns
  /// the number of rides updated.
  Future<int> assignAllTracksToBikeProfile(String? bikeProfileId) async {
    final clock = await stamp();
    return (update(tracks)..where((t) => t.deletedAt.isNull())).write(
        TracksCompanion(
            bikeProfileId: Value(bikeProfileId), bikeClock: Value(clock)));
  }

  /// Bulk-assigns exactly [trackIds] (e.g. a filtered subset from the ride
  /// classifier) to [bikeProfileId]. Returns the number of rides updated.
  Future<int> assignTracksToBikeProfile(
      List<int> trackIds, String? bikeProfileId) async {
    if (trackIds.isEmpty) return 0;
    final clock = await stamp();
    return (update(tracks)..where((t) => t.id.isIn(trackIds))).write(
        TracksCompanion(
            bikeProfileId: Value(bikeProfileId), bikeClock: Value(clock)));
  }

  /// Track-level candidates for the ride classifier — the criteria that live
  /// directly on [Tracks] (cheap, done in SQL). Cadence/HR/power-presence
  /// filtering happens afterwards at the point level (`ride_classifier.dart`),
  /// since that data only exists on [TrackPoints].
  Future<List<Track>> tracksMatching({
    bool onlyUnassigned = false,
    double? minDistanceMeters,
    double? maxDistanceMeters,
    double? minAvgSpeedMps,
    double? maxAvgSpeedMps,
    double? minMaxSpeedMps,
    double? maxMaxSpeedMps,
    DateTime? startedAfter,
    DateTime? startedBefore,
  }) {
    final q = select(tracks)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    if (onlyUnassigned) q.where((t) => t.bikeProfileId.isNull());
    if (minDistanceMeters != null) {
      q.where((t) => t.distanceMeters.isBiggerOrEqualValue(minDistanceMeters));
    }
    if (maxDistanceMeters != null) {
      q.where((t) => t.distanceMeters.isSmallerOrEqualValue(maxDistanceMeters));
    }
    if (minAvgSpeedMps != null) {
      q.where((t) => t.avgSpeedMps.isBiggerOrEqualValue(minAvgSpeedMps));
    }
    if (maxAvgSpeedMps != null) {
      q.where((t) => t.avgSpeedMps.isSmallerOrEqualValue(maxAvgSpeedMps));
    }
    if (minMaxSpeedMps != null) {
      q.where((t) => t.maxSpeedMps.isBiggerOrEqualValue(minMaxSpeedMps));
    }
    if (maxMaxSpeedMps != null) {
      q.where((t) => t.maxSpeedMps.isSmallerOrEqualValue(maxMaxSpeedMps));
    }
    if (startedAfter != null) {
      q.where((t) => t.startedAt.isBiggerOrEqualValue(startedAfter));
    }
    if (startedBefore != null) {
      q.where((t) => t.startedAt.isSmallerOrEqualValue(startedBefore));
    }
    return q.get();
  }

  /// Most-recent rides first. Rides in the trash are excluded.
  Stream<List<Track>> watchTracks() => (select(tracks)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
      .watch();

  /// Every ride not in the trash, most recent first.
  Future<List<Track>> allTracks() => (select(tracks)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
      .get();

  /// Every row including trashed rides and purged deletion markers — for
  /// import dedup (a ride the user deleted must not come back from an old
  /// backup) and for sync.
  Future<List<Track>> allTracksIncludingDeleted() => (select(tracks)
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
      .get();

  /// Rides in the trash that can still be restored (points not purged yet),
  /// most recently deleted first.
  Stream<List<Track>> watchDeletedTracks() => (select(tracks)
        ..where((t) => t.deletedAt.isNotNull() & t.pointsPurged.equals(false))
        ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
      .watch();

  /// Number of points per track, without loading them.
  Future<Map<int, int>> pointCounts() async {
    final count = trackPoints.id.count();
    final rows = await (selectOnly(trackPoints)
          ..addColumns([trackPoints.trackId, count])
          ..groupBy([trackPoints.trackId]))
        .get();
    return {
      for (final r in rows) r.read(trackPoints.trackId)!: r.read(count)!,
    };
  }

  Future<Track?> track(int id) =>
      (select(tracks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<TrackPoint>> pointsFor(int trackId) => (select(trackPoints)
        ..where((p) => p.trackId.equals(trackId))
        ..orderBy([(p) => OrderingTerm.asc(p.time)]))
      .get();

  /// Moves a ride to the trash (see [Tracks.deletedAt]). Nothing is erased:
  /// it can be restored with [restoreTrack] until the retention period ends
  /// and [purgeExpiredTrash] drops its points.
  Future<void> deleteTrack(int id) async {
    final clock = await stamp();
    await (update(tracks)..where((t) => t.id.equals(id))).write(
      TracksCompanion(deletedAt: Value(now()), deletedClock: Value(clock)),
    );
  }

  /// Brings a ride back from the trash. The geometry is re-stamped too, so on
  /// every other phone the restored points win over a copy that was already
  /// purged there.
  Future<void> restoreTrack(int id) async {
    final clock = await stamp();
    await (update(tracks)
          ..where((t) => t.id.equals(id) & t.pointsPurged.equals(false)))
        .write(TracksCompanion(
      deletedAt: const Value(null),
      deletedClock: Value(clock),
      geometryClock: Value(clock),
    ));
  }

  /// Permanently removes a ride's data. If no other live row shares its start
  /// time, the row is kept as a points-less deletion marker for sync;
  /// otherwise (a removed duplicate, an empty crash artefact) it's erased.
  Future<void> purgeTrack(int id) async {
    final t = await track(id);
    if (t == null) return;
    await transaction(() async {
      final others = await (select(tracks)
            ..where((o) =>
                o.id.equals(id).not() &
                o.startedAt.equals(t.startedAt) &
                o.deletedAt.isNull()))
          .get();
      if (others.isNotEmpty || t.endedAt == null) {
        await (delete(tracks)..where((o) => o.id.equals(id))).go();
        return;
      }
      await (delete(trackPoints)..where((p) => p.trackId.equals(id))).go();
      await (update(tracks)..where((o) => o.id.equals(id))).write(
        TracksCompanion(
          pointsPurged: const Value(true),
          deletedAt: Value(t.deletedAt ?? now()),
          deletedClock: Value(t.deletedClock ?? await stamp()),
        ),
      );
    });
  }

  /// Purges every trashed ride deleted more than [retention] ago. Returns the
  /// number purged.
  Future<int> purgeExpiredTrash(Duration retention) async {
    final cutoff = now().subtract(retention);
    final expired = await (select(tracks)
          ..where((t) =>
              t.deletedAt.isSmallerThanValue(cutoff) &
              t.pointsPurged.equals(false)))
        .get();
    for (final t in expired) {
      await purgeTrack(t.id);
    }
    return expired.length;
  }

  /// Deletes specific track points (used to clean GPS spike outliers).
  Future<void> deletePoints(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(trackPoints)..where((p) => p.id.isIn(ids))).go();
  }

  /// Overwrites just a track's computed stats (after cleaning/repair), leaving
  /// its start/end/battery untouched.
  Future<void> updateTrackStats(
    int trackId, {
    required double distanceMeters,
    required int durationSeconds,
    required double avgSpeedMps,
    required double maxSpeedMps,
  }) async {
    final clock = await stamp();
    await (update(tracks)..where((t) => t.id.equals(trackId))).write(
      TracksCompanion(
        distanceMeters: Value(distanceMeters),
        durationSeconds: Value(durationSeconds),
        avgSpeedMps: Value(avgSpeedMps),
        maxSpeedMps: Value(maxSpeedMps),
        geometryClock: Value(clock),
      ),
    );
  }

  // --- Sync ------------------------------------------------------------------

  Future<List<SyncRemoteFile>> listSyncRemoteFiles() => select(syncRemoteFiles).get();

  Future<void> putSyncRemoteFile(String path, String? etag, String meta) =>
      into(syncRemoteFiles).insertOnConflictUpdate(SyncRemoteFilesCompanion.insert(
          path: path, etag: Value(etag), meta: meta));

  Future<void> removeSyncRemoteFiles(Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return;
    await (delete(syncRemoteFiles)..where((f) => f.path.isIn(list))).go();
  }
}
