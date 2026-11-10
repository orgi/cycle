import '../utils/geo.dart';

/// A ride's points laid out along its distance: how far from the start each
/// point is, so the map and the elevation profile can point at the same
/// place — a distance on the profile is a point on the map and back.
/// Immutable; built once per ride's points.
class RideProfile {
  RideProfile._(this.latitudes, this.longitudes, this.altitudes, this.distances);

  factory RideProfile(
      Iterable<({double latitude, double longitude, double? altitude})>
          points) {
    final lat = <double>[], lon = <double>[], alt = <double?>[];
    final dist = <double>[];
    for (final p in points) {
      final d = lat.isEmpty
          ? 0.0
          : dist.last +
              haversineMeters(lat.last, lon.last, p.latitude, p.longitude);
      lat.add(p.latitude);
      lon.add(p.longitude);
      alt.add(p.altitude);
      dist.add(d);
    }
    return RideProfile._(List.unmodifiable(lat), List.unmodifiable(lon),
        List.unmodifiable(alt), List.unmodifiable(dist));
  }

  final List<double> latitudes;
  final List<double> longitudes;
  final List<double?> altitudes;

  /// Metres from the start, per point (never decreasing).
  final List<double> distances;

  int get length => distances.length;
  double get totalMeters => distances.isEmpty ? 0 : distances.last;
  bool get hasAltitude => altitudes.any((a) => a != null);

  /// The lowest and highest height, or null without heights.
  ({double low, double high})? get altitudeRange {
    double? low, high;
    for (final a in altitudes) {
      if (a == null) continue;
      if (low == null || a < low) low = a;
      if (high == null || a > high) high = a;
    }
    return low == null ? null : (low: low, high: high!);
  }

  /// The point nearest [meters] along the ride (clamped to the ride).
  int indexAt(double meters) {
    if (distances.isEmpty) return -1;
    var lo = 0, hi = distances.length - 1;
    while (lo < hi) {
      // First point at or beyond [meters].
      final mid = (lo + hi) >> 1;
      if (distances[mid] < meters) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0 && (meters - distances[lo - 1]) <= (distances[lo] - meters)) {
      return lo - 1;
    }
    return lo;
  }

  /// The point nearest the place [latitude]/[longitude], if one is within
  /// [maxMeters] — a tap on the map near the track, not anywhere.
  int? nearest(double latitude, double longitude, {required double maxMeters}) {
    int? best;
    var bestMeters = maxMeters;
    for (var i = 0; i < length; i++) {
      final d =
          haversineMeters(latitude, longitude, latitudes[i], longitudes[i]);
      if (d <= bestMeters) {
        best = i;
        bestMeters = d;
      }
    }
    return best;
  }

  /// The heights to draw, as (metres along, height), thinned to at most
  /// [maxPoints] (a long ride has tens of thousands; the chart redraws while
  /// the rider drags along it). Keeps the first and last.
  List<({double meters, double altitude})> elevationSamples(
      {int maxPoints = 600}) {
    final all = [
      for (var i = 0; i < length; i++)
        if (altitudes[i] != null)
          (meters: distances[i], altitude: altitudes[i]!),
    ];
    if (all.length <= maxPoints || maxPoints < 2) return all;
    final step = (all.length - 1) / (maxPoints - 1);
    return [for (var k = 0; k < maxPoints; k++) all[(k * step).round()]];
  }
}
