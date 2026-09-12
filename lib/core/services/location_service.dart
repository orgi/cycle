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
  Stream<GeoSample> positions() => _shared ??= _poll().asBroadcastStream();

  /// Reads fixes by polling the one-shot `getCurrentPosition` **back-to-back**
  /// (no idle gap): each call blocks until the GPS returns a fix, then the next
  /// request is issued immediately.
  ///
  /// Why polling and not `getPositionStream`: geolocator 14's continuous
  /// `getPositionStream` does not reliably engage the GPS on this hardware
  /// (Android 14 / Galaxy A33) — it connected but never started
  /// `requestLocationUpdates`, so **no fixes and no GPS icon at all**. The
  /// one-shot `getCurrentPosition` path is the one that actually drives the
  /// receiver here (verified on-device: fixes flow, tracks record). It's the
  /// same reason this code polled originally.
  ///
  /// The earlier polling **slept 1s between calls**, which let the GPS power
  /// down in the gap and made the status-bar icon toggle every ~1-2s. Removing
  /// that sleep keeps a request essentially always in flight, so the receiver
  /// stays warm between fixes (far less toggling) while still using the working
  /// one-shot path. A short delay is applied only after an *error*, to avoid a
  /// tight failure loop.
  Stream<GeoSample> _poll() async* {
    // Seed immediately with the last known position so the map centres and the
    // location dot appear at once — even before a fresh fix.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final seed = _toSample(last);
        if (isAccurateEnough(seed)) yield seed;
      }
    } catch (_) {}

    // Prefer the raw GPS provider (accurate, unsmoothed). If it can't get a fix
    // for a few tries, fall back to the fused (wifi/cell-assisted) provider for
    // one try so a location still arrives indoors / on a cold start; any
    // success resets to GPS.
    var gpsFailures = 0;
    while (true) {
      final useFused = gpsFailures >= 4;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: useFused ? _fusedSettings() : _settings(),
        );
        final sample = _toSample(position);
        if (isAccurateEnough(sample)) yield sample;
        gpsFailures = 0;
        // No idle delay: loop straight into the next request so the GPS stays
        // warm between fixes instead of powering down.
      } catch (e) {
        // Transient (e.g. no fix within timeLimit); brief pause then retry.
        if (kDebugMode) debugPrint('[cycle] getCurrentPosition: $e');
        if (!useFused) gpsFailures++;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// Fused/assisted provider (wifi/cell), used only as a fallback when the raw
  /// GPS provider can't get a fix — so a location still comes through indoors.
  LocationSettings _fusedSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        forceLocationManager: false,
        timeLimit: const Duration(seconds: 8),
      );
    }
    return _settings();
  }

  /// Per-fix location settings. On Android we force the raw `LocationManager`
  /// (GPS) provider instead of the fused provider: it gives unsmoothed
  /// positions (better for cycling speed/distance, no road-snapping) and is the
  /// provider the emulator's `geo fix` feeds.
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
