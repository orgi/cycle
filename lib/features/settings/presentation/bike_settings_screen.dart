import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/bike_settings.dart';
import '../../../core/models/home_layout.dart';
import '../../map/application/home_layout_providers.dart';
import '../application/bike_profile_providers.dart';
import 'widgets/bike_color_dot.dart';
import 'widgets/bike_sensor_picker.dart';
import 'widgets/settings_header.dart';

/// One-line summary of a bike's settings, e.g. for the Settings screen's
/// "active bike" tile: "Wheel 2105 mm · auto-pause below 5 km/h ·
/// auto-start above 8 km/h".
String bikeSettingsSummary(BikeSettings s) => [
      'Wheel ${(s.wheelCircumferenceMeters * 1000).round()} mm',
      s.autoPauseEnabled
          ? 'auto-pause below ${_fmtKmh(s.autoPauseSpeedKmh)} km/h'
          : 'auto-pause off',
      s.autoStartEnabled
          ? 'auto-start above ${_fmtKmh(s.autoStartSpeedKmh)} km/h'
          : 'auto-start off',
    ].join(' · ');

/// Everything that belongs to one bike rather than to the rider or phone:
/// which sensors it uses, its wheel size, auto-pause and auto-start, and the
/// home screen's tiles while riding it. The
/// active bike's settings apply while riding; editing them syncs to the same
/// bike on other phones. `/bike-profiles/:id`.
class BikeSettingsScreen extends ConsumerWidget {
  const BikeSettingsScreen({super.key, required this.bikeId});

  final String bikeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bikes = ref.watch(bikeProfilesProvider);
    final bike = bikes.profiles.where((p) => p.id == bikeId).firstOrNull;
    if (bike == null) {
      // Deleted meanwhile (here or by sync), or not loaded yet.
      return Scaffold(
        appBar: AppBar(title: const Text('Bike settings')),
        body: const Center(child: Text('This bike no longer exists.')),
      );
    }
    final settings = ref.watch(bikeSettingsLookupProvider)(bike.id);
    final notifier = ref.read(bikeProfilesProvider.notifier);
    Future<void> save(BikeSettings next) => notifier.setSettings(bike.id, next);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            BikeColorDot(colorArgb: bike.colorArgb, radius: 10),
            const SizedBox(width: 12),
            Flexible(
              child: Text(bike.name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          if (bike.id == bikes.activeId)
            const ListTile(
              key: Key('bikeSettingsActiveNote'),
              leading: Icon(Icons.check_circle_outline),
              title: Text('Active bike'),
              subtitle: Text('These settings apply to rides you record now.'),
            ),
          const SettingsHeader('Sensors'),
          ListTile(
            key: const Key('bikeSensorsTile'),
            title: const Text('Sensors for this bike'),
            subtitle: Text(bike.sensorIds == null
                ? 'All paired sensors'
                : '${bike.sensorIds!.length} selected'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showBikeSensorPicker(context, ref, bike),
          ),
          ListTile(
            key: const Key('wheelCircumferenceTile'),
            title: const Text('Wheel circumference'),
            subtitle: Text(
              '${(settings.wheelCircumferenceMeters * 1000).round()} mm '
              '— used for BLE speed sensors',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editWheel(context, settings, save),
          ),
          const SettingsHeader('Riding'),
          SwitchListTile(
            key: const Key('autoPauseSwitch'),
            title: const Text('Auto-pause'),
            subtitle: const Text(
              'Pause the timer, distance and average when you stop or slow '
              'below the threshold (e.g. at traffic lights).',
            ),
            value: settings.autoPauseEnabled,
            onChanged: (on) => save(settings.copyWith(autoPauseEnabled: on)),
          ),
          ListTile(
            key: const Key('autoPauseSpeedTile'),
            enabled: settings.autoPauseEnabled,
            title: const Text('Pause below'),
            subtitle: Text('${_fmtKmh(settings.autoPauseSpeedKmh)} km/h'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: settings.autoPauseEnabled
                ? () => _editAutoPauseSpeed(context, settings, save)
                : null,
          ),
          SwitchListTile(
            key: const Key('autoStartSwitch'),
            title: const Text('Auto-start ride'),
            subtitle: const Text(
              'Start recording by itself once you move faster than the '
              'speed below for a few seconds. Stop manually.',
            ),
            value: settings.autoStartEnabled,
            onChanged: (on) => save(settings.copyWith(autoStartEnabled: on)),
          ),
          ListTile(
            key: const Key('autoStartSpeedTile'),
            enabled: settings.autoStartEnabled,
            title: const Text('Start above'),
            subtitle: Text('${_fmtKmh(settings.autoStartSpeedKmh)} km/h'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: settings.autoStartEnabled
                ? () => _editAutoStartSpeed(context, settings, save)
                : null,
          ),
          const SettingsHeader('Home screen'),
          ListTile(
            key: const Key('homeLayoutTile'),
            title: Text(settings.homeLayout == HomeLayout.standard
                ? 'Standard tiles'
                : 'Your own tiles'),
            subtitle: Text(bike.id == bikes.activeId
                ? 'Long-press a tile on the map to move or change it.'
                : 'Make this bike active, then long-press a tile on the map '
                    'to move or change it.'),
            trailing: bike.id == bikes.activeId
                ? TextButton(
                    key: const Key('homeLayoutEdit'),
                    onPressed: () {
                      ref.read(homeLayoutEditingProvider.notifier).set(true);
                      context.go('/');
                    },
                    child: const Text('Edit'),
                  )
                : null,
          ),
          if (settings.homeLayout != HomeLayout.standard)
            ListTile(
              key: const Key('homeLayoutReset'),
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset to the standard tiles'),
              onTap: () =>
                  save(settings.copyWith(homeLayout: HomeLayout.standard)),
            ),
        ],
      ),
    );
  }

  Future<void> _editWheel(
    BuildContext context,
    BikeSettings settings,
    Future<void> Function(BikeSettings) save,
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
      await save(settings.copyWith(wheelCircumferenceMeters: mm / 1000.0));
    }
  }

  Future<void> _editAutoPauseSpeed(
    BuildContext context,
    BikeSettings settings,
    Future<void> Function(BikeSettings) save,
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
      await save(settings.copyWith(autoPauseSpeedKmh: kmh));
    }
  }

  Future<void> _editAutoStartSpeed(
    BuildContext context,
    BikeSettings settings,
    Future<void> Function(BikeSettings) save,
  ) async {
    final controllerText = TextEditingController(
      text: _fmtKmh(settings.autoStartSpeedKmh),
    );
    final kmh = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-start above (km/h)'),
        content: TextField(
          key: const Key('autoStartSpeedField'),
          controller: controllerText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'e.g. 8 for riding, 3 for hiking '
                '($_minAutoStartKmh–$_maxAutoStartKmh)',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('autoStartSpeedSave'),
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controllerText.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (kmh != null && kmh >= _minAutoStartKmh && kmh <= _maxAutoStartKmh) {
      await save(settings.copyWith(autoStartSpeedKmh: kmh));
    }
  }
}

/// Auto-start speeds the dialog accepts (km/h). Walking pace is fine (a
/// hiking profile); below 2 km/h, GPS drift while standing still could start
/// a ride.
const _minAutoStartKmh = 2;
const _maxAutoStartKmh = 40;

/// Formats a km/h threshold without a trailing ".0" (5.0 → "5", 3.5 → "3.5").
String _fmtKmh(double kmh) =>
    kmh == kmh.roundToDouble() ? kmh.round().toString() : kmh.toString();
