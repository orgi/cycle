import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sensors/gatt.dart';
import '../../../core/sensors/sensor_catalog.dart';
import '../../../core/sensors/sensor_service.dart';
import '../application/sensor_providers.dart';

/// Scan for and pair BLE cycling sensors (heart rate, speed/cadence, power).
/// Works with any standard-profile sensor, including modern Garmin sensors.
class SensorsScreen extends ConsumerWidget {
  const SensorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discovered = ref.watch(scanResultsProvider);
    final scanning = ref.watch(scanResultsProvider.notifier).scanning;
    final paired = ref.watch(sensorConnectionProvider);
    final live = {
      for (final c in ref.watch(connectedSensorsProvider).value ?? const [])
        c.id: c,
    };
    final pairedIds = paired.map((p) => p.id).toSet();
    final pairedKeys = paired.map((p) => KnownSensor.keyOf(p.name)).toSet();
    // Sensors another phone has but this one hasn't linked yet.
    final elsewhere = ref
        .watch(sensorCatalogProvider)
        .active
        .where((s) => !pairedKeys.contains(s.key))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

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
          if (paired.isNotEmpty) ...[
            const _SectionHeader('PAIRED'),
            for (final p in paired)
              ListTile(
                key: Key('connected_${p.id}'),
                leading: Icon(
                  live[p.id]?.connected == true
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth,
                  color: live[p.id]?.connected == true
                      ? Colors.cyanAccent
                      : Colors.white38,
                ),
                title: Text(p.name),
                subtitle: Text(_kindsLabel(live[p.id]?.kinds ?? p.kinds)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quick manual reconnect for a sensor that hasn't linked
                    // (e.g. a flaky speed sensor) — a one-shot direct connect,
                    // no scanning, shown only while it isn't connected.
                    if (live[p.id]?.connected != true)
                      IconButton(
                        key: Key('reconnect_${p.id}'),
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Reconnect',
                        onPressed: () {
                          ref
                              .read(sensorConnectionProvider.notifier)
                              .reconnectDevice(p.id);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            duration: const Duration(seconds: 2),
                            content: Text('Reconnecting ${p.name}…'),
                          ));
                        },
                      ),
                    TextButton(
                      key: Key('removeSensor_${p.id}'),
                      onPressed: () => _remove(context, ref, p),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ),
          ],
          if (elsewhere.isNotEmpty) ...[
            const _SectionHeader('ON YOUR OTHER PHONES'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Tap scan with the sensor awake nearby (wear the strap, spin '
                'the crank) — it links by itself and joins the same bikes.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white54),
              ),
            ),
            for (final s in elsewhere)
              ListTile(
                key: Key('elsewhere_${s.key}'),
                leading: const Icon(Icons.devices_other, color: Colors.white38),
                title: Text(s.name),
                subtitle: Text(_kindsLabel(s.kinds)),
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
            if (!pairedIds.contains(sensor.id))
              ListTile(
                key: Key('discovered_${sensor.id}'),
                leading: const Icon(Icons.sensors),
                title: Text(sensor.name),
                subtitle: Text(_kindsLabel(sensor.kinds)),
                trailing: TextButton(
                  onPressed: () => ref
                      .read(sensorConnectionProvider.notifier)
                      .connect(sensor),
                  child: const Text('Connect'),
                ),
              ),
        ],
      ),
    );
  }

  String _kindsLabel(Set<SensorKind> kinds) =>
      kinds.map((k) => k.label).join(' • ');

  Future<void> _remove(
      BuildContext context, WidgetRef ref, PairedSensor p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${p.name}"?'),
        content: const Text(
          'It is removed from all your phones (they sync the sensor list). '
          'Pair it again any time with a scan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('removeSensorConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(sensorConnectionProvider.notifier).disconnect(p.id);
    }
  }
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
