import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/controls/ride_continuation.dart';
import '../../../core/models/geo_sample.dart';
import '../../../core/models/ride_place.dart';
import '../../../core/services/settings/app_settings.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/geo.dart';
import '../../map/application/map_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../application/ride_places_providers.dart';

/// Settings → Controls → Start/stop places: the places where rides start
/// (leaving) and stop (arriving) by themselves. A place is added where the
/// rider stands, so it's set up at home, at work, … once.
class RidePlacesScreen extends ConsumerWidget {
  const RidePlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final places = ref.watch(ridePlacesProvider);
    final here = ref.watch(currentPositionProvider).value;
    final startsAny = places.any((p) => p.trigger.startsRides);

    return Scaffold(
      appBar: AppBar(title: const Text('Start/stop places')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addPlaceButton'),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add this place'),
        onPressed: () => _add(context, ref, places.length),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          SwitchListTile(
            key: const Key('placesEnabledSwitch'),
            title: const Text('Start and stop rides at places'),
            value: settings.placesEnabled,
            onChanged: ref.read(settingsProvider.notifier).setPlacesEnabled,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'A ride starts when you leave a start place, and stops once '
              "you've been at a stop place for "
              '${ref.watch(placeStopAfterProvider).inSeconds} seconds — '
              'riding past doesn\'t stop it. Leaving only counts while Radl is '
              'open with GPS; arriving always counts during a ride.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (startsAny && settings.keepScreenOnMinutes == 0)
            const ListTile(
              key: Key('placesKeepOnHint'),
              leading: Icon(Icons.info_outline),
              title: Text('Tip: keep the screen on'),
              subtitle: Text(
                'Turn on "Keep screen on without a ride" in Settings, so Radl '
                'is still open when you set off.',
              ),
            ),
          const Divider(),
          if (places.isEmpty)
            const Padding(
              key: Key('placesEmpty'),
              padding: EdgeInsets.all(16),
              child: Text(
                'No places yet. Stand where a ride should start or stop — at '
                'home, at work — and tap "Add this place".',
              ),
            ),
          for (final place in places)
            _PlaceTile(place: place, here: here, units: settings.units),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, int count) async {
    final here = _currentFix(ref);
    if (here == null) {
      _noFix(context);
      return;
    }
    final place = await showPlaceDialog(
      context,
      RidePlace(
        id: RidePlacesController.newId(),
        name: count == 0 ? 'Home' : 'Place ${count + 1}',
        latitude: here.latitude,
        longitude: here.longitude,
      ),
      units: ref.read(settingsProvider).units,
      title: 'New place',
    );
    if (place != null) await ref.read(ridePlacesProvider.notifier).put(place);
  }
}

/// The current fix if it's good enough to put a place at: recent, and its
/// error small next to the smallest radius.
GeoSample? _currentFix(WidgetRef ref) {
  final fix = ref.read(currentPositionProvider).value;
  return fix != null && isCurrentFix(fix, DateTime.now(), maxAccuracyMeters: 20)
      ? fix
      : null;
}

void _noFix(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    key: Key('placeNoFixSnack'),
    content: Text(
      'Waiting for an accurate GPS position — try again in a '
      'moment, ideally outdoors.',
    ),
  ),
);

/// A length in the rider's units: metres/feet, kilometres/miles from 1 km.
String _length(double meters, UnitSystem units) {
  if (meters >= 1000) {
    return '${formatDistance(meters / 1000, units)} ${units.distanceLabel}';
  }
  return units == UnitSystem.metric
      ? '${meters.round()} m'
      : '${(meters * 3.28084).round()} ft';
}

IconData _icon(PlaceTrigger t) => switch (t) {
  PlaceTrigger.start => Icons.play_circle_outline,
  PlaceTrigger.stop => Icons.stop_circle_outlined,
  PlaceTrigger.startAndStop => Icons.sync_alt,
};

enum _PlaceAction { edit, moveHere, delete }

class _PlaceTile extends ConsumerWidget {
  const _PlaceTile({
    required this.place,
    required this.here,
    required this.units,
  });

  final RidePlace place;
  final GeoSample? here;
  final UnitSystem units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fix = here;
    String? where;
    if (fix != null) {
      final d = haversineMeters(
        fix.latitude,
        fix.longitude,
        place.latitude,
        place.longitude,
      );
      where = d <= place.radiusMeters
          ? "You're here"
          : '${_length(d, units)} away';
    }
    return ListTile(
      key: Key('place_${place.id}'),
      leading: Icon(_icon(place.trigger)),
      title: Text(place.name),
      subtitle: Text(
        [
          place.trigger.description,
          'radius ${_length(place.radiusMeters, units)}',
          ?where,
        ].join(' · '),
      ),
      onTap: () => _edit(context, ref),
      trailing: PopupMenuButton<_PlaceAction>(
        key: Key('placeMenu_${place.id}'),
        onSelected: (a) => switch (a) {
          _PlaceAction.edit => _edit(context, ref),
          _PlaceAction.moveHere => _moveHere(context, ref),
          _PlaceAction.delete => _delete(context, ref),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _PlaceAction.edit, child: Text('Edit')),
          PopupMenuItem(
            key: Key('placeMoveHere'),
            value: _PlaceAction.moveHere,
            child: Text('Move to where I am'),
          ),
          PopupMenuItem(
            key: Key('placeDelete'),
            value: _PlaceAction.delete,
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final edited = await showPlaceDialog(context, place, units: units);
    if (edited != null) await ref.read(ridePlacesProvider.notifier).put(edited);
  }

  Future<void> _moveHere(BuildContext context, WidgetRef ref) async {
    final fix = _currentFix(ref);
    if (fix == null) {
      _noFix(context);
      return;
    }
    await ref
        .read(ridePlacesProvider.notifier)
        .put(place.copyWith(latitude: fix.latitude, longitude: fix.longitude));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(ridePlacesProvider.notifier);
    await controller.remove(place.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted ${place.name}'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => controller.put(place),
        ),
      ),
    );
  }
}

/// Edits [place]'s name, what it does and its radius; null if cancelled.
Future<RidePlace?> showPlaceDialog(
  BuildContext context,
  RidePlace place, {
  required UnitSystem units,
  String title = 'Edit place',
}) => showDialog<RidePlace>(
  context: context,
  builder: (_) => _PlaceDialog(place: place, units: units, title: title),
);

class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog({
    required this.place,
    required this.units,
    required this.title,
  });

  final RidePlace place;
  final UnitSystem units;
  final String title;

  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.place.name,
  );
  late PlaceTrigger _trigger = widget.place.trigger;
  late double _radius = widget.place.radiusMeters;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radii = {...RidePlace.radiusChoices, _radius}.toList()..sort();
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('placeNameField'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          RadioGroup<PlaceTrigger>(
            groupValue: _trigger,
            onChanged: (t) {
              if (t != null) setState(() => _trigger = t);
            },
            child: Column(
              children: [
                for (final t in PlaceTrigger.values)
                  RadioListTile<PlaceTrigger>(
                    key: Key('placeTrigger_${t.name}'),
                    value: t,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.label),
                    subtitle: Text(t.description),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Radius', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final r in radii)
                ChoiceChip(
                  key: Key('placeRadius_${r.round()}'),
                  label: Text(_length(r, widget.units)),
                  selected: r == _radius,
                  onSelected: (_) => setState(() => _radius = r),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('placeSave'),
          onPressed: () {
            final name = _name.text.trim();
            Navigator.pop(
              context,
              widget.place.copyWith(
                name: name.isEmpty ? widget.place.name : name,
                trigger: _trigger,
                radiusMeters: _radius,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
