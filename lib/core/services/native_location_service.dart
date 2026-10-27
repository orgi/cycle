import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_sample.dart';
import 'location_service.dart';
import 'sea_level_altitude.dart';

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
///
/// Every fix is passed on, however inaccurate: the location dot shows them all,
/// and the ride recording applies `isAccurateEnough` itself.
class NativeLocationService implements LocationService {
  static const EventChannel _events = EventChannel('cycle/location');

  Stream<GeoSample>? _shared;
  final SeaLevelAltitude _seaLevel = SeaLevelAltitude();

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
      .map((e) => geoSampleFromNativeFix(
          (e as Map).cast<String, Object?>(), _seaLevel))
      .asBroadcastStream();
}

/// One fix from `MainActivity.locationToMap`, its height above sea level like
/// iOS reports it (see [SeaLevelAltitude]).
GeoSample geoSampleFromNativeFix(
    Map<String, Object?> m, SeaLevelAltitude seaLevel) {
  final time =
      DateTime.fromMillisecondsSinceEpoch((m['timeMillis']! as num).toInt());
  return GeoSample(
    latitude: (m['latitude']! as num).toDouble(),
    longitude: (m['longitude']! as num).toDouble(),
    time: time,
    speedMps: (m['speed'] as num?)?.toDouble(),
    altitudeMeters: seaLevel.resolve(
      fixTime: time,
      altitude: (m['altitude'] as num?)?.toDouble(),
      platformMsl: (m['mslAltitude'] as num?)?.toDouble(),
      gga: m['gga'] as String?,
    ),
    accuracyMeters: (m['accuracy'] as num?)?.toDouble(),
  );
}
