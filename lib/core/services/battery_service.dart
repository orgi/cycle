import 'package:flutter/services.dart';

/// Reads the device battery level (0–100%). Behind an interface so tests inject
/// a fake and non-Android platforms can no-op.
abstract class BatteryService {
  Future<int?> level();
}

/// Android implementation via the native `cycle/battery` channel.
class NativeBatteryService implements BatteryService {
  static const _channel = MethodChannel('cycle/battery');

  @override
  Future<int?> level() async {
    try {
      return await _channel.invokeMethod<int>('getLevel');
    } catch (_) {
      return null; // channel unavailable (e.g. iOS) → no battery stat
    }
  }
}

class NoopBatteryService implements BatteryService {
  @override
  Future<int?> level() async => null;
}
