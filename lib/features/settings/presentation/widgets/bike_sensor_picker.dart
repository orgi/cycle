import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/bike_profile.dart';
import '../../../../core/sensors/gatt.dart';
import '../../../sensors/application/sensor_providers.dart';

/// Which paired sensors bike [p] should actively pursue. Unchecking a sensor
/// here stops it being scanned/connected for while this bike is active (e.g. a
/// cadence sensor mounted on a different bike) — it stays paired, just not
/// pursued for this one. Shared by the bike list's menu and the bike's
/// settings screen.
Future<void> showBikeSensorPicker(
    BuildContext context, WidgetRef ref, BikeProfile p) async {
  final paired = ref.read(sensorConnectionProvider).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (paired.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('No sensors paired yet — pair some on the Sensors screen first.'),
    ));
    return;
  }
  var selected = p.sensorIds ?? paired.map((s) => s.id).toSet();
  final result = await showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Sensors for "${p.name}"'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final s in paired)
                CheckboxListTile(
                  key: Key('bikeSensorOption_${s.id}'),
                  value: selected.contains(s.id),
                  title: Text(s.name),
                  subtitle: Text(s.kinds.map((k) => k.label).join(' • ')),
                  onChanged: (checked) => setState(() {
                    selected = {...selected};
                    if (checked == true) {
                      selected.add(s.id);
                    } else {
                      selected.remove(s.id);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('bikeSensorsSave'),
            onPressed: () => Navigator.pop(ctx, selected),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (result == null) return;
  final allPairedIds = paired.map((s) => s.id).toSet();
  // Selecting every paired sensor is the same as "all" (null) — keeps a
  // freshly-paired future sensor included by default instead of silently
  // excluded from a bike that was meant to use "everything".
  await ref.read(sensorConnectionProvider.notifier).setBikeSensors(
      p.id, result.length == allPairedIds.length ? null : result);
}
