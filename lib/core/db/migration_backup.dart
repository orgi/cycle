import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Before a schema migration touches [dbFile], writes a consistent snapshot of
/// it to `<backupsDir>/cycle_backup_pre_v<toVersion>_<timestamp>.sqlite` — the
/// one moment a bug can damage every ride at once, so it never runs on the only
/// copy. Uses a raw sqlite3 connection (drift would migrate on open) and
/// `VACUUM INTO`, which also folds in any pending WAL content.
///
/// No-op for a fresh install (no file / version 0) or an up-to-date DB.
/// Returns the backup written, if any. Failure to back up is rethrown: better
/// not to open (and migrate) the DB at all than to migrate without a copy.
Future<File?> backupBeforeMigration(
  File dbFile,
  int toVersion, {
  required Future<Directory> Function() backupsDir,
  DateTime Function() now = DateTime.now,
}) async {
  if (!await dbFile.exists()) return null;
  final db = sqlite3.open(dbFile.path);
  try {
    final version = db.select('PRAGMA user_version').first.values.first as int;
    if (version == 0 || version >= toVersion) return null;
    final dir = await backupsDir();
    await dir.create(recursive: true);
    final n = now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
    final out = File('${dir.path}/cycle_backup_pre_v${toVersion}_$stamp.sqlite');
    if (await out.exists()) await out.delete();
    db.execute('VACUUM INTO ?', [out.path]);
    return out;
  } finally {
    db.close();
  }
}
