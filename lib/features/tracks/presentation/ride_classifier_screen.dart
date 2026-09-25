import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../../../core/utils/format.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/bike_profile_providers.dart';
import '../application/ride_classifier.dart';
import '../application/track_providers.dart';

/// Finds old rides matching a combination of criteria (unassigned, sensor
/// data present, distance/speed/date range) and bulk-assigns the matches to a
/// bike in one go — for classifying a ride history recorded before bike
/// profiles existed, or just correcting a batch of misassigned rides.
class RideClassifierScreen extends ConsumerStatefulWidget {
  const RideClassifierScreen({super.key});

  @override
  ConsumerState<RideClassifierScreen> createState() =>
      _RideClassifierScreenState();
}

class _RideClassifierScreenState extends ConsumerState<RideClassifierScreen> {
  bool _onlyUnassigned = true;
  bool _requireCadence = false;
  bool _requireHr = false;
  bool _requirePower = false;

  final _minDistance = TextEditingController();
  final _maxDistance = TextEditingController();
  final _minAvgSpeed = TextEditingController();
  final _maxAvgSpeed = TextEditingController();
  final _minMaxSpeed = TextEditingController();
  final _maxMaxSpeed = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

  List<Track>? _results; // null = haven't searched yet
  String? _assignTo;

  @override
  void dispose() {
    for (final c in [
      _minDistance,
      _maxDistance,
      _minAvgSpeed,
      _maxAvgSpeed,
      _minMaxSpeed,
      _maxMaxSpeed,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim());

  RideClassifierFilter _buildFilter() {
    final minDist = _num(_minDistance);
    final maxDist = _num(_maxDistance);
    final minAvg = _num(_minAvgSpeed);
    final maxAvg = _num(_maxAvgSpeed);
    final minMax = _num(_minMaxSpeed);
    final maxMax = _num(_maxMaxSpeed);
    final end = _endDate;
    return RideClassifierFilter(
      onlyUnassigned: _onlyUnassigned,
      requireCadenceData: _requireCadence,
      requireHeartRateData: _requireHr,
      requirePowerData: _requirePower,
      minDistanceMeters: minDist != null ? minDist * 1000 : null,
      maxDistanceMeters: maxDist != null ? maxDist * 1000 : null,
      minAvgSpeedMps: minAvg != null ? minAvg / 3.6 : null,
      maxAvgSpeedMps: maxAvg != null ? maxAvg / 3.6 : null,
      minMaxSpeedMps: minMax != null ? minMax / 3.6 : null,
      maxMaxSpeedMps: maxMax != null ? maxMax / 3.6 : null,
      startedAfter: _startDate,
      // A date picker only gives a day — extend to the end of it so
      // "before" is inclusive of rides recorded that day.
      startedBefore:
          end != null ? DateTime(end.year, end.month, end.day, 23, 59, 59) : null,
    );
  }

  Future<void> _find() async {
    final db = ref.read(appDatabaseProvider);
    final result = await filterTracksForClassification(db, _buildFilter());
    if (!mounted) return;
    setState(() {
      _results = result;
      _assignTo = null;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _assign() async {
    final results = _results;
    final bikeId = _assignTo;
    if (results == null || results.isEmpty || bikeId == null) return;
    final bike =
        ref.read(bikeProfilesProvider).profiles.where((p) => p.id == bikeId);
    if (bike.isEmpty) return;
    final name = bike.first.name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            'Assign ${results.length} ride${results.length == 1 ? '' : 's'} '
            'to "$name"?'),
        content: const Text(
          'This overwrites the bike currently assigned to each matching ride.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('classifyAssignConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final db = ref.read(appDatabaseProvider);
    final n = await db.assignTracksToBikeProfile(
        results.map((t) => t.id).toList(), bikeId);
    ref.invalidate(tracksProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Assigned $n ride${n == 1 ? '' : 's'} to "$name"'),
    ));
    setState(() => _results = null);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(bikeProfilesProvider).profiles;
    final results = _results;

    return Scaffold(
      appBar: AppBar(title: const Text('Classify rides')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SwitchListTile(
            key: const Key('onlyUnassignedSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Only unassigned rides'),
            value: _onlyUnassigned,
            onChanged: (v) => setState(() => _onlyUnassigned = v),
          ),
          const Divider(),
          const _SectionLabel('Has sensor data'),
          CheckboxListTile(
            key: const Key('requireCadenceCheckbox'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Cadence'),
            value: _requireCadence,
            onChanged: (v) => setState(() => _requireCadence = v ?? false),
          ),
          CheckboxListTile(
            key: const Key('requireHrCheckbox'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Heart rate'),
            value: _requireHr,
            onChanged: (v) => setState(() => _requireHr = v ?? false),
          ),
          CheckboxListTile(
            key: const Key('requirePowerCheckbox'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Power'),
            value: _requirePower,
            onChanged: (v) => setState(() => _requirePower = v ?? false),
          ),
          const Divider(),
          const _SectionLabel('Distance (km)'),
          _MinMaxRow(minKey: 'minDistanceField', maxKey: 'maxDistanceField',
              minController: _minDistance, maxController: _maxDistance),
          const SizedBox(height: 12),
          const _SectionLabel('Average speed (km/h)'),
          _MinMaxRow(minKey: 'minAvgSpeedField', maxKey: 'maxAvgSpeedField',
              minController: _minAvgSpeed, maxController: _maxAvgSpeed),
          const SizedBox(height: 12),
          const _SectionLabel('Max speed (km/h)'),
          _MinMaxRow(minKey: 'minMaxSpeedField', maxKey: 'maxMaxSpeedField',
              minController: _minMaxSpeed, maxController: _maxMaxSpeed),
          const SizedBox(height: 12),
          const _SectionLabel('Date range'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('startDateButton'),
                  onPressed: () => _pickDate(isStart: true),
                  child: Text(_startDate == null
                      ? 'Any start'
                      : formatDateTime(_startDate!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('endDateButton'),
                  onPressed: () => _pickDate(isStart: false),
                  child: Text(
                      _endDate == null ? 'Any end' : formatDateTime(_endDate!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('findRidesButton'),
            onPressed: _find,
            child: const Text('Find rides'),
          ),
          const SizedBox(height: 16),
          if (results != null) ...[
            Text(
              '${results.length} matching ride${results.length == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final t in results)
              ListTile(
                key: Key('classifyResult_${t.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(t.name),
                subtitle: Text(
                  '${formatDateTime(t.startedAt)}  •  '
                  '${formatDistanceKm(t.distanceMeters / 1000)} km',
                ),
              ),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('classifyAssignDropdown'),
                initialValue: _assignTo,
                decoration: const InputDecoration(labelText: 'Assign to bike'),
                items: [
                  for (final p in profiles)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _assignTo = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('classifyAssignButton'),
                onPressed: _assignTo == null ? null : _assign,
                child: Text(
                    'Assign ${results.length} ride${results.length == 1 ? '' : 's'}'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );
}

class _MinMaxRow extends StatelessWidget {
  const _MinMaxRow({
    required this.minKey,
    required this.maxKey,
    required this.minController,
    required this.maxController,
  });

  final String minKey;
  final String maxKey;
  final TextEditingController minController;
  final TextEditingController maxController;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: TextField(
              key: Key(minKey),
              controller: minController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Min'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: Key(maxKey),
              controller: maxController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Max'),
            ),
          ),
        ],
      );
}
