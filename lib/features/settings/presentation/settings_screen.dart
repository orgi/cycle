import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_version.dart';
import '../../../core/services/apple_health_service.dart';
import '../../../core/services/hardware_button_service.dart';
import '../../../core/services/settings/app_settings.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../health/application/apple_health_providers.dart';
import '../../map/presentation/osm_attribution.dart';
import '../../tracks/application/track_providers.dart';
import '../../tracks/application/track_repair.dart';
import '../application/bike_profile_providers.dart';
import '../application/settings_providers.dart';
import 'bike_settings_screen.dart';
import 'widgets/settings_header.dart';

/// App preferences: appearance, units, controls, data. What belongs to a bike
/// (wheel size, auto-pause, auto-start, sensors) is on its bike profile.
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
          const SettingsHeader('Appearance'),
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
          const SettingsHeader('Units'),
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
          const SettingsHeader('Bikes'),
          // Wheel size, auto-pause and auto-start are per bike: the active
          // bike's apply. Its tile is the way in from here.
          Consumer(builder: (context, ref, _) {
            final profiles = ref.watch(bikeProfilesProvider).profiles;
            final active = ref.watch(bikeProfilesProvider).active;
            return Column(
              children: [
                ListTile(
                  key: const Key('bikeProfilesTile'),
                  leading: const Icon(Icons.pedal_bike),
                  title: const Text('Bike profiles'),
                  subtitle: Text(active != null
                      ? '${profiles.length} bike${profiles.length == 1 ? '' : 's'}'
                          ' • active: ${active.name}'
                      : 'No bikes yet'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/bike-profiles'),
                ),
                if (active != null)
                  ListTile(
                    key: const Key('activeBikeSettingsTile'),
                    leading: const Icon(Icons.tune),
                    title: Text('Settings for ${active.name}'),
                    subtitle: Text(bikeSettingsSummary(
                        ref.watch(activeBikeSettingsProvider))),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/bike-profiles/${active.id}'),
                  ),
              ],
            );
          }),
          const Divider(),
          const SettingsHeader('Controls'),
          // Volume-key start/stop where the platform can capture the keys
          // (Android); the hand-over-screen hold where it's wired (iOS).
          if (volumeKeysSupported)
            SwitchListTile(
              key: const Key('hardwareButtonsSwitch'),
              title: const Text('Volume keys start/stop'),
              subtitle: const Text(
                'Volume up starts a ride, volume down stops it. Works with '
                'gloves.',
              ),
              value: settings.hardwareButtonsEnabled,
              onChanged: controller.setHardwareButtons,
            ),
          if (proximityHoldSupported)
            SwitchListTile(
              key: const Key('proximityHoldSwitch'),
              title: const Text('Hand over screen start/stop'),
              subtitle: const Text(
                'Hold a hand over the top of the screen for 2 seconds to start '
                'or stop a ride. Works with gloves. The screen goes dark while '
                'covered.',
              ),
              value: settings.proximityHoldEnabled,
              onChanged: controller.setProximityHoldEnabled,
            ),
          if (volumeKeysSupported || proximityHoldSupported)
            SwitchListTile(
              key: const Key('showStartStopSwitch'),
              title: const Text('Show Start/Stop button'),
              subtitle: Text(volumeKeysSupported
                  ? 'Off by default: use the volume keys. Always shown while '
                      'the volume keys are off.'
                  : 'Can be hidden while "Hand over screen start/stop" is on. '
                      'Always shown otherwise, so you can stop a ride.'),
              value: settings.showStartStopButton,
              onChanged: controller.setShowStartStopButton,
            ),
          SwitchListTile(
            key: const Key('vibrateStartStopSwitch'),
            title: const Text('Vibrate on start/stop'),
            subtitle: const Text(
              'Confirms by feel: 1 buzz = ride started, 2 = stopped, '
              '3 = bike switched.',
            ),
            value: settings.vibrateOnStartStop,
            onChanged: controller.setVibrateOnStartStop,
          ),
          if (appleHealthSupported) ...[
            const Divider(),
            const SettingsHeader('Apple Health'),
            const _AppleHealthSwitch(),
          ],
          const Divider(),
          const SettingsHeader('Data'),
          ListTile(
            key: const Key('syncTile'),
            leading: const Icon(Icons.sync),
            title: const Text('Sync'),
            subtitle: const Text(
                'Keep rides in step across phones via Nextcloud / WebDAV'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/sync'),
          ),
          ListTile(
            key: const Key('recentlyDeletedTile'),
            leading: const Icon(Icons.restore_from_trash_outlined),
            title: const Text('Recently deleted'),
            subtitle: Text(
                'Restore deleted rides (kept ${settings.retentionDays} days)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/recently-deleted'),
          ),
          ListTile(
            key: const Key('retentionTile'),
            leading: const Icon(Icons.history),
            title: const Text('Keep deleted rides & safety backups'),
            subtitle: Text('${settings.retentionDays} days'),
            onTap: () => _editRetention(context, ref, settings),
          ),
          ListTile(
            key: const Key('backupRestoreTile'),
            leading: const Icon(Icons.save_alt),
            title: const Text('Backup & restore'),
            subtitle: const Text('Move your rides to another phone'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/backup'),
          ),
          ListTile(
            key: const Key('batteryTestTile'),
            leading: const Icon(Icons.battery_std),
            title: const Text('Battery runtime test'),
            subtitle: const Text('How long the phone lasts on a ride'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/battery-test'),
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
          const SettingsHeader('About'),
          const ListTile(
            key: Key('appVersionTile'),
            leading: Icon(Icons.info_outline),
            title: Text('Radl'),
            subtitle: Text('Version $kAppVersion (build $kAppBuild)'),
          ),
          const ListTile(
            key: Key('osmCreditTile'),
            leading: Icon(Icons.map_outlined),
            title: Text('Map data © OpenStreetMap contributors'),
            subtitle: Text('Available under the Open Database License (ODbL)'),
            trailing: Icon(Icons.open_in_new),
            onTap: openOsmCopyright,
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
      ref.read(bikeSettingsLookupProvider),
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
          'ride, keeping the first-recorded copy of each (the copies go to '
          'Recently deleted) — safe to run any time, and a no-op if you have '
          'no duplicates. Use this if an '
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

  Future<void> _editRetention(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final controllerText =
        TextEditingController(text: settings.retentionDays.toString());
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep for (days)'),
        content: TextField(
          key: const Key('retentionField'),
          controller: controllerText,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'Deleted rides stay restorable, and automatic safety '
                'backups are kept, for this long (1–365)',
            helperMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('retentionSave'),
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controllerText.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (days != null && days >= 1 && days <= 365) {
      await ref.read(settingsProvider.notifier).setRetentionDays(days);
    }
  }
}

/// "Save rides to Apple Health" (iOS). Turning it on asks iOS for permission
/// first and stays off if it isn't granted.
class _AppleHealthSwitch extends ConsumerWidget {
  const _AppleHealthSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled =
        ref.watch(settingsProvider.select((s) => s.saveToAppleHealth));
    return SwitchListTile(
      key: const Key('appleHealthSwitch'),
      title: const Text('Save rides to Apple Health'),
      subtitle: const Text(
        'Each finished ride is saved as a cycling workout with route, distance '
        'and heart rate. Strava can import it from there: in Strava, Settings → '
        'Applications, Services, and Devices → Health.',
      ),
      value: enabled,
      onChanged: (on) async {
        final controller = ref.read(settingsProvider.notifier);
        if (!on) return controller.setSaveToAppleHealth(false);
        final messenger = ScaffoldMessenger.of(context);
        bool allowed;
        String? problem;
        try {
          allowed = await ref.read(appleHealthServiceProvider).requestAccess();
        } on AppleHealthException catch (e) {
          allowed = false;
          problem = e.message;
        }
        if (allowed) {
          await controller.setSaveToAppleHealth(true);
        } else {
          messenger.showSnackBar(SnackBar(
            content: Text(problem ??
                'Apple Health access was not granted. Allow it in the Health '
                'app → Sharing → Apps → Radl.'),
          ));
        }
      },
    );
  }
}
