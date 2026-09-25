import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_sample.dart';
import '../utils/gps_accuracy_filter.dart';
import 'location_service.dart';

/// Android GPS via ONE continuous native `LocationManager.requestLocationUpdates`
/// (the raw GPS provider), streamed over the `cycle/location` EventChannel —
/// the same continuous request OruxMaps uses, and the only thing that holds a
/// solid fix on the Galaxy A33.
///
/// Why not geolocator: its one-shot `getCurrentPosition` cold-restarted the GPS
/// on every poll (dumpsys: `mStarted=false → startNavigating` each call), so it
/// never settled into a lock and often produced no fix at all; its
/// `getPositionStream` never engaged the receiver on this hardware. See
/// `MainActivity.kt`'s `startLocationUpdates` and CLAUDE.md's GPS section.
///
/// Permission still goes through geolocator (that part works fine); only the
/// position stream is native.
class NativeLocationService implements LocationService {
  static const EventChannel _events = EventChannel('cycle/location');

  Stream<GeoSample>? _shared;

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
  Stream<GeoSample> positions() => _shared ??= _events
      .receiveBroadcastStream()
      .map((e) => _toSample((e as Map).cast<String, Object?>()))
      .where(isAccurateEnough)
      .asBroadcastStream();

  GeoSample _toSample(Map<String, Object?> m) => GeoSample(
        latitude: (m['latitude']! as num).toDouble(),
        longitude: (m['longitude']! as num).toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch((m['timeMillis']! as num).toInt()),
        speedMps: (m['speed'] as num?)?.toDouble(),
        altitudeMeters: (m['altitude'] as num?)?.toDouble(),
        accuracyMeters: (m['accuracy'] as num?)?.toDouble(),
      );
}
