import 'dart:io';
import 'dart:typed_data';

import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/backup_service.dart';
import 'package:cycle/core/services/incoming_backup_service.dart';
import 'package:cycle/features/backup/application/backup_providers.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIncomingBackupService implements IncomingBackupService {
  _FakeIncomingBackupService([this._pending]);
  final IncomingBackup? _pending;

  @override
  Future<IncomingBackup?> consumePending() async => _pending;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cycle_incoming_backup_test');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  ProviderContainer container(IncomingBackupService incoming) {
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      backupServiceProvider
          .overrideWithValue(BackupService(db, directory: () async => tmp)),
      incomingBackupServiceProvider.overrideWithValue(incoming),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('returns null when nothing is pending', () async {
    final c = container(_FakeIncomingBackupService());
    final result = await c
        .read(backupImportControllerProvider.notifier)
        .importIncomingIfAny();
    expect(result, isNull);
  });

  test('saves + merges a pending backup, returning the imported count',
      () async {
    // Build a source backup (separate db/dir) with one ride.
    final sourceDb = AppDatabase(NativeDatabase.memory());
    addTearDown(sourceDb.close);
    final sourceTmp =
        await Directory.systemTemp.createTemp('cycle_incoming_backup_src');
    addTearDown(() => sourceTmp.delete(recursive: true));
    final start = DateTime.utc(2026, 5, 1, 9);
    final id = await sourceDb.createTrack(start, name: 'From backup');
    await sourceDb.finalizeTrack(id,
        endedAt: start.add(const Duration(minutes: 10)),
        distanceMeters: 2000,
        durationSeconds: 600,
        avgSpeedMps: 3,
        maxSpeedMps: 5);
    final sourceService = BackupService(sourceDb, directory: () async => sourceTmp);
    final backupFile = await sourceService.exportBackup();
    final bytes = Uint8List.fromList(await backupFile.readAsBytes());

    final c = container(_FakeIncomingBackupService(
        IncomingBackup(name: 'cycle_backup_shared.sqlite', bytes: bytes)));

    final imported = await c
        .read(backupImportControllerProvider.notifier)
        .importIncomingIfAny();

    expect(imported, 1);
    final tracks = await db.allTracks();
    expect(tracks, hasLength(1));
    expect(tracks.single.name, 'From backup');
  });
}
