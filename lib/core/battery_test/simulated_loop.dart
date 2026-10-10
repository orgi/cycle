import 'dart:math' as math;

import '../models/geo_sample.dart';

/// A circular route ridden at constant speed — the "ride" the battery runtime
/// test feeds to the map, so the map pans and redraws tiles the way it does on a
/// real ride (a still map costs far less and would overstate the runtime).
///
/// The loop is centred on the rider's own area (last real fix, else the shown
/// map's centre), so it runs over the offline map they actually have installed.
/// Pure and deterministic: the position is a function of the elapsed time only.
class SimulatedLoop {
  const SimulatedLoop({
    required this.centerLat,
    required this.centerLon,
    this.radiusMeters = 800,
    this.speedKmh = 25,
  });

  final double centerLat;
  final double centerLon;
  final double radiusMeters;
  final double speedKmh;

  static const _earthRadius = 6371000.0;

  double get circumferenceMeters => 2 * math.pi * radiusMeters;

  /// Where the simulated rider is after [elapsed], stamped with [time].
  GeoSample sampleAt(Duration elapsed, DateTime time) {
    final speedMps = speedKmh / 3.6;
    final travelled = speedMps * elapsed.inMilliseconds / 1000;
    final angle = 2 * math.pi * (travelled % circumferenceMeters) /
        circumferenceMeters;
    final north = radiusMeters * math.cos(angle);
    final east = radiusMeters * math.sin(angle);
    final lat = centerLat + (north / _earthRadius) * 180 / math.pi;
    final lon = centerLon +
        (east / (_earthRadius * math.cos(centerLat * math.pi / 180))) *
            180 /
            math.pi;
    return GeoSample(
      latitude: lat,
      longitude: lon,
      time: time,
      speedMps: speedMps,
      altitudeMeters: 0,
      accuracyMeters: 5,
    );
  }
}
