import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

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

@DriftDatabase(tables: [Tracks, TrackPoints])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 4;

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
        },
        beforeOpen: (_) async {
          // Required for the trackPoints → tracks ON DELETE CASCADE to fire.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  static QueryExecutor _open() => LazyDatabase(() async {
        final dir = await getApplicationSupportDirectory();
        return NativeDatabase.createInBackground(File('${dir.path}/cycle.sqlite'));
      });

  Future<int> createTrack(DateTime startedAt,
          {String name = 'Ride',
          int? batteryStartPercent,
          String? bikeProfileId}) =>
      into(tracks).insert(
        TracksCompanion.insert(
          startedAt: startedAt,
          name: Value(name),
          batteryStartPercent: Value(batteryStartPercent),
          bikeProfileId: Value(bikeProfileId),
        ),
      );

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
  }) =>
      (update(tracks)..where((t) => t.id.equals(trackId))).write(
        TracksCompanion(
          endedAt: Value(endedAt),
          distanceMeters: Value(distanceMeters),
          durationSeconds: Value(durationSeconds),
          avgSpeedMps: Value(avgSpeedMps),
          maxSpeedMps: Value(maxSpeedMps),
          batteryEndPercent: Value(batteryEndPercent),
        ),
      );

  Future<void> renameTrack(int trackId, String name) =>
      (update(tracks)..where((t) => t.id.equals(trackId)))
          .write(TracksCompanion(name: Value(name)));

  /// Sets (or clears, with null) which bike a ride is attributed to — used
  /// both when starting a ride and to live-correct an in-progress one, and
  /// from the ride-detail screen to correct an already-finalised ride.
  Future<void> setTrackBikeProfile(int trackId, String? bikeProfileId) =>
      (update(tracks)..where((t) => t.id.equals(trackId))).write(
        TracksCompanion(bikeProfileId: Value(bikeProfileId)),
      );

  /// Bulk-assigns every ride (no `where` — including ones already on another
  /// bike) to [bikeProfileId], e.g. "put all my past rides on Cube". Returns
  /// the number of rides updated.
  Future<int> assignAllTracksToBikeProfile(String? bikeProfileId) =>
      update(tracks).write(TracksCompanion(bikeProfileId: Value(bikeProfileId)));

  /// Bulk-assigns exactly [trackIds] (e.g. a filtered subset from the ride
  /// classifier) to [bikeProfileId]. Returns the number of rides updated.
  Future<int> assignTracksToBikeProfile(
      List<int> trackIds, String? bikeProfileId) {
    if (trackIds.isEmpty) return Future.value(0);
    return (update(tracks)..where((t) => t.id.isIn(trackIds)))
        .write(TracksCompanion(bikeProfileId: Value(bikeProfileId)));
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

  /// Most-recent rides first.
  Stream<List<Track>> watchTracks() => (select(tracks)
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
      .watch();

  Future<List<Track>> allTracks() => (select(tracks)
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
      .get();

  Future<Track?> track(int id) =>
      (select(tracks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<TrackPoint>> pointsFor(int trackId) => (select(trackPoints)
        ..where((p) => p.trackId.equals(trackId))
        ..orderBy([(p) => OrderingTerm.asc(p.time)]))
      .get();

  Future<void> deleteTrack(int id) =>
      (delete(tracks)..where((t) => t.id.equals(id))).go();

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
  }) =>
      (update(tracks)..where((t) => t.id.equals(trackId))).write(
        TracksCompanion(
          distanceMeters: Value(distanceMeters),
          durationSeconds: Value(durationSeconds),
          avgSpeedMps: Value(avgSpeedMps),
          maxSpeedMps: Value(maxSpeedMps),
        ),
      );
}
