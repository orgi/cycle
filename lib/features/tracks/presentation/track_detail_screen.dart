import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/metrics/elevation.dart';
import '../../../core/services/apple_health_service.dart';
import '../../../core/utils/format.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../dashboard/presentation/widgets/metric_tile.dart';
import '../../health/application/apple_health_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/presentation/widgets/bike_profile_picker.dart';
import '../application/track_providers.dart';
import '../application/track_repair.dart';
import 'widgets/ride_map.dart';

class TrackDetailScreen extends ConsumerWidget {
  const TrackDetailScreen({super.key, required this.trackId});

  final int trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackAsync = ref.watch(trackProvider(trackId));
    final pointsAsync = ref.watch(trackPointsProvider(trackId));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ride'),
          // Tabs, so the map and the chart get the whole screen and their
          // gestures never fight a page scroll.
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('rideTabStats'), text: 'Stats'),
              Tab(key: Key('rideTabMap'), text: 'Map'),
              Tab(key: Key('rideTabElevation'), text: 'Elevation'),
            ],
          ),
          actions: [
            if (appleHealthSupported)
              IconButton(
                key: const Key('saveToAppleHealthButton'),
                icon: const Icon(Icons.favorite_border),
                tooltip: 'Save to Apple Health',
                onPressed: () => _saveToAppleHealth(context, ref),
              ),
            IconButton(
              key: const Key('cleanSpikesButton'),
              icon: const Icon(Icons.auto_fix_high),
              tooltip: 'Clean GPS spikes',
              onPressed: () => _cleanSpikes(context, ref),
            ),
            IconButton(
              key: const Key('exportButton'),
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export GPX',
              onPressed: () => _export(context, ref),
            ),
            IconButton(
              key: const Key('deleteTrackButton'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () => _delete(context, ref),
            ),
          ],
        ),
        body: trackAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (track) {
            if (track == null) {
              return const Center(child: Text('Ride not found'));
            }
            final points = pointsAsync.value ?? const <TrackPoint>[];
            // Until the points are in, the map and the chart have nothing to
            // show yet (not "no track").
            const loading = Center(child: CircularProgressIndicator());
            final pointsLoaded = pointsAsync.hasValue;
            return TabBarView(
              // No swiping between tabs: a sideways drag on the map or the
              // chart moves it, never the page.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StatsTab(track: track, points: points),
                // Kept alive: switching tabs doesn't reload the map.
                _KeepAlive(
                  child: !pointsLoaded
                      ? loading
                      : points.length < 2
                          ? const Center(child: Text('No track recorded'))
                          : RideMap(points: points),
                ),
                _KeepAlive(
                  child: !pointsLoaded
                      ? loading
                      : _ElevationTab(points: points),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref
          .read(gpxExportServiceProvider)
          .exportToFile(trackId);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved ${file.path}'),
          duration: const Duration(seconds: 10),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(appDatabaseProvider);
    await db.deleteTrack(trackId);
    if (context.mounted) context.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Ride moved to Recently deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => db.restoreTrack(trackId),
        ),
      ),
    );
  }

  Future<void> _cleanSpikes(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await repairTrackSpikes(
      ref.read(appDatabaseProvider),
      ref.read(bikeSettingsLookupProvider),
      trackId,
    );
    // Reload the header stats + points so the map/chart redraw without spikes.
    ref.invalidate(trackProvider(trackId));
    ref.invalidate(trackPointsProvider(trackId));
    final n = result.removed;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n == 0
              ? 'No GPS spikes found'
              : 'Removed $n GPS spike${n == 1 ? '' : 's'} and recomputed stats',
        ),
      ),
    );
  }

  Future<void> _saveToAppleHealth(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(appleHealthExporterProvider)
        .saveRide(trackId);
    messenger.showSnackBar(SnackBar(content: Text(result.userMessage)));
  }
}

