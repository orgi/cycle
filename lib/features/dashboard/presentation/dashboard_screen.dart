import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/format.dart';
import '../../sensors/application/sensor_providers.dart';
import '../application/ride_providers.dart';
import 'widgets/metric_tile.dart';
import 'widgets/start_stop_button.dart';

/// The main bike-computer screen: a fixed grid of live metrics plus a start/stop
/// control. Always-on, true-black background for OLED battery saving.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(rideMetricsProvider);
    final sensors = ref.watch(sensorSnapshotProvider).value;
    final hasSensorData = sensors != null &&
        (sensors.heartRate != null ||
            sensors.cadenceRpm != null ||
            sensors.power != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle'),
        actions: [
          IconButton(
            key: const Key('openTracksButton'),
            icon: const Icon(Icons.history),
            tooltip: 'Rides',
            onPressed: () => context.push('/tracks'),
          ),
          IconButton(
            key: const Key('openSensorsButton'),
            icon: const Icon(Icons.bluetooth),
            tooltip: 'Sensors',
            onPressed: () => context.push('/sensors'),
          ),
          IconButton(
            key: const Key('openMapButton'),
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Map',
            onPressed: () => context.push('/map'),
          ),
        ],
      ),
      // Fixed, non-scrolling layout so every metric is glanceable at once.
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
                  referenceValue: '88.8', // fixed size — no resize on extra digit
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
                        referenceValue: '888.88',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricTile(
                        label: 'Time',
                        value: formatDuration(metrics.elapsed),
                        unit: 'h:m:s',
                        referenceValue: '88:88:88',
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
                        referenceValue: '88.8',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MetricTile(
                        label: 'Max',
                        value: formatSpeedKmh(metrics.maxSpeedKmh),
                        unit: 'km/h',
                        referenceValue: '88.8',
                      ),
                    ),
                  ],
                ),
              ),
              if (hasSensorData) ...[
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: 'Heart',
                          value: sensors.heartRate?.toString() ?? '--',
                          unit: 'bpm',
                          referenceValue: '888',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricTile(
                          label: 'Cadence',
                          value: sensors.cadenceRpm?.round().toString() ?? '--',
                          unit: 'rpm',
                          referenceValue: '888',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricTile(
                          label: 'Power',
                          value: sensors.power?.toString() ?? '--',
                          unit: 'W',
                          referenceValue: '8888',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const StartStopButton(),
            ],
          ),
        ),
      ),
    );
  }
}
