import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/metrics/elevation.dart';
import '../../../core/metrics/ride_profile.dart';
import '../../../core/services/apple_health_service.dart';
import '../../../core/utils/format.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../dashboard/presentation/widgets/metric_tile.dart';
import '../../health/application/apple_health_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../../settings/presentation/widgets/bike_profile_picker.dart';
import '../application/track_providers.dart';
import '../application/track_repair.dart';
import 'widgets/ride_elevation_chart.dart';
import 'widgets/ride_map.dart';

class TrackDetailScreen extends ConsumerWidget {
  const TrackDetailScreen({super.key, required this.trackId});

  final int trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackAsync = ref.watch(trackProvider(trackId));
    final pointsAsync = ref.watch(trackPointsProvider(trackId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ride'),
          // Tabs, so the map and the elevation profile get the whole screen
          // and their gestures never fight a page scroll.
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('rideTabStats'), text: 'Stats'),
              Tab(key: Key('rideTabMap'), text: 'Map'),
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
                          : _MapTab(points: points),
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

/// The map with the elevation profile under it, linked: a point picked on
/// either — a tap near the track on the map, a tap or drag on the profile —
/// shows on both, with its distance, height, speed and time. Without heights
/// the map has the tab to itself.
class _MapTab extends StatefulWidget {
  const _MapTab({required this.points});

  final List<TrackPoint> points;

  @override
  State<_MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<_MapTab> {
  late RideProfile _profile = _profileOf(widget.points);
  int? _selected;

  static RideProfile _profileOf(List<TrackPoint> points) => RideProfile([
        for (final p in points)
          (latitude: p.latitude, longitude: p.longitude, altitude: p.altitude),
      ]);

  @override
  void didUpdateWidget(_MapTab old) {
    super.didUpdateWidget(old);
    if (!identical(old.points, widget.points)) {
      // Cleaned of spikes: other points, the old index means nothing.
      _profile = _profileOf(widget.points);
      _selected = null;
    }
  }

  /// A tap on the map selects the track point there — within about a
  /// fingertip (30 px) of it; a tap beside the track clears the selection.
  void _onMapTap(double latitude, double longitude, double metersPerPixel) {
    final i = _profile.nearest(latitude, longitude,
        maxMeters: 30 * metersPerPixel);
    setState(() => _selected = i);
  }

  void _select(int i) {
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final i = _selected;
    final map = RideMap(
      points: widget.points,
      selected: i == null
          ? null
          : (latitude: _profile.latitudes[i], longitude: _profile.longitudes[i]),
      onMapTap: _onMapTap,
    );
    final range = _profile.altitudeRange;
    if (range == null) return map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The profile takes a fifth, the map the rest.
        Expanded(flex: 4, child: map),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: i == null
              ? Text(
                  'Climb ${_climb().round()} m · lowest ${range.low.round()} m'
                  ' · highest ${range.high.round()} m',
                  key: const Key('elevationSummary'),
                  style: const TextStyle(color: Colors.white70),
                )
              : Text(
                  _pointInfo(i),
                  key: const Key('rideSelectionInfo'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
        ),
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: RideElevationChart(
              profile: _profile,
              selected: i,
              onSelect: _select,
            ),
          ),
        ),
      ],
    );
  }

  /// Counted like the live CLIMB (smoothed, with a threshold), so both agree.
  double _climb() => rideClimbMeters(widget.points
      .map((p) => (altitude: p.altitude, speedMps: p.speedMps)));

  /// "12.40 km · 456 m · 23 km/h · 08:42" for point [i].
  String _pointInfo(int i) {
    final p = widget.points[i];
    return [
      '${formatDistanceKm(_profile.distances[i] / 1000)} km',
      if (p.altitude != null) '${p.altitude!.round()} m',
      if (p.speedMps != null) '${(p.speedMps! * 3.6).round()} km/h',
      formatClock(p.time),
    ].join(' · ');
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
