import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/bike_profile.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/ride_summary.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../application/track_providers.dart';

/// List of recorded rides, newest first. When 2+ bike profiles exist, a filter
/// row lets you view a single bike's rides/summary or "All" (total).
class TracksScreen extends ConsumerWidget {
  const TracksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider);
    final profiles = ref.watch(bikeProfilesProvider).profiles;
    final filter = ref.watch(selectedBikeProfileFilterProvider);

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
        data: (all) {
          if (all.isEmpty) {
            return const Center(
              child: Text('No rides yet. Tap Start to record one.',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          final list = filter == null
              ? all
              : all.where((t) => t.bikeProfileId == filter).toList();
          final summaries = computeRideSummaries(list);
          // Filter row (only with 2+ bikes) + summary row, then either the
          // (possibly filtered) ride rows or an empty-for-this-bike message.
          final showFilter = profiles.length > 1;
          final headerCount = (showFilter ? 1 : 0) + 1;
          final bodyCount = list.isEmpty ? 1 : list.length;
          return ListView.builder(
            itemCount: headerCount + bodyCount,
            itemBuilder: (context, i) {
              if (showFilter && i == 0) {
                return _BikeFilterRow(profiles: profiles, selected: filter);
              }
              final afterFilter = showFilter ? i - 1 : i;
              if (afterFilter == 0) {
                return _SummaryRow(summaries: summaries);
              }
              if (list.isEmpty) {
                return const _EmptyForFilter();
              }
              final t = list[afterFilter - 1];
              final profileColor = profiles
                  .where((p) => p.id == t.bikeProfileId)
                  .firstOrNull
                  ?.colorArgb;
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
                  leading: (showFilter && profileColor != null)
                      ? CircleAvatar(
                          key: Key('trackBikeDot_${t.id}'),
                          radius: 6,
                          backgroundColor: Color(profileColor),
                        )
                      : null,
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

/// Shown in place of the ride rows when a bike filter matches no rides.
class _EmptyForFilter extends StatelessWidget {
  const _EmptyForFilter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text('No rides for this bike yet.',
            style: TextStyle(color: Colors.white54)),
      ),
    );
  }
}

/// "All" + one chip per bike profile, filtering the list/summary below.
class _BikeFilterRow extends ConsumerWidget {
  const _BikeFilterRow({required this.profiles, required this.selected});

  final List<BikeProfile> profiles;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              key: const Key('bikeFilterAll'),
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => ref
                  .read(selectedBikeProfileFilterProvider.notifier)
                  .select(null),
            ),
            for (final p in profiles) ...[
              const SizedBox(width: 6),
              ChoiceChip(
                key: Key('bikeFilter_${p.id}'),
                avatar: CircleAvatar(backgroundColor: Color(p.colorArgb)),
                label: Text(p.name),
                selected: selected == p.id,
                onSelected: (_) => ref
                    .read(selectedBikeProfileFilterProvider.notifier)
                    .select(p.id),
              ),
            ],
          ],
        ),
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
