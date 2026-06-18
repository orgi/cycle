import 'package:gpx/gpx.dart';

import 'follow_route.dart';

/// Parses a GPX document into a [FollowRoute].
///
/// Accepts the three common ways a route shows up in a GPX file, in order of
/// preference: track points (`<trk><trkseg><trkpt>`), route points
/// (`<rte><rtept>`), then bare waypoints (`<wpt>`). The name comes from the
/// track/route/metadata `<name>`, falling back to [fallbackName].
///
/// Throws [FormatException] if the document has fewer than two usable points.
FollowRoute parseGpxRoute(String xml, {String fallbackName = 'Route'}) {
  final Gpx gpx;
  try {
    gpx = GpxReader().fromString(xml);
  } on Object catch (e) {
    throw FormatException('not a valid GPX file: $e');
  }

  final coords = <(double, double)>[];
  String? name;

  for (final trk in gpx.trks) {
    name ??= _nonEmpty(trk.name);
    for (final seg in trk.trksegs) {
      for (final p in seg.trkpts) {
        coords.add((p.lat ?? 0, p.lon ?? 0));
      }
    }
  }
  if (coords.isEmpty) {
    for (final rte in gpx.rtes) {
      name ??= _nonEmpty(rte.name);
      for (final p in rte.rtepts) {
        coords.add((p.lat ?? 0, p.lon ?? 0));
      }
    }
  }
  if (coords.isEmpty) {
    for (final p in gpx.wpts) {
      coords.add((p.lat ?? 0, p.lon ?? 0));
    }
  }

  name ??= _nonEmpty(gpx.metadata?.name);
  return FollowRoute.fromCoordinates(name ?? fallbackName, coords);
}

String? _nonEmpty(String? s) => (s != null && s.trim().isNotEmpty) ? s : null;
