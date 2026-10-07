import 'package:flutter/services.dart';

/// Tells the native side whether a ride is recording, so it knows whether the
/// continuous GPS request still has a consumer while the app is backgrounded.
///
/// The GPS request used to stay registered for the whole process lifetime —
/// including after a ride was stopped, with the app in the background and the
/// screen off, until Android reclaimed the process. At 1 Hz that is a real,
/// continuous drain that the per-ride battery stat (sampled only between Start
/// and Stop) can never show, which is why Android's per-app battery usage read
/// far higher than the rides accounted for.
///
/// `MainActivity` now holds the request only while Dart is listening AND (the
/// app is in the foreground OR a ride is recording). The recording half of that
/// condition is what this pushes across; the foreground half the activity knows
/// by itself. A backgrounded recording ride is unaffected — it keeps the same
/// single, continuously-held request as before.
abstract class LocationPowerControl {
  Future<void> setRecordingActive(bool active);
}

class NativeLocationPowerControl implements LocationPowerControl {
  const NativeLocationPowerControl();

  static const _channel = MethodChannel('cycle/location_control');

  @override
  Future<void> setRecordingActive(bool active) async {
    try {
      await _channel.invokeMethod<void>('setRecordingActive', active);
    } catch (_) {
      // Channel unavailable (iOS, tests) — the position stream is unaffected.
    }
  }
}

/// Used in tests and on platforms without the native channel.
class NoopLocationPowerControl implements LocationPowerControl {
  const NoopLocationPowerControl();

  @override
  Future<void> setRecordingActive(bool active) async {}
}
