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

/// Where to put the camera so the box [minLat]…[maxLat] × [minLon]…[maxLon]
/// fits a [width] × [height] (logical px) map with [paddingPx] to spare: its
/// centre, and the largest *whole* zoom level at which it fits (mapsforge
/// zooms in whole levels; rounding up would cut the ends off). Web Mercator
/// with [tileSize]-px tiles — latitude is stretched away from the equator
/// (≈1.5× at 48°N), so treating degrees of latitude like longitude zooms in
/// too far for a north–south ride. The centre is the Mercator midpoint, so
/// the box sits in the middle of the screen.
({double latitude, double longitude, int zoom}) fitMapView({
  required double minLat,
  required double maxLat,
  required double minLon,
  required double maxLon,
  required double width,
  required double height,
  double tileSize = 256,
  double paddingPx = 24,
  int minZoom = 3,
  int maxZoom = 17,
}) {
  double mercY(double lat) {
    final r = _toRadians(lat.clamp(-85.0511, 85.0511));
    return math.log(math.tan(math.pi / 4 + r / 2));
  }

  final y0 = mercY(math.min(minLat, maxLat));
  final y1 = mercY(math.max(minLat, maxLat));
  // Fractions of the world's width/height the box takes.
  final lonFrac = math.max((maxLon - minLon).abs(), 1e-6) / 360;
  final latFrac = math.max(y1 - y0, 1e-6) / (2 * math.pi);
  final w = math.max(width - 2 * paddingPx, 1.0);
  final h = math.max(height - 2 * paddingPx, 1.0);
  double log2(double x) => math.log(x) / math.ln2;
  // The world is tileSize·2^z px wide (and high) at zoom z.
  final z = math.min(log2(w / (tileSize * lonFrac)),
      log2(h / (tileSize * latFrac)));
  final yMid = (y0 + y1) / 2;
  final latMid = math.atan((math.exp(yMid) - math.exp(-yMid)) / 2) * 180 / math.pi;
  return (
    latitude: latMid,
    longitude: (minLon + maxLon) / 2,
    zoom: z.floor().clamp(minZoom, maxZoom),
  );
}
