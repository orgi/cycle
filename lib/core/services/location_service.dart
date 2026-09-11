import 'dart:async';

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

  /// Holds ONE continuous location stream open, so the GPS chip keeps a lock
  /// instead of cold-cycling. The previous design polled the one-shot
  /// `getCurrentPosition` at 1 Hz — each call powered the GPS up for a single
  /// fix and released it, so the GPS visibly toggled on/off every ~1-2s in the
  /// status bar and never settled into a solid lock (poor fixes on a moving
  /// bike). A held-open `getPositionStream` on the raw `LocationManager`
  /// provider is the same continuous `requestLocationUpdates` OruxMaps uses.
  ///
  /// geolocator's stream on the *fused* provider was historically flaky on
  /// Android 14 (connected but never emitted). We use the raw provider
  /// (`forceLocationManager: true`), and guard the "never emits" case with a
  /// per-gap timeout that falls back to the assisted provider so a location
  /// still comes through indoors / on a cold start, then returns to raw GPS.
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

    var useFused = false;
    while (true) {
      final settings = useFused ? _fusedStreamSettings() : _rawStreamSettings();
      var gotFix = false;
      try {
        // If no fix arrives for a while the raw provider may be silently stuck
        // (no sky view, or the Android-14 no-emit case) — close the stream so
        // we drop to the assisted provider for a round instead of hanging.
        final stream = Geolocator.getPositionStream(locationSettings: settings)
            .timeout(const Duration(seconds: 12),
                onTimeout: (sink) => sink.close());
        await for (final position in stream) {
          final sample = _toSample(position);
          if (isAccurateEnough(sample)) {
            gotFix = true;
            yield sample;
          }
        }
      } catch (e) {
        // Stream error (permission revoked mid-ride, provider disabled, …) —
        // resubscribe below.
        if (kDebugMode) debugPrint('[cycle] positionStream(fused=$useFused): $e');
      }
      // Raw produced nothing this round → try the assisted provider next;
      // otherwise always prefer raw GPS.
      useFused = !gotFix && !useFused;
      // Only reached when the stream ended/errored — during normal operation
      // the await-for above never returns, so the GPS stays continuously on.
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// Assisted (fused, wifi/cell) provider, used only as a fallback when the raw
  /// GPS stream goes silent — so a location still comes through indoors.
  LocationSettings _fusedStreamSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    return _rawStreamSettings();
  }

  /// Continuous-stream location settings. On Android we force the raw
  /// `LocationManager` (GPS) provider instead of the fused provider: it gives
  /// unsmoothed positions (better for cycling speed/distance, no road-snapping),
  /// keeps the GPS continuously on, and is the provider the emulator's
  /// `geo fix` feeds. No `timeLimit` — a held-open stream must survive gaps
  /// under cover (the [_stream] timeout handles a truly stuck provider).
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
