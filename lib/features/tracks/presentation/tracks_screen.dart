import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/ride_summary.dart';
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
          final summaries = computeRideSummaries(list);
          return ListView.builder(
            itemCount: list.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _SummaryRow(summaries: summaries);
              }
              final t = list[i - 1];
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

/// Rolling week/month/year totals shown above the ride list.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summaries});

  final RideSummaries summaries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
              child: _SummaryCard(
                  key: const Key('summaryWeek'),
                  label: 'This week',
                  summary: summaries.week)),
          const SizedBox(width: 8),
          Expanded(
              child: _SummaryCard(
                  key: const Key('summaryMonth'),
                  label: 'This month',
                  summary: summaries.month)),
          const SizedBox(width: 8),
          Expanded(
              child: _SummaryCard(
                  key: const Key('summaryYear'),
                  label: 'This year',
                  summary: summaries.year)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({super.key, required this.label, required this.summary});

  final String label;
  final RideSummary summary;

  @override
  Widget build(BuildContext context) {
    final hours = summary.duration.inMinutes / 60.0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Text('${formatDistanceKm(summary.distanceKm)} km',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          Text('${hours.toStringAsFixed(1)} h  •  '
              '${summary.rideCount} ride${summary.rideCount == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
