import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ride_providers.dart';

/// Full-width Start/Stop control. Laid out inline (not a floating button) so it
/// never overlaps the metric tiles. Shared by the dashboard and the map view.
class StartStopButton extends ConsumerWidget {
  const StartStopButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(recordingProvider);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        key: const Key('startStopButton'),
        onPressed: () => ref.read(recordingProvider.notifier).toggle(),
        style: FilledButton.styleFrom(
          backgroundColor: recording ? Colors.red : Colors.green,
          foregroundColor: Colors.white,
        ),
        icon: Icon(recording ? Icons.stop : Icons.play_arrow),
        label: Text(recording ? 'Stop' : 'Start'),
      ),
    );
  }
}
