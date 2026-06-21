import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/settings/app_settings.dart';
import '../application/settings_providers.dart';

/// App preferences: units, wheel size and physical-button control.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Units'),
          RadioGroup<UnitSystem>(
            groupValue: settings.units,
            onChanged: (u) {
              if (u != null) controller.setUnits(u);
            },
            child: Column(
              children: [
                RadioListTile<UnitSystem>(
                  key: const Key('unitsMetric'),
                  value: UnitSystem.metric,
                  title: const Text('Metric (km, km/h)'),
                ),
                RadioListTile<UnitSystem>(
                  key: const Key('unitsImperial'),
                  value: UnitSystem.imperial,
                  title: const Text('Imperial (mi, mph)'),
                ),
              ],
            ),
          ),
          const Divider(),
          const _Header('Sensors'),
          ListTile(
            title: const Text('Wheel circumference'),
            subtitle: Text(
                '${(settings.wheelCircumferenceMeters * 1000).round()} mm '
                '— used for BLE speed sensors'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editWheel(context, ref, settings),
          ),
          const Divider(),
          const _Header('Controls'),
          SwitchListTile(
            key: const Key('hardwareButtonsSwitch'),
            title: const Text('Volume keys start/stop'),
            subtitle: const Text(
                'Use the phone\'s volume buttons to start/stop recording '
                '(Android only; not available on iOS).'),
            value: settings.hardwareButtonsEnabled,
            onChanged: controller.setHardwareButtons,
          ),
        ],
      ),
    );
  }

  Future<void> _editWheel(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final controllerText = TextEditingController(
        text: (settings.wheelCircumferenceMeters * 1000).round().toString());
    final mm = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wheel circumference (mm)'),
        content: TextField(
          key: const Key('wheelCircumferenceField'),
          controller: controllerText,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'e.g. 2105 for 700×25c, 2200 for 29″',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('wheelCircumferenceSave'),
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controllerText.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (mm != null && mm > 500 && mm < 4000) {
      await ref
          .read(settingsProvider.notifier)
          .setWheelCircumference(mm / 1000.0);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
