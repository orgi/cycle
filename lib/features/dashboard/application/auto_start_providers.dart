import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/controls/auto_start_detector.dart';
import '../../settings/application/settings_providers.dart';
import 'ride_providers.dart';

/// Starts a ride by itself once the rider is riding (opt-in setting), so a
/// gloved rider never has to touch the phone to begin recording. Stopping stays
/// manual. See [AutoStartDetector] for the rule and why it disarms after a ride
/// until the rider has stood still for a while.
///
/// Uses the same shared GPS stream the dashboard already consumes, so it costs
/// no extra battery. Like the GPS itself it only sees fixes while the app is in
/// the foreground (or a ride records), which matches the screen-on use case.
///
/// Watched by the home screen to keep it alive. The bool mirrors the setting.
final autoStartControllerProvider =
    NotifierProvider<AutoStartController, bool>(AutoStartController.new);

class AutoStartController extends Notifier<bool> {
  @override
  bool build() {
    final enabled =
        ref.watch(settingsProvider.select((s) => s.autoStartEnabled));
    if (!enabled) return false;

    final detector = AutoStartDetector();
    final sub = ref.watch(locationServiceProvider).positions().listen((sample) {
      final recording = ref.read(recordingProvider);
      if (detector.update(sample, recording: recording)) {
        unawaited(ref.read(recordingProvider.notifier).start());
      }
    });
    ref.onDispose(sub.cancel);
    return true;
  }
}
