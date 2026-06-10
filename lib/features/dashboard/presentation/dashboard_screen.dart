import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../application/ride_providers.dart';
import 'widgets/metric_tile.dart';

/// The main bike-computer screen: a grid of live metrics plus a start/stop
/// control. Always-on, true-black background for OLED battery saving.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(rideMetricsProvider);
    final recording = ref.watch(recordingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle'),
        actions: [
          IconButton(
            key: const Key('openMapButton'),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Map',
            onPressed: () => context.push('/map'),
          ),
        ],
      ),
      // Fixed, non-scrolling layout so every metric is glanceable at once:
      // a large primary speed tile, then two rows of secondary metrics.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: MetricTile(
                  label: 'Speed',
                  value: formatSpeedKmh(metrics.currentSpeedKmh),
                  unit: 'km/h',
                  emphasized: true,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Distance',
                        value: formatDistanceKm(metrics.distanceKm),
                        unit: 'km',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricTile(
                        label: 'Time',
                        value: formatDuration(metrics.elapsed),
                        unit: 'h:m:s',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Avg',
                        value: formatSpeedKmh(metrics.avgSpeedKmh),
                        unit: 'km/h',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricTile(
                        label: 'Max',
                        value: formatSpeedKmh(metrics.maxSpeedKmh),
                        unit: 'km/h',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('startStopButton'),
        onPressed: () => ref.read(recordingProvider.notifier).toggle(),
        backgroundColor: recording ? Colors.red : Colors.green,
        foregroundColor: Colors.white,
        icon: Icon(recording ? Icons.stop : Icons.play_arrow),
        label: Text(recording ? 'Stop' : 'Start'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
