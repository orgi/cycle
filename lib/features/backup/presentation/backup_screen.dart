import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backup_service.dart';
import '../../../core/utils/format.dart';
import '../../tracks/application/track_providers.dart';
import '../application/backup_providers.dart';

/// Export the ride database to a file (to move rides to another phone) or
/// import one exported there — folder-based like GPX routes, no file picker
/// (see CLAUDE.md "file_picker does not build here"). "Share" hands a backup
/// to the OS share sheet (OneDrive, Drive, email, Bluetooth, …) so moving
/// rides to another phone doesn't need a cable — the chosen app handles its
/// own login, so no OAuth/account setup lives in Cycle itself.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backups = ref.watch(backupFilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Export all your rides to a file, then share it to another phone '
            '(OneDrive, Drive, email, Bluetooth, …) or copy it over adb/USB, '
            'and import it there. Importing merges rides — already-present '
            'rides are skipped, so it\'s safe to import the same backup more '
            'than once.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('exportBackupButton'),
            icon: const Icon(Icons.save_alt),
            label: const Text('Export backup'),
            onPressed: () => _export(context, ref),
          ),
          const SizedBox(height: 8),
          ref.watch(backupsFolderPathProvider).when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (path) => Text('Folder: $path',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12)),
              ),
          const Divider(height: 32),
          const Text('AVAILABLE BACKUPS',
              style: TextStyle(color: Colors.white54, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          backups.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (files) {
              if (files.isEmpty) {
                return const Text(
                    'No backup files found. Export one here, or copy one '
                    'from another phone into the folder above.',
                    style: TextStyle(color: Colors.white54));
              }
              return Column(
                children: [
                  for (final f in files)
                    ListTile(
                      key: Key('backupFile_${f.name}'),
                      leading: const Icon(Icons.description_outlined),
                      title: Text(f.name),
                      subtitle: Text(formatDateTime(f.modified)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('shareBackup_${f.name}'),
                            icon: const Icon(Icons.share_outlined),
                            tooltip: 'Share',
                            onPressed: () => _share(context, ref, f),
                          ),
                          FilledButton.tonal(
                            key: Key('importBackup_${f.name}'),
                            onPressed: () => _import(context, ref, f),
                            child: const Text('Import'),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref.read(backupServiceProvider).exportBackup();
      // The screen may have been navigated away from while exporting — `ref`
      // (unlike `messenger`, captured above) is unsafe to touch once this
      // ConsumerWidget is unmounted.
      if (!context.mounted) return;
      ref.invalidate(backupFilesProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('Saved ${file.path}'),
        duration: const Duration(seconds: 10),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _import(
      BuildContext context, WidgetRef ref, BackupFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await ref.read(backupServiceProvider).importBackup(file.path);
      if (!context.mounted) return;
      ref.invalidate(tracksProvider);
      messenger.showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'No new rides in this backup'
            : 'Imported $n ride${n == 1 ? '' : 's'}'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _share(
      BuildContext context, WidgetRef ref, BackupFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shareServiceProvider).shareFile(file.path);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }
}
