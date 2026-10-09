import 'package:flutter/services.dart';

/// Reads the device battery level (0–100%). Behind an interface so tests inject
/// a fake and non-Android platforms can no-op.
abstract class BatteryService {
  Future<int?> level();
}

/// Native `cycle/battery` channel: `MainActivity.kt` (Android, whole %) and
/// `AppDelegate.swift` (iOS — which rounds to 5 % steps since iOS 17, so short
/// rides may read 0 %).
class NativeBatteryService implements BatteryService {
  static const _channel = MethodChannel('cycle/battery');

  @override
  Future<int?> level() async {
    try {
      return await _channel.invokeMethod<int>('getLevel');
    } catch (_) {
      return null; // channel unavailable (tests) → no battery stat
    }
  }
}

class NoopBatteryService implements BatteryService {
  @override
  Future<int?> level() async => null;
}
