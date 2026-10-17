import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/apple_health_service.dart';
import '../../dashboard/application/ride_providers.dart';
import '../../settings/application/settings_providers.dart';

/// Writes to Apple Health. Overridable in tests.
final appleHealthServiceProvider =
    Provider<AppleHealthService>((ref) => MethodChannelAppleHealthService());

/// Saves rides to Apple Health (iOS). See [AppleHealthExporter].
final appleHealthExporterProvider =
    Provider<AppleHealthExporter>((ref) => AppleHealthExporter(ref));

/// Outcome of saving one ride.
enum HealthSaveOutcome { saved, alreadySaved, notFinished, failed }

class HealthSaveResult {
  const HealthSaveResult(this.outcome, [this.message]);
  final HealthSaveOutcome outcome;

  /// Why it failed (for [HealthSaveOutcome.failed]).
  final String? message;

  String get userMessage => switch (outcome) {
        HealthSaveOutcome.saved => 'Saved to Apple Health',
        HealthSaveOutcome.alreadySaved => 'Already in Apple Health',
        HealthSaveOutcome.notFinished =>
          'Only finished rides can be saved to Apple Health',
        HealthSaveOutcome.failed => 'Could not save to Apple Health: $message',
      };
}

/// Saves finished rides to Apple Health as cycling workouts, each at most once.
///
/// Which rides were saved is remembered on the phone (by ride start time), so
/// a second tap — or the automatic save after a ride the rider then saves by
/// hand — doesn't create a duplicate workout. Apple Health itself isn't read:
/// that would need read permission just to avoid duplicates.
class AppleHealthExporter {
  AppleHealthExporter(this._ref);
  final Ref _ref;

  static const _savedKey = 'apple_health.saved_rides';

  /// Saves the ride [trackId] unless it already was.
  Future<HealthSaveResult> saveRide(int trackId) async {
    final db = _ref.read(appDatabaseProvider);
    final track = await db.track(trackId);
    if (track == null) return const HealthSaveResult(HealthSaveOutcome.notFinished);
    final ride = healthRideFrom(track, await db.pointsFor(trackId));
    if (ride == null) return const HealthSaveResult(HealthSaveOutcome.notFinished);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_savedKey) ?? const <String>[];
    if (saved.contains(ride.externalId)) {
      return const HealthSaveResult(HealthSaveOutcome.alreadySaved);
    }
    try {
      await _ref.read(appleHealthServiceProvider).saveRide(ride);
    } on AppleHealthException catch (e) {
      return HealthSaveResult(HealthSaveOutcome.failed, e.message);
    }
    await prefs.setStringList(_savedKey, [...saved, ride.externalId]);
    return const HealthSaveResult(HealthSaveOutcome.saved);
  }

  /// Called when a ride ends: saves it if "Save rides to Apple Health" is on.
  /// Never throws — a failed save mustn't disturb stopping a ride; the rider
  /// can still save it by hand from the ride's screen.
  Future<void> saveIfEnabled(int trackId) async {
    if (!appleHealthSupported) return;
    if (!_ref.read(settingsProvider).saveToAppleHealth) return;
    try {
      final result = await saveRide(trackId);
      if (result.outcome == HealthSaveOutcome.failed) {
        debugPrint('Apple Health: ${result.message}');
      }
    } on Object catch (e) {
      debugPrint('Apple Health: $e');
    }
  }
}
