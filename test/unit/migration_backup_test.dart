import 'dart:io';

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/db/migration_backup.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Builds a schema-v4 database file (as shipped before sync) with one ride.
void _writeV4(String path) {
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE tracks (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL DEFAULT 'Ride', started_at INTEGER NOT NULL,
      ended_at INTEGER NULL, distance_meters REAL NOT NULL DEFAULT 0,
      duration_seconds INTEGER NOT NULL DEFAULT 0,
      avg_speed_mps REAL NOT NULL DEFAULT 0, max_speed_mps REAL NOT NULL DEFAULT 0,
      battery_start_percent INTEGER NULL, battery_end_percent INTEGER NULL,
      bike_profile_id TEXT NULL);
    CREATE TABLE track_points (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      track_id INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE,
      time INTEGER NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL,
      altitude REAL NULL, speed_mps REAL NULL, heart_rate INTEGER NULL,
      cadence_rpm REAL NULL, power INTEGER NULL,
      speed_from_sensor INTEGER NULL CHECK (speed_from_sensor IN (0, 1)));
    INSERT INTO tracks (name, started_at, ended_at, distance_meters)
      VALUES ('Old ride', 1767225600, 1767229200, 12345);
    INSERT INTO track_points (track_id, time, latitude, longitude)
      VALUES (1, 1767225600, 47.0, 11.0);
    PRAGMA user_version = 4;
  ''');
  db.close();
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cycle_mig'));
  tearDown(() => tmp.delete(recursive: true));

  test('a v4 database is snapshotted before migrating, then migrates', () async {
    final dbFile = File('${tmp.path}/cycle.sqlite');
    _writeV4(dbFile.path);
    final backups = Directory('${tmp.path}/backups');

    final backup = await backupBeforeMigration(dbFile, AppDatabase.kSchemaVersion,
        backupsDir: () async => backups);
    expect(backup, isNotNull);
    expect(backup!.path, contains('cycle_backup_pre_v5_'));

    // The snapshot is the untouched v4 DB with the ride.
    final snap = sqlite3.open(backup.path);
    expect(snap.select('PRAGMA user_version').first.values.first, 4);
    expect(snap.select('SELECT name FROM tracks').single['name'], 'Old ride');
    snap.close();

    // The real DB then migrates and keeps the ride + its point.
    final db = AppDatabase(NativeDatabase(dbFile));
    final rides = await db.allTracks();
    expect(rides.single.name, 'Old ride');
    expect(rides.single.deletedAt, isNull);
    expect(await db.pointsFor(rides.single.id), hasLength(1));
    await db.close();

    // Up to date now: no second snapshot.
    expect(
        await backupBeforeMigration(dbFile, AppDatabase.kSchemaVersion,
            backupsDir: () async => backups),
        isNull);
  });

  test('no snapshot for a fresh install', () async {
    expect(
        await backupBeforeMigration(File('${tmp.path}/missing.sqlite'), 5,
            backupsDir: () async => tmp),
        isNull);
  });
}
