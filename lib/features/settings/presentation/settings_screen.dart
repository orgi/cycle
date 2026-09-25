import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_version.dart';
import '../../../core/services/settings/app_settings.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../tracks/application/track_providers.dart';
import '../../tracks/application/track_repair.dart';
import '../application/bike_profile_providers.dart';
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
          const _Header('Appearance'),
          RadioGroup<AppColorScheme>(
            groupValue: settings.colorScheme,
            onChanged: (s) {
              if (s != null) controller.setColorScheme(s);
            },
            child: Column(
              children: [
                for (final scheme in AppColorScheme.values)
                  RadioListTile<AppColorScheme>(
                    key: Key('scheme_${scheme.name}'),
                    value: scheme,
                    title: Text(scheme.label),
                  ),
              ],
            ),
          ),
          const Divider(),
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
              '— used for BLE speed sensors',
            ),
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
              '(Android only; not available on iOS).',
            ),
            value: settings.hardwareButtonsEnabled,
            onChanged: controller.setHardwareButtons,
          ),
          SwitchListTile(
            key: const Key('showStartStopSwitch'),
            title: const Text('Show Start/Stop button'),
            subtitle: const Text(
              'Off by default — use the volume keys. Always shown when the '
              'volume keys are disabled.',
            ),
            value: settings.showStartStopButton,
            onChanged: controller.setShowStartStopButton,
          ),
          SwitchListTile(
            key: const Key('autoPauseSwitch'),
            title: const Text('Auto-pause'),
            subtitle: const Text(
              'Pause the timer, distance and average when you stop or slow '
              'below the threshold (e.g. at traffic lights).',
            ),
            value: settings.autoPauseEnabled,
            onChanged: controller.setAutoPauseEnabled,
          ),
          ListTile(
            key: const Key('autoPauseSpeedTile'),
            enabled: settings.autoPauseEnabled,
            title: const Text('Pause below'),
            subtitle: Text('${_fmtKmh(settings.autoPauseSpeedKmh)} km/h'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: settings.autoPauseEnabled
                ? () => _editAutoPauseSpeed(context, ref, settings)
                : null,
          ),
          const Divider(),
          const _Header('Bikes'),
          Consumer(builder: (context, ref, _) {
            final profiles = ref.watch(bikeProfilesProvider).profiles;
            final active = ref.watch(bikeProfilesProvider).active;
            return ListTile(
              key: const Key('bikeProfilesTile'),
              leading: const Icon(Icons.pedal_bike),
              title: const Text('Bike profiles'),
              subtitle: Text(active != null
                  ? '${profiles.length} bike${profiles.length == 1 ? '' : 's'}'
                      ' • active: ${active.name}'
                  : 'No bikes yet'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/bike-profiles'),
            );
          }),
          const Divider(),
          const _Header('Accounts'),
          ListTile(
            key: const Key('uploadAccountsTile'),
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Upload accounts'),
            subtitle: const Text('Connect Strava and Komoot for ride upload'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/upload-accounts'),
          ),
          const Divider(),
          const _Header('Data'),
          ListTile(
            key: const Key('backupRestoreTile'),
            leading: const Icon(Icons.save_alt),
            title: const Text('Backup & restore'),
            subtitle: const Text('Move your rides to another phone'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/backup'),
          ),
          ListTile(
            key: const Key('oruxmapsImportTile'),
            leading: const Icon(Icons.map_outlined),
            title: const Text('Import from OruxMaps'),
            subtitle: const Text('Bring in tracks recorded with OruxMaps'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/oruxmaps-import'),
          ),
          ListTile(
            key: const Key('recalculateDistancesTile'),
            leading: const Icon(Icons.straighten),
            title: const Text('Recalculate ride distances'),
            subtitle: const Text(
              'Fixes rides recorded before a GPS-jitter distance fix',
            ),
            onTap: () => _recalculateDistances(context, ref),
          ),
          ListTile(
            key: const Key('removeDuplicatesTile'),
            leading: const Icon(Icons.content_copy),
            title: const Text('Remove duplicate rides'),
            subtitle: const Text(
              'Fixes rides imported twice by an overlapping OruxMaps import',
            ),
            onTap: () => _removeDuplicates(context, ref),
          ),
          const Divider(),
          const _Header('About'),
          const ListTile(
            key: Key('appVersionTile'),
            leading: Icon(Icons.info_outline),
            title: Text('Cycle'),
            subtitle: Text('Version $kAppVersion (build $kAppBuild)'),
          ),
        ],
      ),
    );
  }

  Future<void> _recalculateDistances(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recalculate ride distances?'),
        content: const Text(
          'Recomputes every ride\'s distance/average/max from its recorded '
          'points using the current maths. Use this once after an update '
          'that changes how distance is calculated (e.g. the GPS-jitter '
          'fix) so old rides match new ones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('recalculateDistancesConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Recalculate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final n = await recalculateAllTrackStats(
      ref.read(appDatabaseProvider),
      ref.read(settingsProvider),
    );
    ref.invalidate(tracksProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('Recalculated $n ride${n == 1 ? '' : 's'}')),
    );
  }

  Future<void> _removeDuplicates(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove duplicate rides?'),
        content: const Text(
          'Removes rides that share the exact same start time as another '
          'ride, keeping the first-recorded copy of each — safe to run any '
          'time, and a no-op if you have no duplicates. Use this if an '
          'OruxMaps import ran twice at once (e.g. tapped again before a '
          'slow import finished) and left duplicate rides behind.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('removeDuplicatesConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final n = await removeDuplicateTracks(ref.read(appDatabaseProvider));
    ref.invalidate(tracksProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          n == 0 ? 'No duplicates found' : 'Removed $n duplicate ride${n == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  Future<void> _editWheel(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final controllerText = TextEditingController(
      text: (settings.wheelCircumferenceMeters * 1000).round().toString(),
    );
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

  Future<void> _editAutoPauseSpeed(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final controllerText = TextEditingController(
      text: _fmtKmh(settings.autoPauseSpeedKmh),
    );
    final kmh = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-pause below (km/h)'),
        content: TextField(
          key: const Key('autoPauseSpeedField'),
          controller: controllerText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'Ride pauses when your speed drops below this',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('autoPauseSpeedSave'),
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controllerText.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (kmh != null && kmh >= 0 && kmh < 30) {
      await ref.read(settingsProvider.notifier).setAutoPauseSpeedKmh(kmh);
    }
  }
}

/// Formats a km/h threshold without a trailing ".0" (5.0 → "5", 3.5 → "3.5").
String _fmtKmh(double kmh) =>
    kmh == kmh.roundToDouble() ? kmh.round().toString() : kmh.toString();

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
