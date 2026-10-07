import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sensors/sensor_service.dart';
import '../../dashboard/application/ride_providers.dart';
import 'sensor_providers.dart';

/// Releases BLE sensor links while the app is backgrounded with no ride
/// running, and restores them when it comes back — the Bluetooth counterpart
/// of the native GPS lifecycle gate.
///
/// Why: a pending `autoConnect` registration never expires, so a paired sensor
/// the rider isn't carrying keeps the Bluetooth controller trying to reach it
/// for as long as the process lives. Measured on a real A33 after a weekend of
/// app-open standby: no BLE scanning at all (that rule stands), but six GATT
/// client registrations held open and ~169 mAh — about 3% of the battery —
/// blamed on Cycle, nearly all of it incurred with the screen off. Nothing
/// reads a sensor value in that state.
///
/// A backgrounded *recording* ride keeps its sensors, exactly like the GPS
/// gate: the condition is background AND not recording. Restoring goes through
/// the ordinary direct-connect path plus the bounded retry window, so this adds
/// no scanning.
class SensorPowerGate {
  SensorPowerGate(this._service, {Duration grace = _defaultGrace})
      : _grace = grace {  // ignore: prefer_initializing_formals
    _foreground = _isForeground(
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed);
    _listener = AppLifecycleListener(onStateChange: setLifecycleState);
  }

  /// Backgrounding is not committed to instantly — flicking to another app and
  /// straight back would otherwise tear every link down and build it up again,
  /// and re-registering is the very thing being economised on — but the delay
  /// is deliberately short. This timer runs on the app's own event loop, and
  /// Android's cached-app freezer can freeze a backgrounded process within
  /// seconds; a timer that loses that race never fires at all, leaving exactly
  /// the registrations this gate exists to release. A few seconds absorbs the
  /// inactive→paused→resumed flicker of an app switch while still firing long
  /// before any freezer.
  static const _defaultGrace = Duration(seconds: 3);

  final SensorService _service;
  final Duration _grace;
  late final AppLifecycleListener _listener;

  bool _foreground = true;
  bool _recording = false;
  bool _suspended = false;
  Timer? _graceTimer;

  /// Whether links are currently released.
  @visibleForTesting
  bool get isSuspended => _suspended;

  @visibleForTesting
  void setLifecycleState(AppLifecycleState state) {
    _foreground = _isForeground(state);
    _apply();
  }

  void setRecording(bool recording) {
    _recording = recording;
    _apply();
  }

  // `inactive` is transient (the notification shade, a system dialog, an
  // incoming call banner) and is not backgrounding.
  static bool _isForeground(AppLifecycleState state) =>
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  void _apply() {
    if (_foreground || _recording) {
      _graceTimer?.cancel();
      _graceTimer = null;
      if (_suspended) {
        _suspended = false;
        unawaited(_service.resumeConnections());
      }
      return;
    }
    if (_suspended || _graceTimer != null) return;
    _graceTimer = Timer(_grace, () {
      _graceTimer = null;
      _suspended = true;
      unawaited(_service.suspendConnections());
    });
  }

  void dispose() {
    _graceTimer?.cancel();
    _listener.dispose();
  }
}

/// Owns the gate for the app's lifetime. Read once at startup (see `main()`);
/// it wires itself to the recording state from there.
final sensorPowerGateProvider = Provider<SensorPowerGate>((ref) {
  final gate = SensorPowerGate(ref.read(sensorServiceProvider));
  gate.setRecording(ref.read(recordingProvider));
  ref.listen(recordingProvider, (_, next) => gate.setRecording(next));
  ref.onDispose(gate.dispose);
  return gate;
});
