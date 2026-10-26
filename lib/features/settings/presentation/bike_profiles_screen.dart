import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/bike_profile.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../tracks/application/track_providers.dart';
import '../application/bike_profile_providers.dart';
import 'widgets/bike_color_dot.dart';
import 'widgets/bike_sensor_picker.dart';

/// Manage bike profiles: add/rename/recolour/delete, and pick which is active.
/// Each bike's own settings (sensors, wheel size, auto-pause, auto-start) are
/// on its `BikeSettingsScreen`, from the row's menu.
/// Finding/classifying old rides by criteria lives on the Rides screen instead
/// (`TracksScreen`'s filter icon) — that's where you browse ride history, not
/// here.
class BikeProfilesScreen extends ConsumerWidget {
  const BikeProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(bikeProfilesProvider);
    final notifier = ref.read(bikeProfilesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bike profiles'),
        actions: [
          IconButton(
            key: const Key('addBikeProfileButton'),
            icon: const Icon(Icons.add),
            tooltip: 'Add bike',
            onPressed: () => _add(context, notifier),
          ),
        ],
      ),
      body: data.profiles.isEmpty
          ? const Center(
              child: Text('No bikes yet. Tap + to add one.',
                  style: TextStyle(color: Colors.white54)),
            )
          : ListView(
              children: [
                for (final p in data.profiles)
                  ListTile(
                    key: Key('bikeProfileRow_${p.id}'),
                    leading: GestureDetector(
                      key: Key('bikeProfileColor_${p.id}'),
                      onTap: () => _pickColor(context, notifier, p),
                      child: BikeColorDot(colorArgb: p.colorArgb, radius: 20),
                    ),
                    title: Text(p.name),
                    subtitle:
                        p.id == data.activeId ? const Text('Active') : null,
                    trailing: PopupMenuButton<String>(
                      key: Key('bikeProfileMenu_${p.id}'),
                      onSelected: (action) {
                        switch (action) {
                          case 'settings':
                            context.push('/bike-profiles/${p.id}');
                          case 'rename':
                            _rename(context, notifier, p);
                          case 'sensors':
                            showBikeSensorPicker(context, ref, p);
                          case 'assignAll':
                            _assignAllRides(context, ref, p);
                          case 'delete':
                            _delete(context, notifier, p);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'settings',
                          child: Text('Bike settings'),
                        ),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                          value: 'sensors',
                          child: Text('Sensors for this bike'),
                        ),
                        PopupMenuItem(
                          value: 'assignAll',
                          child: Text('Assign all rides to this bike'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () => notifier.setActive(p.id),
                  ),
              ],
            ),
    );
  }

  Future<void> _add(
      BuildContext context, BikeProfilesController notifier) async {
    final name =
        await _promptName(context, title: 'Add bike', initial: '');
    if (name != null && name.trim().isNotEmpty) {
      if (!await notifier.add(name.trim()) && context.mounted) {
        _nameTaken(context, name.trim());
      }
    }
  }

  /// Same-named bikes would be merged into one by sync, so a second bike
  /// with an existing name is refused.
  void _nameTaken(BuildContext context, String name) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('There is already a bike called "$name"'),
      ));

  Future<void> _rename(BuildContext context, BikeProfilesController notifier,
      BikeProfile p) async {
    final name =
        await _promptName(context, title: 'Rename bike', initial: p.name);
    if (name != null && name.trim().isNotEmpty) {
      if (!await notifier.rename(p.id, name.trim()) && context.mounted) {
        _nameTaken(context, name.trim());
      }
    }
  }

  Future<String?> _promptName(BuildContext context,
      {required String title, required String initial}) {
    final controllerText = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('bikeProfileNameField'),
          controller: controllerText,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Road bike'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('bikeProfileNameSave'),
            onPressed: () => Navigator.pop(ctx, controllerText.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickColor(BuildContext context,
      BikeProfilesController notifier, BikeProfile p) async {
    final color = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose a colour'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in kBikeProfileColors)
              GestureDetector(
                key: Key('bikeProfileColorOption_${c.toRadixString(16)}'),
                onTap: () => Navigator.pop(ctx, c),
                child: BikeColorDot(
                  colorArgb: c,
                  radius: 16,
                  child: c == p.colorArgb
                      ? Icon(Icons.check, color: bikeColorContrast(c))
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
    if (color != null) await notifier.setColor(p.id, color);
  }

  /// Sets every recorded ride's bike to [p] in one go — e.g. "put all my past
  /// rides on Cube" — overwriting any bike each ride currently has.
  Future<void> _assignAllRides(
      BuildContext context, WidgetRef ref, BikeProfile p) async {
    final db = ref.read(appDatabaseProvider);
    final total = (await db.allTracks()).length;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Assign all rides to "${p.name}"?'),
        content: Text(
          'Sets the bike on all $total recorded ride${total == 1 ? '' : 's'} '
          'to "${p.name}", overwriting any bike currently assigned to each '
          'one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('assignAllRidesConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final n = await db.assignAllTracksToBikeProfile(p.id);
    ref.invalidate(tracksProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Assigned $n ride${n == 1 ? '' : 's'} to "${p.name}"'),
      ));
    }
  }

  Future<void> _delete(BuildContext context, BikeProfilesController notifier,
      BikeProfile p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text(
          'Rides already recorded on this bike keep their data — they just '
          "won't match any profile filter anymore.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('bikeProfileDeleteConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await notifier.remove(p.id);
  }
}
