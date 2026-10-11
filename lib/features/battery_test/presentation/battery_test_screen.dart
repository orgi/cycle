import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/battery_test/battery_test_log.dart';
import '../../../core/utils/format.dart';
import '../application/battery_test_providers.dart';

String formatRuntime(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  return '$h:$m h';
}

String _fmtLevel(int? l) => l == null ? '?' : '$l %';

String _fmtDate(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Battery runtime test: start/stop, the running test, and past results.
class BatteryTestScreen extends ConsumerWidget {
  const BatteryTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(batteryTestProvider);
    final results = ref.watch(batteryTestResultsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Battery runtime test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Simulates a ride until the battery runs out: the map moves on a '
            'zigzag through your area, drawing and saving the track, the real '
            'GPS stays on and the screen stays on, like on a ride. Every minute the time and battery level '
            'are saved, so the result survives the phone switching itself off.\n\n'
            'Unplug the charger, keep Cycle open and the phone unlocked, set '
            'the brightness you ride with, and connect your sensors if you '
            'ride with them. After the phone has switched off, charge it to '
            '100 % in one go (this also recalibrates the battery display), '
            'open Cycle, and the result appears here.',
          ),
          const SizedBox(height: 16),
          if (run == null)
            FilledButton.icon(
              key: const Key('batteryTestStart'),
              icon: const Icon(Icons.battery_charging_full),
              label: const Text('Start battery test'),
              onPressed: () => _start(context, ref),
            )
          else
            _RunningCard(run: run),
          const SizedBox(height: 24),
          Text('Results', style: Theme.of(context).textTheme.titleMedium),
          results.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not read results: $e'),
            data: (list) {
              final done = list.where((r) => r.id != run?.id).toList();
              if (done.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No battery tests yet.'),
                );
              }
              return Column(
                children: [for (final r in done) _ResultTile(result: r)],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(batteryTestProvider.notifier).start();
    final msg = switch (result) {
      BatteryTestStartResult.started => null,
      BatteryTestStartResult.alreadyRunning => 'A battery test is already running.',
      BatteryTestStartResult.rideRecording => 'Stop the ride first.',
      BatteryTestStartResult.noArea =>
        'No position or map yet — wait for the map to show, then try again.',
    };
    if (msg != null) messenger.showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _RunningCard extends ConsumerStatefulWidget {
  const _RunningCard({required this.run});
  final BatteryTestRun run;

  @override
  ConsumerState<_RunningCard> createState() => _RunningCardState();
}

class _RunningCardState extends ConsumerState<_RunningCard> {
  late final Timer _tick =
      Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _tick; // start the clock
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final elapsed = DateTime.now().difference(run.startedAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Running for ${formatDuration(elapsed)}',
                key: const Key('batteryTestElapsed'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Battery: ${_fmtLevel(run.startLevel)} → '
                '${_fmtLevel(run.currentLevel)}'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('batteryTestStop'),
              icon: const Icon(Icons.stop),
              label: const Text('Stop test'),
              onPressed: () => ref.read(batteryTestProvider.notifier).stop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({required this.result});
  final BatteryTestResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    final rate = r.drainPerHour;
    final projected = r.projectedFullRuntime;
    final lines = <String>[
      '${_fmtLevel(r.startLevel)} → ${_fmtLevel(r.endLevel)}'
          '${rate == null ? '' : ' · ${rate.toStringAsFixed(1)} %/h'}',
      r.stoppedByHand
          ? 'Stopped by hand'
          : 'Ran until the phone switched off (last sign of life '
              '${_fmtDate(r.lastAlive)})',
      if (r.stoppedByHand && projected != null)
        'Projected 100 → 0 %: ${formatRuntime(projected)}',
      if (r.chargedDuringTest) 'Charger was connected during the test',
    ];
    return Card(
      child: ListTile(
        key: Key('batteryTestResult-${r.id}'),
        title: Text('${formatRuntime(r.runtime)} · ${_fmtDate(r.startedAt)}'),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () =>
              ref.read(batteryTestProvider.notifier).delete(r.id),
        ),
      ),
    );
  }
}
