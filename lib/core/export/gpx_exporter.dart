import 'package:gpx/gpx.dart';

import '../db/database.dart';

/// Serialises a recorded ride to a GPX 1.1 string. Heart rate / cadence / power
/// are written as track-point extensions (the de-facto Garmin convention).
class GpxExporter {
  GpxExporter._();

  static String export(Track track, List<TrackPoint> points) {
    final gpx = Gpx()
      ..creator = 'Cycle'
      ..metadata = (Metadata()
        ..name = track.name
        ..time = track.startedAt)
      ..trks = [
        Trk(
          name: track.name,
          trksegs: [
            Trkseg(
              trkpts: [
                for (final p in points)
                  Wpt(
                    lat: p.latitude,
                    lon: p.longitude,
                    ele: p.altitude,
                    time: p.time,
                    extensions: _extensions(p),
                  ),
              ],
            ),
          ],
        ),
      ];
    return GpxWriter().asString(gpx, pretty: true);
  }

  static Map<String, Object> _extensions(TrackPoint p) => {
        if (p.heartRate != null) 'heartrate': p.heartRate!,
        if (p.cadenceRpm != null) 'cadence': p.cadenceRpm!.round(),
        if (p.power != null) 'power': p.power!,
      };
}
