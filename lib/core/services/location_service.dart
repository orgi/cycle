import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_sample.dart';
import '../utils/gps_accuracy_filter.dart';

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
  GeolocatorLocationService();

  // One shared location stream feeds all listeners (metrics + map), so they
  // never desync and we don't open the GPS twice.
  Stream<GeoSample>? _shared;

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
  Stream<GeoSample> positions() => _shared ??= _stream().asBroadcastStream();

  /// Holds ONE continuous location stream open, so the GPS chip stays powered
  /// on and keeps a lock instead of cold-cycling. The previous design polled
  /// the one-shot `getCurrentPosition` at 1 Hz — each call powered the GPS up
  /// for a single fix and released it, so the GPS visibly toggled on/off in
  /// the status bar and never settled into a solid lock (poor fixes on a
  /// moving bike). A held-open `getPositionStream` on the raw `LocationManager`
  /// provider is the same continuous `requestLocationUpdates` OruxMaps uses.
  ///
  /// We NEVER close the stream on a missing fix — that would power the GPS
  /// down (the icon would blink off even while "searching", e.g. in a
  /// basement). The stream is only re-subscribed if the platform stream itself
  /// errors out. No fused/assisted fallback: the raw provider keeps the GPS
  /// engine on and searching, and emits as soon as it acquires; a fused
  /// fallback would only road-snap/smooth (bad for cycling) and its historical
  /// Android-14 "never emits" flakiness is a fused-provider problem we avoid by
  /// staying on raw.
  Stream<GeoSample> _stream() async* {
    // Seed immediately with the last known position so the map centres and the
    // location dot appear at once — even before a fresh fix.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final seed = _toSample(last);
        if (isAccurateEnough(seed)) yield seed;
      }
    } catch (_) {}

    while (true) {
      try {
        // Held open indefinitely: filtering inaccurate fixes does NOT close the
        // stream, so the GPS stays continuously on and searching. During normal
        // operation this yield* never returns.
        yield* Geolocator.getPositionStream(locationSettings: _rawStreamSettings())
            .map(_toSample)
            .where(isAccurateEnough);
      } catch (e) {
        // Only a genuine platform error ends the stream (provider disabled,
        // permission revoked mid-ride, …) — resubscribe after a short pause.
        if (kDebugMode) debugPrint('[cycle] positionStream error: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// Continuous-stream location settings. On Android we force the raw
  /// `LocationManager` (GPS) provider instead of the fused provider: it gives
  /// unsmoothed positions (better for cycling speed/distance, no road-snapping),
  /// keeps the GPS continuously on, and is the provider the emulator's
  /// `geo fix` feeds. No `timeLimit` — a held-open stream must survive gaps
  /// under cover without being torn down.
  LocationSettings _rawStreamSettings() {
    const accuracy = LocationAccuracy.bestForNavigation;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          forceLocationManager: true,
          intervalDuration: const Duration(seconds: 1),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
        );
      default:
        return const LocationSettings(
          accuracy: accuracy,
          distanceFilter: 0,
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
