import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../dashboard/application/ride_providers.dart';
import '../application/track_providers.dart';

/// List of recorded rides, newest first.
class TracksScreen extends ConsumerWidget {
  const TracksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rides'),
        actions: [
          IconButton(
            key: const Key('uploadAccountsButton'),
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Upload accounts',
            onPressed: () => context.push('/upload-accounts'),
          ),
        ],
      ),
      body: tracks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text('No rides yet. Tap Start to record one.',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i];
              return Dismissible(
                key: Key('track_${t.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) =>
                    ref.read(appDatabaseProvider).deleteTrack(t.id),
                child: ListTile(
                  key: Key('trackTile_${t.id}'),
                  title: Text(t.name),
                  subtitle: Text(
                    '${formatDateTime(t.startedAt)}  •  '
                    '${formatDistanceKm(t.distanceMeters / 1000)} km  •  '
                    '${formatDuration(Duration(seconds: t.durationSeconds))}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/tracks/${t.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
