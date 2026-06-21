import 'dart:async';

import 'package:flutter/services.dart';

/// A physical key the rider can use to control recording.
enum HardwareButton { volumeUp, volumeDown }

/// Stream of physical-button presses + control over whether the platform
/// intercepts them. Behind an interface so a fake drives tests.
abstract class HardwareButtonService {
  Stream<HardwareButton> get events;

  /// When enabled, the platform captures the volume keys (so they toggle
  /// recording instead of changing the volume). Disabled restores normal keys.
  Future<void> setEnabled(bool enabled);
}

/// Real implementation over the native `cycle/hardware_buttons` MethodChannel
/// (Android volume keys; see `MainActivity.kt`). Done natively — no plugin — to
/// stay compatible with this project's AGP 9 + standalone-Kotlin build. iOS
/// cannot intercept the volume keys system-wide, so this is a no-op there.
class MethodChannelHardwareButtonService implements HardwareButtonService {
  MethodChannelHardwareButtonService([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('cycle/hardware_buttons') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<HardwareButton> _controller =
      StreamController<HardwareButton>.broadcast();

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'onVolumeKey') {
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

  void dispose() => _controller.close();
}
