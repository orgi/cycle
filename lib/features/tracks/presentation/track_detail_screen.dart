import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/database.dart';
import '../../../core/export/gpx_exporter.dart';
import '../../../core/services/upload/upload_models.dart';
import '../../../core/utils/format.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../dashboard/presentation/widgets/metric_tile.dart';
import '../../upload/application/upload_providers.dart';
import '../application/track_providers.dart';
import 'widgets/ride_map.dart';
import 'widgets/speed_color.dart';

class TrackDetailScreen extends ConsumerWidget {
  const TrackDetailScreen({super.key, required this.trackId});

  final int trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackAsync = ref.watch(trackProvider(trackId));
    final pointsAsync = ref.watch(trackPointsProvider(trackId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride'),
        actions: [
          IconButton(
            key: const Key('uploadRideButton'),
            icon: const Icon(Icons.cloud_upload_outlined),
            tooltip: 'Upload',
            onPressed: () => _upload(context, ref),
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
          return _Body(track: track, points: points);
        },
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ref.read(gpxExportServiceProvider).exportToFile(trackId);
      messenger.showSnackBar(SnackBar(content: Text('Saved ${file.path}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    await ref.read(appDatabaseProvider).deleteTrack(trackId);
    if (context.mounted) context.pop();
  }

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final track = ref.read(trackProvider(trackId)).value;
    final points =
        ref.read(trackPointsProvider(trackId)).value ?? const <TrackPoint>[];
    if (track == null) return;

    final provider = await showModalBottomSheet<UploadProvider>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in UploadProvider.values)
              ListTile(
                key: Key('upload_${p.name}'),
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text('Upload to ${p.label}'),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (provider == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final gpx = GpxExporter.export(track, points);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await ref.read(uploadControllerProvider.notifier).upload(
          provider,
          gpxBytes: utf8.encode(gpx),
          name: track.name,
          movingSeconds: track.durationSeconds,
        );
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(result.ok
          ? 'Uploaded to ${provider.label}'
              '${result.activityUrl != null ? ' — ${result.activityUrl}' : ''}'
          : 'Upload failed: ${result.error}'),
    ));
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.track, required this.points});

  final Track track;
  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      MetricTile(
          label: 'Distance',
          value: formatDistanceKm(track.distanceMeters / 1000),
          unit: 'km'),
      MetricTile(
          label: 'Time',
          value: formatDuration(Duration(seconds: track.durationSeconds)),
          unit: 'h:m:s'),
      MetricTile(
          label: 'Avg',
          value: formatSpeedKmh(track.avgSpeedMps * 3.6),
          unit: 'km/h'),
      MetricTile(
          label: 'Max',
          value: formatSpeedKmh(track.maxSpeedMps * 3.6),
          unit: 'km/h'),
    ];
    if (_hasElevation) {
      tiles.add(MetricTile(
          label: 'Ascent', value: _ascentMeters.round().toString(), unit: 'm'));
    }
    final avgHr = _avg((p) => p.heartRate);
    if (avgHr != null) {
      tiles.add(MetricTile(
          label: 'Avg HR', value: avgHr.round().toString(), unit: 'bpm'));
    }
    final avgCad = _avg((p) => p.cadenceRpm);
    if (avgCad != null) {
      tiles.add(MetricTile(
          label: 'Avg cadence',
          value: avgCad.round().toString(),
          unit: 'rpm'));
    }
    final avgPwr = _avg((p) => p.power);
    if (avgPwr != null) {
      tiles.add(MetricTile(
          label: 'Avg power', value: avgPwr.round().toString(), unit: 'W'));
    }
    final bStart = track.batteryStartPercent;
    final bEnd = track.batteryEndPercent;
    if (bStart != null && bEnd != null) {
      tiles.add(MetricTile(
          label: 'Battery used',
          value: (bStart - bEnd).toDouble().toStringAsFixed(1),
          unit: '%'));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(formatDateTime(track.startedAt),
            style: const TextStyle(color: Colors.white54)),
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
                        : const SizedBox.shrink()),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const Text('MAP — track coloured by speed (pinch to zoom)',
            style: TextStyle(color: Colors.white54, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        SizedBox(height: 300, child: RideMap(points: points)),
        const SizedBox(height: 8),
        const _SpeedLegend(),
        if (_hasElevation) ...[
          const SizedBox(height: 16),
          const Text('ELEVATION (pinch to zoom)',
              style: TextStyle(color: Colors.white54, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 1,
              maxScale: 8,
              child: _ElevationChart(points: points),
            ),
          ),
        ],
      ],
    );
  }

  bool get _hasElevation => points.any((p) => p.altitude != null);

  double get _ascentMeters {
    var gain = 0.0;
    double? prev;
    for (final p in points) {
      final a = p.altitude;
      if (a == null) continue;
      if (prev != null && a > prev) gain += a - prev;
      prev = a;
    }
    return gain;
  }

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

/// Red (slow, ≤10 km/h) → violet (fast, ≥60 km/h) gradient key for the track.
class _SpeedLegend extends StatelessWidget {
  const _SpeedLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('10', style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [
                  for (var i = 0; i <= 10; i++) Color(speedColorArgb(10 + i * 5)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Text('60+ km/h',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
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
      duration: Duration.zero, // no implicit animation (keeps tests deterministic)
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
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
        ],
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
      ),
    );
  }
}
