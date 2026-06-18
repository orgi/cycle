import '../../../core/utils/geo.dart';

/// One point along a followed route, tagged with the cumulative distance from
/// the route start to this point (metres) and, when the source GPX had
/// timestamps, the elapsed time from the route start. Pre-computing these makes
/// "remaining distance" and the ghost rider O(1)/O(n) lookups during navigation.
class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.distanceFromStartMeters,
    this.timeFromStart,
  });

  final double latitude;
  final double longitude;
  final double distanceFromStartMeters;

  /// Elapsed time from the route's first point, when the GPX carried per-point
  /// timestamps (null for a bare geometry route).
  final Duration? timeFromStart;
}

/// A route the rider follows, imported from a GPX file. Immutable; build it with
/// [FollowRoute.fromCoordinates] / [FollowRoute.fromGpxPoints], which drop
/// repeated points and compute the cumulative distance (and time) of every point.
class FollowRoute {
  FollowRoute({required this.name, required this.points})
      : assert(points.length >= 2, 'a route needs at least two points');

  /// Display name (from the GPX `<name>`, or a fallback).
  final String name;

  /// Ordered route points with cumulative distances.
  final List<RoutePoint> points;

  /// Total route length in metres.
  double get totalMeters =>
      points.isEmpty ? 0 : points.last.distanceFromStartMeters;

  /// Whether every point carries a timestamp (so a ghost can replay the GPX's
  /// own pace rather than a constant target speed).
  bool get isTimed =>
      points.length >= 2 && points.every((p) => p.timeFromStart != null);

  /// Total recorded duration, when [isTimed].
  Duration? get totalDuration => isTimed ? points.last.timeFromStart : null;

  /// Builds a route from raw `(lat, lon)` coordinates (no timing).
  factory FollowRoute.fromCoordinates(
    String name,
    Iterable<(double lat, double lon)> coordinates,
  ) =>
      FollowRoute.fromGpxPoints(
        name,
        [for (final (lat, lon) in coordinates) (lat: lat, lon: lon, time: null)],
      );

  /// Builds a route from GPX points (optionally timestamped), computing
  /// cumulative distances + per-point elapsed time and collapsing consecutive
  /// duplicate points (which would create zero-length segments). Throws
  /// [FormatException] if fewer than two distinct points remain.
  factory FollowRoute.fromGpxPoints(
    String name,
    Iterable<({double lat, double lon, DateTime? time})> raw,
  ) {
    final points = <RoutePoint>[];
    double cumulative = 0;
    double? prevLat;
    double? prevLon;
    DateTime? startTime;
    for (final p in raw) {
      if (prevLat != null && prevLon != null) {
        final segment = haversineMeters(prevLat, prevLon, p.lat, p.lon);
        if (segment < 0.01) continue; // skip duplicate / coincident point
        cumulative += segment;
      }
      startTime ??= p.time;
      points.add(RoutePoint(
        latitude: p.lat,
        longitude: p.lon,
        distanceFromStartMeters: cumulative,
        timeFromStart: (p.time != null && startTime != null)
            ? p.time!.difference(startTime)
            : null,
      ));
      prevLat = p.lat;
      prevLon = p.lon;
    }
    if (points.length < 2) {
      throw const FormatException('route needs at least two distinct points');
    }
    return FollowRoute(name: name, points: points);
  }
}
