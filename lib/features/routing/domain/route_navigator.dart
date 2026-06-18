import 'dart:math' as math;

import 'follow_route.dart';

/// Where the rider is relative to a [FollowRoute], computed from a GPS fix.
class RouteProgress {
  const RouteProgress({
    required this.nearestSegmentIndex,
    required this.crossTrackMeters,
    required this.traveledMeters,
    required this.remainingMeters,
    required this.offRoute,
  });

  /// Index of the route segment (points[i] → points[i+1]) the rider is closest
  /// to.
  final int nearestSegmentIndex;

  /// Perpendicular distance from the rider to the route (metres).
  final double crossTrackMeters;

  /// Distance along the route from the start to the rider's projection (metres).
  final double traveledMeters;

  /// Distance along the route from the rider's projection to the end (metres).
  final double remainingMeters;

  /// Whether the rider has strayed further than the off-route threshold.
  final bool offRoute;
}

/// Locates a GPS position on a [FollowRoute]: nearest segment, cross-track
/// (off-route) distance and distance remaining to the end.
///
/// Pure Dart (no plugin, no map dependency) so it is fully unit-testable. Uses a
/// local equirectangular projection centred on the query point, which is
/// accurate to a fraction of a percent over the few-hundred-metre segments
/// between GPS-spaced route points.
class RouteNavigator {
  RouteNavigator(this.route, {this.offRouteThresholdMeters = 30});

  final FollowRoute route;

  /// Beyond this cross-track distance the rider counts as off route.
  final double offRouteThresholdMeters;

  static const double _metersPerDegLat = 111320.0;

  RouteProgress locate(double latitude, double longitude) {
    final points = route.points;
    final mLon = _metersPerDegLat * math.cos(latitude * math.pi / 180.0);

    // Local metres of (lat, lon) relative to the query point as origin.
    double ex(double lon) => (lon - longitude) * mLon;
    double ny(double lat) => (lat - latitude) * _metersPerDegLat;

    var bestCrossTrack = double.infinity;
    var bestIndex = 0;
    var bestAlongSegment = 0.0; // metres from segment start to the projection

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final ax = ex(a.longitude), ay = ny(a.latitude);
      final bx = ex(b.longitude), by = ny(b.latitude);
      final dx = bx - ax, dy = by - ay;
      final segLenSq = dx * dx + dy * dy;

      double t;
      if (segLenSq == 0) {
        t = 0;
      } else {
        // Projection parameter of the origin onto line A→B, clamped to segment.
        t = ((-ax) * dx + (-ay) * dy) / segLenSq;
        t = t.clamp(0.0, 1.0);
      }
      final fx = ax + t * dx, fy = ay + t * dy; // foot of perpendicular
      final crossTrack = math.sqrt(fx * fx + fy * fy);
      if (crossTrack < bestCrossTrack) {
        bestCrossTrack = crossTrack;
        bestIndex = i;
        bestAlongSegment = t * math.sqrt(segLenSq);
      }
    }

    final traveled =
        points[bestIndex].distanceFromStartMeters + bestAlongSegment;
    final remaining = (route.totalMeters - traveled).clamp(0.0, double.infinity);

    return RouteProgress(
      nearestSegmentIndex: bestIndex,
      crossTrackMeters: bestCrossTrack,
      traveledMeters: traveled,
      remainingMeters: remaining,
      offRoute: bestCrossTrack > offRouteThresholdMeters,
    );
  }
}
