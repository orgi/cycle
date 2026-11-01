import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/controls/proximity_hold_detector.dart';
import '../../../core/services/hardware_button_service.dart';
import '../../../core/services/haptics_service.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../sensors/application/sensor_providers.dart';
import 'bike_profile_providers.dart';
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

/// How long after the first hold of a stop (see [ProximityStop]) the second
/// one must be done. Overridable so tests needn't wait in real time.
final proximityStopWindowProvider =
    Provider<Duration>((ref) => const Duration(seconds: 6));

/// Stopping a ride with the hand over the screen takes two holds: the first
/// arms the stop (one buzz) and only a second one — the hand taken away in
/// between, since a hold counts once per cover — within
/// [proximityStopWindowProvider] stops the ride (the stop's two buzzes). A
/// single hover, which used to stop rides by accident, can't any more; an
/// armed stop that isn't confirmed just runs out. Starting stays one hold.
///
/// The state is until when the stop is armed (null: not armed), for the home
/// screen's countdown.
final proximityStopProvider =
    NotifierProvider<ProximityStop, DateTime?>(ProximityStop.new);

class ProximityStop extends Notifier<DateTime?> {
  Timer? _timer;

  @override
  DateTime? build() {
    // Stopped some other way (TIME, a place): nothing left to confirm.
    ref.listen(recordingProvider, (_, recording) {
      if (!recording) disarm();
    });
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// A hold during a ride: true when it is the second one (stop now), false
  /// when it armed the stop.
  bool hold() {
    if (state != null) {
      disarm();
      return true;
    }
    final window = ref.read(proximityStopWindowProvider);
    _timer = Timer(window, disarm);
    state = DateTime.now().add(window);
    return false;
  }

  void disarm() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }
}

/// Wires the volume keys to recording: volume-up starts a ride (or, if one is
/// already recording, cycles the bike profile — see [RecordingController.
/// cycleBikeProfile]); volume-down stops. Only while the setting is enabled.
///
/// Also the glove-friendly proximity gesture (iOS, opt-in): holding a hand over
/// the top of the screen for ~2 s starts a ride; stopping one takes a second
/// hold to confirm ([ProximityStop]). See [ProximityHoldDetector].
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
    if (volumeKeysSupported) unawaited(service.setEnabled(enabled));

    _proximitySub?.cancel();
    _proximitySub = null;
    _hold?.dispose();
    _hold = null;
    if (proximity) {
      final hold = ProximityHoldDetector(
        onHold: _onHold,
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

  void _onHold() {
    final recording = ref.read(recordingProvider.notifier);
    if (!ref.read(recordingProvider)) {
      unawaited(recording.start(manual: true));
    } else if (ref.read(proximityStopProvider.notifier).hold()) {
      unawaited(recording.stop());
    } else if (ref.read(settingsProvider).vibrateOnStartStop) {
      // Armed: "take the hand away, then hold again to stop".
      unawaited(
          ref.read(hapticsServiceProvider).confirm(RideFeedback.stopArmed));
    }
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
          unawaited(recording.start(manual: true));
        }
      case HardwareButton.volumeDown:
        unawaited(recording.stop());
    }
  }
}

/// Pushes the active bike's wheel circumference to the sensor service (used to
/// derive speed from a CSC sensor) — again whenever the bike or its setting
/// changes. Listened from `main()` for the app's lifetime: a widget's watch
/// (the home screen also has one) is paused while another screen covers it,
/// so a bike switched in Settings would only reach the sensor back on the map.
final sensorSettingsSyncProvider = Provider<void>((ref) {
  final circumference = ref.watch(
      activeBikeSettingsProvider.select((s) => s.wheelCircumferenceMeters));
  ref.read(sensorServiceProvider).setWheelCircumference(circumference);
});
