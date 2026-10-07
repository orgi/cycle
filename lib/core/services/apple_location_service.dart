import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_sample.dart';
import '../utils/gps_accuracy_filter.dart';
import 'location_power_control.dart';
import 'location_service.dart';

/// iOS GPS via ONE continuous Core Location request (geolocator's
/// `getPositionStream`, i.e. `CLLocationManager.startUpdatingLocation`) — the
/// iOS counterpart of Android's [NativeLocationService]: a single held-open
/// request so the receiver keeps navigating, never per-fix one-shots.
///
/// The Android warning against `getPositionStream` is about geolocator's
/// *Android* implementation on the Galaxy A33; on iOS the stream is a thin
/// wrapper over Core Location's own continuous updates, which is the standard
/// way to track there. The one-shot `getCurrentPosition` polling in
/// [GeolocatorLocationService] is what to avoid on every platform.
///
/// Also the iOS half of the GPS lifecycle gate ([LocationPowerControl]): the
/// Core Location request is held only while someone listens AND (the app is in
/// the foreground OR a ride is recording) — the same condition
/// `MainActivity.updateLocationUpdates` applies on Android. Background location
/// updates are enabled (so a ride records with the screen off), which would
/// otherwise keep the receiver navigating indefinitely after a ride was
/// stopped and the app backgrounded. Like Android's, this is a lifecycle gate,
/// not a duty cycle: the request starts/stops only on a foreground/background
/// or recording transition, never per fix.
class AppleLocationService implements LocationService, LocationPowerControl {
  AppleLocationService({
    Stream<Position> Function(LocationSettings settings)? positionStream,
    bool observeLifecycle = true,
  }) : _positionStream = positionStream ??
            ((s) => Geolocator.getPositionStream(locationSettings: s)) {
    if (observeLifecycle) {
      _foreground = _isForeground(
          WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed);
      _lifecycle = AppLifecycleListener(onStateChange: setLifecycleState);
    }
  }

  final Stream<Position> Function(LocationSettings settings) _positionStream;
  AppLifecycleListener? _lifecycle;

  late final StreamController<GeoSample> _out =
      StreamController<GeoSample>.broadcast(
    onListen: () {
      _listening = true;
      _apply();
    },
    onCancel: () {
      _listening = false;
      _apply();
    },
  );

  StreamSubscription<Position>? _source;
  bool _listening = false;
  bool _foreground = true;
  bool _recording = false;

  /// Whether the Core Location request is currently held.
  @visibleForTesting
  bool get isTracking => _source != null;

  /// Cycling-tuned: `fitness` activity type, never auto-paused (a stop at a
  /// junction must not end updates), and kept running while backgrounded so a
  /// ride records with the screen off (needs `UIBackgroundModes: location` in
  /// Info.plist; iOS shows the blue location pill meanwhile).
  static final LocationSettings settings = AppleSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
    activityType: ActivityType.fitness,
    pauseLocationUpdatesAutomatically: false,
    allowBackgroundLocationUpdates: true,
    showBackgroundLocationIndicator: true,
  );

  @override
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Stream<GeoSample> positions() => _out.stream;

  @override
  Future<void> setRecordingActive(bool active) async {
    _recording = active;
    _apply();
  }

  @visibleForTesting
  void setLifecycleState(AppLifecycleState state) {
    _foreground = _isForeground(state);
    _apply();
  }

  // `inactive` is transient (Control Centre, a system dialog, an incoming call
  // banner) and is not backgrounding.
  static bool _isForeground(AppLifecycleState state) =>
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  void _apply() {
    final want = _listening && (_foreground || _recording);
    if (want && _source == null) {
      _source = _positionStream(settings).listen(
        (p) {
          final sample = toSample(p);
          if (isAccurateEnough(sample)) _out.add(sample);
        },
        onError: _out.addError,
      );
    } else if (!want && _source != null) {
      unawaited(_source!.cancel());
      _source = null;
    }
  }

  @visibleForTesting
  void dispose() {
    _lifecycle?.dispose();
    unawaited(_source?.cancel());
    _source = null;
    unawaited(_out.close());
  }

  /// Core Location reports an invalid speed / accuracy as a negative value;
  /// map those to "unknown" (null) rather than a real -1 m/s or -1 m.
  static GeoSample toSample(Position p) => GeoSample(
        latitude: p.latitude,
        longitude: p.longitude,
        time: p.timestamp,
        speedMps: p.speed < 0 ? null : p.speed,
        altitudeMeters: p.altitude,
        accuracyMeters: p.accuracy < 0 ? null : p.accuracy,
      );
}
