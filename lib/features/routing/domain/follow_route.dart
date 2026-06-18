import '../../../core/utils/geo.dart';

/// One point along a followed route, tagged with the cumulative distance from
/// the route start to this point (metres). Pre-computing the cumulative
/// distance makes "remaining distance" an O(1) lookup during navigation.
class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.distanceFromStartMeters,
  });

  final double latitude;
  final double longitude;
  final double distanceFromStartMeters;
}

/// A route the rider follows, imported from a GPX file. Immutable; build it with
/// [FollowRoute.fromCoordinates], which drops repeated points and computes the
/// cumulative distance of every point.
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

  /// Builds a route from raw `(lat, lon)` coordinates, computing cumulative
  /// distances and collapsing consecutive duplicate points (which would create
  /// zero-length segments). Throws [FormatException] if fewer than two distinct
  /// points remain.
  factory FollowRoute.fromCoordinates(
    String name,
    Iterable<(double lat, double lon)> coordinates,
  ) {
    final points = <RoutePoint>[];
    double cumulative = 0;
    double? prevLat;
    double? prevLon;
    for (final (lat, lon) in coordinates) {
      if (prevLat != null && prevLon != null) {
        final segment = haversineMeters(prevLat, prevLon, lat, lon);
        if (segment < 0.01) continue; // skip duplicate / coincident point
        cumulative += segment;
      }
      points.add(RoutePoint(
        latitude: lat,
        longitude: lon,
        distanceFromStartMeters: cumulative,
      ));
      prevLat = lat;
      prevLon = lon;
    }
    if (points.length < 2) {
      throw const FormatException('route needs at least two distinct points');
    }
    return FollowRoute(name: name, points: points);
  }
}
