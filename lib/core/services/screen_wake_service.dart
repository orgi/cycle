import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen awake while riding (the app is a handlebar bike computer,
/// so the display must stay on). Behind an interface so widget tests can use a
/// no-op implementation instead of hitting the platform channel.
///
/// Keep-awake has **more than one owner** — a recording ride and an in-flight
/// map download both want it — so requests are reference-counted by owner
/// rather than driving a single global flag. Without this, whichever owner
/// finished first released the screen out from under the other: stopping a ride
/// while a region download was running let the screen sleep, the OS suspend the
/// app and the download drop (it resumes from its `.part` file on retry, but
/// only after the user notices).
///
/// The platform call is made only on a transition: the first [enable] turns it
/// on, and it stays on until the last owner has [disable]d. Both are idempotent
/// per owner.
abstract class ScreenWakeService {
  final Set<String> _owners = <String>{};

  /// Owner key for a recording ride.
  static const String ownerRecording = 'recording';

  /// Owner key for an in-flight map region download.
  static const String ownerMapDownload = 'map-download';

  /// Whether any owner currently holds keep-awake.
  @visibleForTesting
  bool get isHeld => _owners.isNotEmpty;

  Future<void> enable(String owner) async {
    final wasHeld = _owners.isNotEmpty;
    _owners.add(owner);
    if (!wasHeld) await applyEnabled(true);
  }

  Future<void> disable(String owner) async {
    if (!_owners.remove(owner)) return;
    if (_owners.isEmpty) await applyEnabled(false);
  }

  /// Applies the actual platform state. Called only on a transition.
  @protected
  Future<void> applyEnabled(bool on);
}

class WakelockScreenWakeService extends ScreenWakeService {
  @override
  Future<void> applyEnabled(bool on) =>
      on ? WakelockPlus.enable() : WakelockPlus.disable();
}

/// Used in tests; does nothing.
class NoopScreenWakeService extends ScreenWakeService {
  @override
  Future<void> applyEnabled(bool on) async {}
}
