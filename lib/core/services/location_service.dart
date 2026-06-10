import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_sample.dart';

/// Abstraction over the platform GPS so the rest of the app depends on a stream
/// of [GeoSample]s rather than on geolocator directly. This keeps controllers
/// testable (inject a fake) and gives us one place to later fuse BLE speed.
abstract class LocationService {
  /// Requests the permissions needed for live tracking. Returns whether
  /// foreground location is usable.
  Future<bool> ensurePermission();

  /// Continuous stream of position samples while subscribed.
  Stream<GeoSample> positions();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Stream<GeoSample> positions() async* {
    // geolocator 14's getPositionStream binds a foreground service that, on
    // Android 14 (incl. the emulator), often connects but never starts
    // requestLocationUpdates — yielding no fixes and no error. Polling the
    // one-shot getCurrentPosition at ~1 Hz uses a different, reliable code path
    // and is exactly the cadence a bike computer needs.
    while (true) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: _settings(),
        );
        yield _toSample(position);
      } catch (e) {
        // Transient (e.g. no fix within timeLimit); retry on the next tick.
        if (kDebugMode) debugPrint('[cycle] getCurrentPosition: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// Platform-specific location settings. On Android we force the raw
  /// `LocationManager` (GPS) provider instead of the fused provider: it gives
  /// unsmoothed positions (better for cycling speed/distance, no road-snapping)
  /// and is the provider the emulator's `geo fix` feeds, so GPS works there too.
  LocationSettings _settings() {
    const accuracy = LocationAccuracy.bestForNavigation;
    const timeLimit = Duration(seconds: 8);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          forceLocationManager: true,
          timeLimit: timeLimit,
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          timeLimit: timeLimit,
        );
      default:
        return const LocationSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          timeLimit: timeLimit,
        );
    }
  }

  GeoSample _toSample(Position p) => GeoSample(
        latitude: p.latitude,
        longitude: p.longitude,
        time: p.timestamp,
        speedMps: p.speed,
        altitudeMeters: p.altitude,
        accuracyMeters: p.accuracy,
      );
}
