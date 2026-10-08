import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';

/// A backup file found in the backups folder.
class BackupFile {
  const BackupFile(
      {required this.name, required this.path, required this.modified});

  final String name;
  final String path;
  final DateTime modified;
}

/// Exports the ride database to a portable `.sqlite` file, and imports rides
/// from one back in — the way to move ride history between phones (there's no
/// root/adb-backup path available on a non-debuggable release build; see
/// CLAUDE.md "Known gotchas").
///
/// Import **merges**: rides are matched by `startedAt` and a ride already
/// present locally is skipped, so re-importing the same backup (or importing
/// on a phone that already recorded some of the same rides) is safe to repeat.
class BackupService {
  BackupService(this._db, {Future<Directory> Function()? directory})
      : _directory = directory ?? defaultRoot;

  final AppDatabase _db;
  final Future<Directory> Function() _directory;

  /// Same root as routes/exports: the app-specific *external* files dir on
  /// Android (visible via the Files app / adb, no root needed).
  static Future<Directory> defaultRoot() async {
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<Directory> _backupsDir() async {
    final root = await _directory();
    final dir = Directory('${root.path}/backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> backupsFolderPath() async => (await _backupsDir()).path;

  /// Writes a consistent snapshot of the whole ride database to
  /// `<root>/backups/cycle_backup_<timestamp>.sqlite` and returns it.
  /// `VACUUM INTO` takes a live, transaction-consistent copy without needing
  /// to close the database first.
  Future<File> exportBackup({String label = ''}) async {
    final dir = await _backupsDir();
    final prefix = label.isEmpty ? '' : '${label}_';
    final file =
        File('${dir.path}/cycle_backup_$prefix${_timestamp()}.sqlite');
    if (await file.exists()) {
      await file.delete();
    }
    await _db.customStatement('VACUUM INTO ?', [file.path]);
    return file;
  }

  /// Name prefix of the automatic safety snapshots taken before a sync applies
  /// deletions or replaces a ride's data — the only backups [pruneAutoBackups]
  /// ever removes.
  static const autoLabel = 'auto';

  /// Takes an automatic safety snapshot unless one was already taken today.
  /// Returns the new file, or null if today's already exists.
  Future<File?> autoBackupOncePerDay({DateTime? now}) async {
    final n = now ?? DateTime.now();
    final today = _timestamp(n).substring(0, 8);
    for (final b in await listBackups()) {
      if (b.name.startsWith('cycle_backup_${autoLabel}_$today')) return null;
    }
    return exportBackup(label: autoLabel);
  }

  /// Deletes automatic safety snapshots older than [retention]. Manual exports,
  /// the pre-migration and the pre-first-sync snapshots are never touched.
  /// Returns the number deleted.
  Future<int> pruneAutoBackups(Duration retention, {DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(retention);
    var deleted = 0;
    for (final b in await listBackups()) {
      if (!b.name.startsWith('cycle_backup_${autoLabel}_')) continue;
      if (b.modified.isBefore(cutoff)) {
        await File(b.path).delete();
        deleted++;
      }
    }
    return deleted;
  }

  /// Saves [bytes] (e.g. downloaded from a cloud provider) as `<name>` in the
  /// backups folder, so it shows up in [listBackups] like a local export.
  Future<File> saveDownloadedBackup(String name, List<int> bytes) async {
    final dir = await _backupsDir();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// `.sqlite` backups currently in the backups folder, newest first.
  Future<List<BackupFile>> listBackups() async {
    final dir = await _backupsDir();
    final files = <BackupFile>[];
    await for (final entry in dir.list()) {
      if (entry is File && entry.path.toLowerCase().endsWith('.sqlite')) {
        final stat = await entry.stat();
        files.add(BackupFile(
          name: entry.uri.pathSegments.last,
          path: entry.path,
          modified: stat.modified,
        ));
      }
    }
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  /// Merges every ride from the backup at [path] into the live database,
  /// skipping rides whose `startedAt` already exists locally — including rides
  /// in the trash, so a ride the user deleted doesn't come back from an old
  /// backup (it can be restored from "Recently deleted" instead). Returns the
  /// number of rides actually imported.
  Future<int> importBackup(String path) async {
    final source = AppDatabase(NativeDatabase(File(path)));
    try {
      final existing =
          (await _db.allTracksIncludingDeleted()).map((t) => t.startedAt).toSet();
      var imported = 0;
      for (final track in await source.allTracks()) {
        if (existing.contains(track.startedAt)) continue;

        final newId = await _db.createTrack(
          track.startedAt,
          name: track.name,
          batteryStartPercent: track.batteryStartPercent,
          bikeProfileId: track.bikeProfileId,
        );
        for (final p in await source.pointsFor(track.id)) {
          await _db.addPoint(TrackPointsCompanion.insert(
            trackId: newId,
            time: p.time,
            latitude: p.latitude,
            longitude: p.longitude,
            altitude: Value(p.altitude),
            speedMps: Value(p.speedMps),
            heartRate: Value(p.heartRate),
            cadenceRpm: Value(p.cadenceRpm),
            power: Value(p.power),
            speedFromSensor: Value(p.speedFromSensor),
          ));
        }
        await _db.finalizeTrack(
          newId,
          endedAt: track.endedAt ?? track.startedAt,
          distanceMeters: track.distanceMeters,
          durationSeconds: track.durationSeconds,
          avgSpeedMps: track.avgSpeedMps,
          maxSpeedMps: track.maxSpeedMps,
          batteryEndPercent: track.batteryEndPercent,
        );
        imported++;
      }
      return imported;
    } finally {
      await source.close();
    }
  }

  String _timestamp([DateTime? now]) {
    final n = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
