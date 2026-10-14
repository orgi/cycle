import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/utils/format.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../application/track_providers.dart';

/// The trash: rides deleted within the retention period, with Restore and
/// "Delete now". A restore also comes back on every synced phone.
class RecentlyDeletedScreen extends ConsumerWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deleted = ref.watch(deletedTracksProvider);
    final days = ref.watch(settingsProvider.select((s) => s.retentionDays));
    return Scaffold(
      appBar: AppBar(title: const Text('Recently deleted')),
      body: deleted.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No deleted rides.\nDeleted rides stay here for $days days.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Deleted rides are removed for good $days days after '
                  'deletion.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              for (final t in list) _DeletedTile(track: t, retentionDays: days),
            ],
          );
        },
      ),
    );
  }
}

class _DeletedTile extends ConsumerWidget {
  const _DeletedTile({required this.track, required this.retentionDays});

  final Track track;
  final int retentionDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = track;
    final deletedAt = t.deletedAt!;
    final left = deletedAt
        .add(Duration(days: retentionDays))
        .difference(DateTime.now())
        .inDays;
    return ListTile(
      key: Key('deletedTile_${t.id}'),
      title: Text(t.name),
      subtitle: Text(
        '${formatDateTime(t.startedAt)}  •  '
        '${formatDistanceKm(t.distanceMeters / 1000)} km\n'
        'Deleted ${formatDateTime(deletedAt)} · '
        '${left <= 0 ? 'removed soon' : '$left days left'}',
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('restoreTrack_${t.id}'),
            icon: const Icon(Icons.restore),
            tooltip: 'Restore',
            onPressed: () async {
              await ref.read(appDatabaseProvider).restoreTrack(t.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Restored "${t.name}"')),
                );
              }
            },
          ),
          IconButton(
            key: Key('purgeTrack_${t.id}'),
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: 'Delete now',
            onPressed: () => _purge(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _purge(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete for good?'),
        content: const Text(
          'The ride can no longer be restored — on this phone or any phone '
          'it syncs with. Safety backups taken before are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('purgeConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(appDatabaseProvider).purgeTrack(track.id);
  }
}
