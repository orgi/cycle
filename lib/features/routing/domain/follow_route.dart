import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/metrics/elevation.dart';
import '../../../core/utils/geo.dart';

/// One point along a followed route, tagged with the cumulative distance from
/// the route start to this point (metres), its height when the GPX has one
/// and, when the source GPX had timestamps, the elapsed time from the route
/// start. Pre-computing these makes
/// "remaining distance" and the ghost rider O(1)/O(n) lookups during navigation.
class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.distanceFromStartMeters,
    this.elevationMeters,
    this.timeFromStart,
  });

  final double latitude;
  final double longitude;
  final double distanceFromStartMeters;

  /// Height above sea level (the GPX `<ele>`), when the route has one.
  final double? elevationMeters;

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

  /// Identity of the route's geometry, the saved route's id: the same route
  /// imported twice, or on two phones, gets the same one, whatever its name or
  /// timestamps. Points are rounded to microdegrees (~0.1 m) so it comes out
  /// the same on every platform.
  late final String fingerprint = _fingerprint(points);

  static String _fingerprint(List<RoutePoint> points) {
    final b = StringBuffer();
    for (final p in points) {
      b
        ..write((p.latitude * 1e6).round())
        ..write(',')
        ..write((p.longitude * 1e6).round())
        ..write(';');
    }
    return sha256.convert(utf8.encode(b.toString())).toString().substring(0, 32);
  }

  /// Total route length in metres.
  double get totalMeters =>
      points.isEmpty ? 0 : points.last.distanceFromStartMeters;

  /// Whether every point carries a timestamp (so a ghost can replay the GPX's
  /// own pace rather than a constant target speed).
  bool get isTimed =>
      points.length >= 2 && points.every((p) => p.timeFromStart != null);

  /// Total recorded duration, when [isTimed].
  Duration? get totalDuration => isTimed ? points.last.timeFromStart : null;

  /// The route's height over its distance (points without one left out).
  late final ElevationProfile elevationProfile = ElevationProfile([
    for (final p in points)
      if (p.elevationMeters != null)
        ProfilePoint(p.distanceFromStartMeters, p.elevationMeters!),
  ]);

  /// Whether the route has heights (planned routes from Komoot & co. do).
  bool get hasElevation => !elevationProfile.isEmpty;

  /// Climb from the start up to each [elevationProfile] point. A planned
  /// route's heights come from a terrain model, not a jittery GPS, so a small
  /// threshold is enough.
  late final List<double> _climbTo = () {
    final counter = ClimbCounter(thresholdMeters: 2);
    return [
      for (final p in elevationProfile.points)
        (counter..add(p.elevationMeters)).climbMeters,
    ];
  }();

  /// The route's total climb.
  double get totalClimbMeters => _climbTo.isEmpty ? 0 : _climbTo.last;

  /// The climb still ahead after [traveledMeters] along the route.
  double climbRemainingMeters(double traveledMeters) =>
      (totalClimbMeters - _interpolate(traveledMeters, (i) => _climbTo[i]))
          .clamp(0.0, double.infinity);

  /// The route's height at [distanceMeters] along it, or null without heights.
  double? elevationAt(double distanceMeters) => hasElevation
      ? _interpolate(
          distanceMeters, (i) => elevationProfile.points[i].elevationMeters)
      : null;

  /// [value] of the [elevationProfile] points, interpolated at [distance].
  double _interpolate(double distance, double Function(int i) value) {
    final pts = elevationProfile.points;
    if (pts.isEmpty) return 0;
    if (distance <= pts.first.distanceMeters) return value(0);
    if (distance >= pts.last.distanceMeters) return value(pts.length - 1);
    var lo = 0, hi = pts.length - 1; // pts[lo] <= distance < pts[hi]
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (pts[mid].distanceMeters <= distance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = pts[hi].distanceMeters - pts[lo].distanceMeters;
    final t = span <= 0 ? 0.0 : (distance - pts[lo].distanceMeters) / span;
    return value(lo) + (value(hi) - value(lo)) * t;
  }

  /// Builds a route from raw `(lat, lon)` coordinates (no timing).
  factory FollowRoute.fromCoordinates(
    String name,
    Iterable<(double lat, double lon)> coordinates,
  ) =>
      FollowRoute.fromGpxPoints(
        name,
        [
          for (final (lat, lon) in coordinates)
            (lat: lat, lon: lon, ele: null, time: null),
        ],
      );

  /// Builds a route from GPX points (optionally with heights and timestamps),
  /// computing
  /// cumulative distances + per-point elapsed time and collapsing consecutive
  /// duplicate points (which would create zero-length segments). Throws
  /// [FormatException] if fewer than two distinct points remain.
  factory FollowRoute.fromGpxPoints(
    String name,
    Iterable<({double lat, double lon, double? ele, DateTime? time})> raw,
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
        elevationMeters: p.ele,
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
