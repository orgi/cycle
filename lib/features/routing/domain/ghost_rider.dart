import 'follow_route.dart';

/// The ghost rider's position at a moment in time.
class GhostPosition {
  const GhostPosition({
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });

  final double latitude;
  final double longitude;

  /// Distance the ghost has covered along the route (metres).
  final double distanceMeters;
}

/// A virtual rider that moves along a [FollowRoute] so you can race it.
///
/// If the route is [FollowRoute.isTimed] (the imported GPX had timestamps) the
/// ghost replays that exact pace; otherwise it advances at a constant target
/// speed. Pure Dart so the pacing maths is unit-tested.
class GhostRider {
  GhostRider(this.route, {this.targetSpeedMps = defaultTargetSpeedMps});

  final FollowRoute route;

  /// Pace used when the route is not timed.
  final double targetSpeedMps;

  /// 25 km/h — a reasonable default for an untimed route. (Could be exposed as
  /// a setting later.)
  static const double defaultTargetSpeedMps = 25 / 3.6;

  /// Distance the ghost has covered at [elapsed] (clamped to the route length).
  double distanceAt(Duration elapsed) {
    if (route.isTimed) return _timedDistanceAt(elapsed);
    final seconds = elapsed.inMilliseconds / 1000.0;
    return (targetSpeedMps * seconds).clamp(0.0, route.totalMeters);
  }

  /// Ghost position (lat/lon + distance) at [elapsed].
  GhostPosition positionAt(Duration elapsed) {
    final distance = distanceAt(elapsed);
    final (lat, lon) = _pointAtDistance(distance);
    return GhostPosition(
        latitude: lat, longitude: lon, distanceMeters: distance);
  }

  double _timedDistanceAt(Duration elapsed) {
    final pts = route.points;
    if (elapsed <= pts.first.timeFromStart!) return 0;
    if (elapsed >= pts.last.timeFromStart!) return route.totalMeters;
    for (var i = 0; i < pts.length - 1; i++) {
      final t0 = pts[i].timeFromStart!;
      final t1 = pts[i + 1].timeFromStart!;
      if (elapsed >= t0 && elapsed <= t1) {
        final span = (t1 - t0).inMilliseconds;
        final frac =
            span == 0 ? 0.0 : (elapsed - t0).inMilliseconds / span;
        return pts[i].distanceFromStartMeters +
            frac *
                (pts[i + 1].distanceFromStartMeters -
                    pts[i].distanceFromStartMeters);
      }
    }
    return route.totalMeters;
  }

  /// Interpolated lat/lon at a distance along the route.
  (double, double) _pointAtDistance(double distance) {
    final pts = route.points;
    if (distance <= 0) return (pts.first.latitude, pts.first.longitude);
    if (distance >= route.totalMeters) {
      return (pts.last.latitude, pts.last.longitude);
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final d0 = pts[i].distanceFromStartMeters;
      final d1 = pts[i + 1].distanceFromStartMeters;
      if (distance >= d0 && distance <= d1) {
        final span = d1 - d0;
        final frac = span == 0 ? 0.0 : (distance - d0) / span;
        return (
          pts[i].latitude + frac * (pts[i + 1].latitude - pts[i].latitude),
          pts[i].longitude + frac * (pts[i + 1].longitude - pts[i].longitude),
        );
      }
    }
    return (pts.last.latitude, pts.last.longitude);
  }
}
