import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen awake while riding (the app is a handlebar bike computer,
/// so the display must stay on). Behind an interface so widget tests can use a
/// no-op implementation instead of hitting the platform channel.
abstract class ScreenWakeService {
  Future<void> enable();
  Future<void> disable();
}

class WakelockScreenWakeService implements ScreenWakeService {
  const WakelockScreenWakeService();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

/// Used in tests; does nothing.
class NoopScreenWakeService implements ScreenWakeService {
  const NoopScreenWakeService();

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}
