import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this platform can capture the volume keys to start/stop a ride:
/// Android natively (`MainActivity.dispatchKeyEvent`), iOS through the
/// volume-level workaround in `AppDelegate.swift` (iOS has no public API).
bool get volumeKeysSupported =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Whether the "hold a hand over the screen" (proximity sensor) gesture is
/// wired natively. iOS only for now.
bool get proximityHoldSupported => defaultTargetPlatform == TargetPlatform.iOS;

/// A physical key the rider can use to control recording.
enum HardwareButton { volumeUp, volumeDown }

/// Stream of physical-button presses + control over whether the platform
/// intercepts them. Behind an interface so a fake drives tests.
abstract class HardwareButtonService {
  Stream<HardwareButton> get events;

  /// When enabled, the platform captures the volume keys (so they toggle
  /// recording instead of changing the volume). Disabled restores normal keys.
  Future<void> setEnabled(bool enabled);

  /// Proximity-sensor state while enabled: true = the top of the screen is
  /// covered. Raw covered/uncovered edges; the hold rule is applied in Dart.
  Stream<bool> get proximity;

  /// Turns proximity monitoring on/off (iOS; a no-op where unsupported).
  Future<void> setProximityEnabled(bool enabled);
}

/// Real implementation over the native `cycle/hardware_buttons` MethodChannel
/// (Android volume keys, see `MainActivity.kt`; iOS volume keys + proximity
/// sensor, see `AppDelegate.swift`). Done natively — no plugin — to stay
/// compatible with this project's AGP 9 + standalone-Kotlin build.
class MethodChannelHardwareButtonService implements HardwareButtonService {
  MethodChannelHardwareButtonService([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('cycle/hardware_buttons') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<HardwareButton> _controller =
      StreamController<HardwareButton>.broadcast();
  final StreamController<bool> _proximity = StreamController<bool>.broadcast();

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'onProximity') {
      if (call.arguments is bool) _proximity.add(call.arguments as bool);
    } else if (call.method == 'onVolumeKey') {
      switch (call.arguments) {
        case 'up':
          _controller.add(HardwareButton.volumeUp);
        case 'down':
          _controller.add(HardwareButton.volumeDown);
      }
    }
    return null;
  }

  @override
  Stream<HardwareButton> get events => _controller.stream;

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on MissingPluginException {
      // No native handler (e.g. iOS / tests) — nothing to intercept.
    }
  }

  @override
  Stream<bool> get proximity => _proximity.stream;

  @override
  Future<void> setProximityEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setProximityEnabled', enabled);
    } on MissingPluginException {
      // Not wired on this platform (Android, tests).
    }
  }

  void dispose() {
    _controller.close();
    _proximity.close();
  }
}