/// The numbers: date, bike (tap to change), distance, time, speeds, climb,
/// sensors and battery.
class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.track, required this.points});

  final Track track;
  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      MetricTile(
        label: 'Distance',
        value: formatDistanceKm(track.distanceMeters / 1000),
        unit: 'km',
      ),
      MetricTile(
        label: 'Time',
        value: formatDuration(Duration(seconds: track.durationSeconds)),
        unit: 'h:m:s',
      ),
      MetricTile(
        label: 'Avg',
        value: formatSpeedKmh(track.avgSpeedMps * 3.6),
        unit: 'km/h',
      ),
      MetricTile(
        label: 'Max',
        value: formatSpeedKmh(track.maxSpeedMps * 3.6),
        unit: 'km/h',
      ),
    ];
    if (_hasElevation) {
      tiles.add(
        MetricTile(
          label: 'Ascent',
          value: _ascentMeters.round().toString(),
          unit: 'm',
        ),
      );
    }
    final avgHr = _avg((p) => p.heartRate);
    if (avgHr != null) {
      tiles.add(
        MetricTile(
          label: 'Avg HR',
          value: avgHr.round().toString(),
          unit: 'bpm',
        ),
      );
    }
    final avgCad = _avg((p) => p.cadenceRpm);
    if (avgCad != null) {
      tiles.add(
        MetricTile(
          label: 'Avg cadence',
          value: avgCad.round().toString(),
          unit: 'rpm',
        ),
      );
    }
    final avgPwr = _avg((p) => p.power);
    if (avgPwr != null) {
      tiles.add(
        MetricTile(
          label: 'Avg power',
          value: avgPwr.round().toString(),
          unit: 'W',
        ),
      );
    }
    final bStart = track.batteryStartPercent;
    final bEnd = track.batteryEndPercent;
    if (bStart != null && bEnd != null) {
      final drain = (bStart - bEnd).toDouble();
      tiles.add(
        MetricTile(
          label: 'Battery used',
          value: drain.toStringAsFixed(1),
          unit: '%',
        ),
      );
      final hours = track.durationSeconds / 3600.0;
      if (hours > 0) {
        tiles.add(
          MetricTile(
            label: 'Battery rate',
            value: (drain / hours).toStringAsFixed(1),
            unit: '%/h',
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          formatDateTime(track.startedAt),
          style: const TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 6),
        Consumer(
          builder: (context, ref, _) {
            final profiles = ref.watch(bikeProfilesProvider).profiles;
            final current = profiles
                .where((p) => p.id == track.bikeProfileId)
                .firstOrNull;
            return InkWell(
              key: const Key('trackBikeRow'),
              borderRadius: BorderRadius.circular(6),
              onTap: () async {
                final chosen = await showBikeProfilePicker(
                  context,
                  profiles: profiles,
                  currentId: track.bikeProfileId,
                );
                if (chosen == null) return;
                await ref
                    .read(appDatabaseProvider)
                    .setTrackBikeProfile(track.id, chosen);
                ref.invalidate(trackProvider(track.id));
                ref.invalidate(tracksProvider);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.pedal_bike,
                      size: 18,
                      color: current != null
                          ? Color(current.colorArgb)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      current?.name ?? 'Unassigned',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: Colors.white38,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < tiles.length; i += 2) ...[
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < tiles.length
                      ? tiles[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  bool get _hasElevation => points.any((p) => p.altitude != null);

  // Counted like the live CLIMB (smoothed, with a threshold), so both agree.
  double get _ascentMeters => rideClimbMeters(
    points.map((p) => (altitude: p.altitude, speedMps: p.speedMps)),
  );

  double? _avg(num? Function(TrackPoint) select) {
    var sum = 0.0;
    var n = 0;
    for (final p in points) {
      final v = select(p);
      if (v != null) {
        sum += v;
        n++;
      }
    }
    return n == 0 ? null : sum / n;
  }
}

/// The height profile, filling the tab: pinch to zoom in, drag to pan.
class _ElevationTab extends StatelessWidget {
  const _ElevationTab({required this.points});

  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final heights = [
      for (final p in points)
        if (p.altitude != null) p.altitude!,
    ];
    if (heights.isEmpty) {
      return const Center(
        key: Key('noElevation'),
        child: Text('No heights recorded for this ride'),
      );
    }
    var low = heights.first, high = heights.first;
    for (final h in heights) {
      if (h < low) low = h;
      if (h > high) high = h;
    }
    final climb = rideClimbMeters(
      points.map((p) => (altitude: p.altitude, speedMps: p.speedMps)),
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Climb ${climb.round()} m · lowest ${low.round()} m · '
            'highest ${high.round()} m',
            key: const Key('elevationSummary'),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pinch to zoom, drag to pan',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 1,
              maxScale: 8,
              child: _ElevationChart(points: points),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps a tab's content alive while another tab shows.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _ElevationChart extends StatelessWidget {
  const _ElevationChart({required this.points});

  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final alt = points[i].altitude;
      if (alt != null) spots.add(FlSpot(i.toDouble(), alt));
    }
    return LineChart(
      duration:
          Duration.zero, // no implicit animation (keeps tests deterministic)
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
        ],
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        // Disabled: fl_chart's own touch handling otherwise wins the gesture
        // arena against the enclosing InteractiveViewer, so pinch-zoom/pan
        // never reached it.
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
