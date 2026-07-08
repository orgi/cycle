import 'dart:io';

import 'package:cycle/core/services/backup_service.dart';
import 'package:cycle/core/services/share_service.dart';
import 'package:cycle/features/backup/application/backup_providers.dart';
import 'package:cycle/features/backup/presentation/backup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [BackupService] test double: the real class does genuine `dart:io`/FFI
/// work (VACUUM INTO, real file/DB opens), and triggering that from a widget's
/// `onPressed` inside a `testWidgets` body deadlocks — `TestWidgetsFlutterBinding`
/// runs the test in a zone that doesn't reliably observe real async I/O
/// completing outside of `tester.runAsync()`. The real service's behaviour
/// (export/import/dedup) is already covered by `backup_service_test.dart`; this
/// fake lets the widget test focus on the screen's wiring only.
class _FakeBackupService implements BackupService {
  _FakeBackupService(this._files);

  final List<BackupFile> _files;
  int importCalls = 0;

  @override
  Future<File> exportBackup() async => File('fake_backup.sqlite');

  @override
  Future<File> saveDownloadedBackup(String name, List<int> bytes) async =>
      File('fake_$name');

  @override
  Future<List<BackupFile>> listBackups() async => _files;

  @override
  Future<String> backupsFolderPath() async => '/fake/backups';

  @override
  Future<int> importBackup(String path) async {
    importCalls++;
    return 0;
  }
}

/// A [ShareService] test double — avoids the real class's native channel call.
class _FakeShareService implements ShareService {
  String? lastSharedPath;

  @override
  Future<void> shareFile(String path) async {
    lastSharedPath = path;
  }
}

void main() {
  testWidgets('empty state points at the backups folder', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(_FakeBackupService(const [])),
        ],
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.text('No backup files found. Export one here, or copy one '
            'from another phone into the folder above.'),
        findsOneWidget);
    expect(find.textContaining('/fake/backups'), findsOneWidget);
    expect(find.byKey(const Key('exportBackupButton')), findsOneWidget);
  });

  testWidgets('tapping Import on a listed backup reports the result',
      (tester) async {
    final fake = _FakeBackupService([
      BackupFile(
        name: 'cycle_backup_20260701_0800.sqlite',
        path: '/fake/backups/cycle_backup_20260701_0800.sqlite',
        modified: DateTime(2026, 7, 1, 8),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [backupServiceProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('cycle_backup_20260701_0800.sqlite'), findsOneWidget);

    await tester.tap(find.byKey(
        const Key('importBackup_cycle_backup_20260701_0800.sqlite')));
    await tester.pumpAndSettle();

    expect(fake.importCalls, 1);
    expect(find.text('No new rides in this backup'), findsOneWidget);
  });

  testWidgets('tapping Share on a listed backup hands its path to ShareService',
      (tester) async {
    final backupFake = _FakeBackupService([
      BackupFile(
        name: 'cycle_backup_20260701_0800.sqlite',
        path: '/fake/backups/cycle_backup_20260701_0800.sqlite',
        modified: DateTime(2026, 7, 1, 8),
      ),
    ]);
    final shareFake = _FakeShareService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupServiceProvider.overrideWithValue(backupFake),
          shareServiceProvider.overrideWithValue(shareFake),
        ],
        child: const MaterialApp(home: BackupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('shareBackup_cycle_backup_20260701_0800.sqlite')));
    await tester.pumpAndSettle();

    expect(shareFake.lastSharedPath,
        '/fake/backups/cycle_backup_20260701_0800.sqlite');
  });
}
