import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sensors/gatt.dart';
import '../application/sensor_providers.dart';

/// Scan for and pair BLE cycling sensors (heart rate, speed/cadence, power).
/// Works with any standard-profile sensor, including modern Garmin sensors.
class SensorsScreen extends ConsumerWidget {
  const SensorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovered = ref.watch(scanResultsProvider);
    final scanning = ref.watch(scanResultsProvider.notifier).scanning;
    final connected = ref.watch(connectedSensorsProvider).value ?? const [];
    final connectedIds = connected.map((c) => c.id).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensors'),
        actions: [
          if (scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              key: const Key('scanButton'),
              icon: const Icon(Icons.bluetooth_searching),
              tooltip: 'Scan',
              onPressed: () =>
                  ref.read(scanResultsProvider.notifier).startScan(),
            ),
        ],
      ),
      body: ListView(
        children: [
          if (connected.isNotEmpty) ...[
            const _SectionHeader('CONNECTED'),
            for (final sensor in connected)
              ListTile(
                key: Key('connected_${sensor.id}'),
                leading: Icon(
                  sensor.connected ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: sensor.connected ? Colors.cyanAccent : Colors.white38,
                ),
                title: Text(sensor.name),
                subtitle: Text(_kindsLabel(sensor.kinds)),
                trailing: TextButton(
                  onPressed: () => ref
                      .read(sensorConnectionProvider.notifier)
                      .disconnect(sensor.id),
                  child: const Text('Disconnect'),
                ),
              ),
          ],
          const _SectionHeader('AVAILABLE'),
          if (discovered.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Tap scan to search for sensors.',
                  style: TextStyle(color: Colors.white54)),
            ),
          for (final sensor in discovered)
            if (!connectedIds.contains(sensor.id))
              ListTile(
                key: Key('discovered_${sensor.id}'),
                leading: const Icon(Icons.sensors),
                title: Text(sensor.name),
                subtitle: Text(_kindsLabel(sensor.kinds)),
                trailing: TextButton(
                  onPressed: () => ref
                      .read(sensorConnectionProvider.notifier)
                      .connect(sensor.id),
                  child: const Text('Connect'),
                ),
              ),
        ],
      ),
    );
  }

  String _kindsLabel(Set<SensorKind> kinds) =>
      kinds.map((k) => k.label).join(' • ');
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white54,
                letterSpacing: 1.2,
              ),
        ),
      );
}
