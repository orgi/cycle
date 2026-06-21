import 'dart:math' as math;

/// Great-circle distance in metres between two WGS84 coordinates.
///
/// Pure Dart (no plugin) so it is unit-testable without a platform channel.
/// Uses the haversine formula; accurate to well within GPS error over the
/// short legs between consecutive track points.
double haversineMeters(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadius = 6371000.0; // metres
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

/// Initial compass bearing in degrees (0 = north, 90 = east, clockwise) from
/// point 1 to point 2. Used to orient direction arrows along a track/route.
double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  final dLon = _toRadians(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(_toRadians(lat2));
  final x = math.cos(_toRadians(lat1)) * math.sin(_toRadians(lat2)) -
      math.sin(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * math.cos(dLon);
  final brng = math.atan2(y, x) * 180.0 / math.pi;
  return (brng + 360.0) % 360.0;
}

double _toRadians(double degrees) => degrees * math.pi / 180.0;
