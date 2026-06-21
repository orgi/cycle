import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/hardware_button_service.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../sensors/application/sensor_providers.dart';
import 'settings_providers.dart';

/// Physical-button source. Overridable in tests.
final hardwareButtonServiceProvider = Provider<HardwareButtonService>((ref) {
  final service = MethodChannelHardwareButtonService();
  ref.onDispose(service.dispose);
  return service;
});

/// Wires the volume keys to recording: volume-up starts, volume-down stops, but
/// only while the setting is enabled. Watched by the home screen to keep it
/// alive. The returned bool mirrors the enabled state.
final hardwareButtonControllerProvider =
    NotifierProvider<HardwareButtonController, bool>(
        HardwareButtonController.new);

class HardwareButtonController extends Notifier<bool> {
  StreamSubscription<HardwareButton>? _sub;

  @override
  bool build() {
    final service = ref.watch(hardwareButtonServiceProvider);
    final enabled =
        ref.watch(settingsProvider.select((s) => s.hardwareButtonsEnabled));

    _sub?.cancel();
    _sub = service.events.listen(_onButton);
    unawaited(service.setEnabled(enabled));
    ref.onDispose(() => _sub?.cancel());
    return enabled;
  }

  void _onButton(HardwareButton button) {
    if (!state) return; // ignore stray events when disabled
    final recording = ref.read(recordingProvider.notifier);
    switch (button) {
      case HardwareButton.volumeUp:
        unawaited(recording.start());
      case HardwareButton.volumeDown:
        unawaited(recording.stop());
    }
  }
}

/// Pushes the wheel-circumference setting to the sensor service (used to derive
/// speed from a CSC sensor). Watched by the home screen to stay alive.
final sensorSettingsSyncProvider = Provider<void>((ref) {
  final circumference =
      ref.watch(settingsProvider.select((s) => s.wheelCircumferenceMeters));
  ref.read(sensorServiceProvider).setWheelCircumference(circumference);
});
