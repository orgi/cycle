import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/controls/proximity_hold_detector.dart';
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

/// How long the proximity sensor must stay covered to count as a deliberate
/// hold. Overridable so tests needn't wait in real time.
final proximityHoldDurationProvider =
    Provider<Duration>((ref) => const Duration(seconds: 2));

/// Wires the volume keys to recording: volume-up starts a ride (or, if one is
/// already recording, cycles the bike profile — see [RecordingController.
/// cycleBikeProfile]); volume-down stops. Only while the setting is enabled.
///
/// Also the glove-friendly proximity gesture (iOS, opt-in): holding a hand over
/// the top of the screen for ~2 s toggles recording — starts a ride, or stops
/// the running one. See [ProximityHoldDetector].
///
/// Watched by the home screen to keep it alive. The returned bool mirrors the
/// volume-key enabled state.
final hardwareButtonControllerProvider =
    NotifierProvider<HardwareButtonController, bool>(
        HardwareButtonController.new);

class HardwareButtonController extends Notifier<bool> {
  StreamSubscription<HardwareButton>? _sub;
  StreamSubscription<bool>? _proximitySub;
  ProximityHoldDetector? _hold;

  @override
  bool build() {
    final service = ref.watch(hardwareButtonServiceProvider);
    final enabled =
        ref.watch(settingsProvider.select((s) => s.hardwareButtonsEnabled));
    final proximity = proximityHoldSupported &&
        ref.watch(settingsProvider.select((s) => s.proximityHoldEnabled));

    _sub?.cancel();
    _sub = service.events.listen(_onButton);
    unawaited(service.setEnabled(enabled));

    _proximitySub?.cancel();
    _proximitySub = null;
    _hold?.dispose();
    _hold = null;
    if (proximity) {
      final hold = ProximityHoldDetector(
        onHold: _toggleRecording,
        holdDuration: ref.watch(proximityHoldDurationProvider),
      );
      _hold = hold;
      _proximitySub = service.proximity.listen(hold.update);
    }
    unawaited(service.setProximityEnabled(proximity));

    ref.onDispose(() {
      _sub?.cancel();
      _proximitySub?.cancel();
      _hold?.dispose();
    });
    return enabled;
  }

  void _toggleRecording() {
    final recording = ref.read(recordingProvider.notifier);
    unawaited(ref.read(recordingProvider) ? recording.stop() : recording.start());
  }

  void _onButton(HardwareButton button) {
    if (!state) return; // ignore stray events when disabled
    final recording = ref.read(recordingProvider.notifier);
    switch (button) {
      case HardwareButton.volumeUp:
        if (ref.read(recordingProvider)) {
          // Already recording: a 2nd/3rd/… press corrects the bike profile
          // for this ride instead of a no-op.
          unawaited(recording.cycleBikeProfile());
        } else {
          unawaited(recording.start());
        }
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
