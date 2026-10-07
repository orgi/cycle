import 'package:flutter/services.dart';

/// What happened, felt as a number of vibration pulses — distinct enough to
/// tell apart through gloves with the phone on the handlebar, which is where
/// the hands-free triggers (volume keys, hand over screen, auto-start) are used
/// without looking at the screen.
enum RideFeedback {
  started(1),
  stopped(2),
  bikeProfileChanged(3);

  const RideFeedback(this.pulses);
  final int pulses;
}

/// Vibrates to confirm a ride event. Behind an interface so tests can record
/// what would have been felt.
abstract class HapticsService {
  Future<void> confirm(RideFeedback feedback);
}

/// Native `cycle/haptics` channel (`MainActivity.kt` / `AppDelegate.swift`):
/// `vibrate(n)` plays n pulses. Plain Flutter `HapticFeedback` is too weak for
/// this on both platforms (a Taptic tick on iOS, a view-level click on
/// Android that the system may suppress).
class NativeHapticsService implements HapticsService {
  const NativeHapticsService();

  static const _channel = MethodChannel('cycle/haptics');

  @override
  Future<void> confirm(RideFeedback feedback) async {
    try {
      await _channel.invokeMethod<void>('vibrate', feedback.pulses);
    } catch (_) {
      // No handler (tests, other platforms) — feedback is best-effort.
    }
  }
}

class NoopHapticsService implements HapticsService {
  const NoopHapticsService();

  @override
  Future<void> confirm(RideFeedback feedback) async {}
}
