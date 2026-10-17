import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../db/database.dart';

/// Whether rides can be saved to Apple Health on this platform (iOS only).
bool get appleHealthSupported => defaultTargetPlatform == TargetPlatform.iOS;

/// One point of a ride's GPS route.
class HealthRoutePoint {
  const HealthRoutePoint({
    required this.time,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speedMps,
  });

  final DateTime time;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speedMps;
}

/// A finished ride as an Apple Health cycling workout.
class HealthRide {
  const HealthRide({
    required this.externalId,
    required this.start,
    required this.end,
    required this.distanceMeters,
    this.route = const [],
    this.heartRates = const [],
  });

  /// Stable id stored with the workout (`HKMetadataKeyExternalUUID`): the
  /// ride's start second, the same identity the ride sync uses.
  final String externalId;
  final DateTime start;
  final DateTime end;
  final double distanceMeters;
  final List<HealthRoutePoint> route;
  final List<({DateTime time, int bpm})> heartRates;

  /// Channel payload: plain numbers (epoch ms), points as small lists to keep
  /// a long ride's message compact.
  Map<String, Object?> toMap() => {
        'externalId': externalId,
        'startMs': start.millisecondsSinceEpoch,
        'endMs': end.millisecondsSinceEpoch,
        'distanceMeters': distanceMeters,
        'route': [
          for (final p in route)
            [
              p.time.millisecondsSinceEpoch.toDouble(),
              p.latitude,
              p.longitude,
              p.altitude ?? double.nan,
              p.speedMps ?? -1.0,
            ],
        ],
        'heartRates': [
          for (final h in heartRates)
            [h.time.millisecondsSinceEpoch.toDouble(), h.bpm.toDouble()],
        ],
      };
}

/// The id a ride is saved under, from its start time (whole seconds).
String healthRideId(DateTime startedAt) =>
    'radl-ride-${startedAt.toUtc().millisecondsSinceEpoch ~/ 1000}';

/// Builds the workout for a finished [track]; null for a ride that isn't
/// finished (still recording, or cut off by a crash) or has no time span.
HealthRide? healthRideFrom(Track track, List<TrackPoint> points) {
  final end = track.endedAt;
  if (end == null || !end.isAfter(track.startedAt)) return null;
  return HealthRide(
    externalId: healthRideId(track.startedAt),
    start: track.startedAt,
    end: end,
    distanceMeters: track.distanceMeters,
    route: [
      for (final p in points)
        HealthRoutePoint(
          time: p.time,
          latitude: p.latitude,
          longitude: p.longitude,
          altitude: p.altitude,
          speedMps: p.speedMps,
        ),
    ],
    heartRates: [
      for (final p in points)
        if (p.heartRate != null && p.heartRate! > 0)
          (time: p.time, bpm: p.heartRate!),
    ],
  );
}

/// Why saving to Apple Health didn't happen.
class AppleHealthException implements Exception {
  const AppleHealthException(this.message);
  final String message;
  @override
  String toString() => 'AppleHealthException: $message';
}

/// Writes rides to Apple Health. Behind an interface so tests use a fake.
abstract class AppleHealthService {
  /// Asks iOS for permission to save workouts (shows the Health sheet the
  /// first time). True when saving is allowed.
  Future<bool> requestAccess();

  /// Saves [ride] as a cycling workout with its route and heart rate.
  /// Throws [AppleHealthException] when it can't.
  Future<void> saveRide(HealthRide ride);
}

/// The real implementation over the native `cycle/health` channel
/// (`AppleHealth` in `AppDelegate.swift`).
class MethodChannelAppleHealthService implements AppleHealthService {
  MethodChannelAppleHealthService([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('cycle/health');

  final MethodChannel _channel;

  @override
  Future<bool> requestAccess() async {
    try {
      return await _channel.invokeMethod<bool>('requestAccess') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      throw AppleHealthException(e.message ?? e.code);
    }
  }

  @override
  Future<void> saveRide(HealthRide ride) async {
    try {
      await _channel.invokeMethod<void>('saveRide', ride.toMap());
    } on MissingPluginException {
      throw const AppleHealthException('Apple Health is not available here');
    } on PlatformException catch (e) {
      throw AppleHealthException(e.message ?? e.code);
    }
  }
}
