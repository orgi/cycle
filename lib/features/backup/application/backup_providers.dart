import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backup_service.dart';
import '../../../core/services/incoming_backup_service.dart';
import '../../../core/services/share_service.dart';
import '../../dashboard/application/ride_providers.dart';

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(appDatabaseProvider)),
);

/// Hands a backup file to the OS share sheet. Overridable in tests.
final shareServiceProvider =
    Provider<ShareService>((ref) => NativeShareService());

/// Picks up a `.sqlite` backup the app was opened/shared with. Overridable in
/// tests.
final incomingBackupServiceProvider =
    Provider<IncomingBackupService>((ref) => IncomingBackupService());

/// `.sqlite` backups currently sitting in the backups folder, newest first.
final backupFilesProvider = FutureProvider.autoDispose<List<BackupFile>>(
  (ref) => ref.watch(backupServiceProvider).listBackups(),
);

/// Absolute path of the backups folder, shown so the user knows where to
/// find/drop backup files. Cached by Riverpod (unlike a bare `FutureBuilder`
/// fed a freshly-created Future on every build, which never settles).
final backupsFolderPathProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(backupServiceProvider).backupsFolderPath(),
);

final backupImportControllerProvider =
    NotifierProvider<BackupImportController, void>(BackupImportController.new);

/// Imports a `.sqlite` backup the app was opened/shared with, if any —
/// mirrors `FollowRouteController.followIncomingIfAny()` for GPX.
class BackupImportController extends Notifier<void> {
  @override
  void build() {}

  /// Returns the number of rides imported, or null when there was nothing
  /// pending (no incoming backup / no native handler on this platform).
  Future<int?> importIncomingIfAny() async {
    final incoming =
        await ref.read(incomingBackupServiceProvider).consumePending();
    if (incoming == null) return null;
    final service = ref.read(backupServiceProvider);
    final file =
        await service.saveDownloadedBackup(incoming.name, incoming.bytes);
    final imported = await service.importBackup(file.path);
    ref.invalidate(backupFilesProvider);
    return imported;
  }
}
