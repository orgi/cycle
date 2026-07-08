import 'dart:io';

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/backup_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _seedRide(AppDatabase db, DateTime start,
    {String name = 'Ride'}) async {
  final id = await db.createTrack(start, name: name, batteryStartPercent: 90);
  await db.addPoint(TrackPointsCompanion.insert(
    trackId: id,
    time: start,
    latitude: 43.0,
    longitude: 7.0,
    heartRate: const Value(140),
  ));
  await db.finalizeTrack(id,
      endedAt: start.add(const Duration(minutes: 30)),
      distanceMeters: 12000,
      durationSeconds: 1800,
      avgSpeedMps: 6.0,
      maxSpeedMps: 10.0,
      batteryEndPercent: 80);
  return id;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cycle_backup');
  });
  tearDown(() => tmp.delete(recursive: true));

  test('exportBackup writes a loadable sqlite file with the rides', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedRide(db, DateTime.utc(2026, 6, 1, 8));

    final service = BackupService(db, directory: () async => tmp);
    final file = await service.exportBackup();

    expect(await file.exists(), isTrue);
    expect(file.path, contains('backups/cycle_backup_'));

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final tracks = await reopened.allTracks();
    expect(tracks, hasLength(1));
    expect(tracks.single.distanceMeters, 12000);
  });

  test('importBackup merges rides into the live database', () async {
    final source = AppDatabase(NativeDatabase.memory());
    await _seedRide(source, DateTime.utc(2026, 6, 1, 8), name: 'From A3');
    final sourceService = BackupService(source, directory: () async => tmp);
    final backupFile = await sourceService.exportBackup();
    await source.close();

    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    final targetService = BackupService(target, directory: () async => tmp);

    final imported = await targetService.importBackup(backupFile.path);
    expect(imported, 1);

    final tracks = await target.allTracks();
    expect(tracks, hasLength(1));
    expect(tracks.single.name, 'From A3');
    expect(tracks.single.distanceMeters, 12000);
    expect(tracks.single.batteryStartPercent, 90);
    expect(tracks.single.batteryEndPercent, 80);
    final points = await target.pointsFor(tracks.single.id);
    expect(points, hasLength(1));
    expect(points.single.heartRate, 140);
  });

  test('importBackup skips rides that already exist (dedup on re-import)',
      () async {
    final start = DateTime.utc(2026, 6, 1, 8);
    final source = AppDatabase(NativeDatabase.memory());
    await _seedRide(source, start);
    final sourceService = BackupService(source, directory: () async => tmp);
    final backupFile = await sourceService.exportBackup();
    await source.close();

    final target = AppDatabase(NativeDatabase.memory());
    addTearDown(target.close);
    await _seedRide(target, start); // already has the same ride
    final targetService = BackupService(target, directory: () async => tmp);

    final imported = await targetService.importBackup(backupFile.path);
    expect(imported, 0);
    expect(await target.allTracks(), hasLength(1));
  });

  test('listBackups lists newest first', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedRide(db, DateTime.utc(2026, 6, 1, 8));
    final service = BackupService(db, directory: () async => tmp);

    final first = await service.exportBackup();
    await Future<void>.delayed(const Duration(seconds: 1));
    final second = await service.exportBackup();

    final files = await service.listBackups();
    expect(files.map((f) => f.path), [second.path, first.path]);
  });
}
