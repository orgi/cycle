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
}

@DriftDatabase(tables: [Tracks, TrackPoints])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(tracks, tracks.batteryStartPercent);
            await m.addColumn(tracks, tracks.batteryEndPercent);
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
          {String name = 'Ride', int? batteryStartPercent}) =>
      into(tracks).insert(
        TracksCompanion.insert(
          startedAt: startedAt,
          name: Value(name),
          batteryStartPercent: Value(batteryStartPercent),
        ),
      );

  Future<void> addPoint(TrackPointsCompanion point) =>
      into(trackPoints).insert(point);

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
}
