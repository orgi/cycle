import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/export/gpx_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpx/gpx.dart';

void main() {
  test('exports a track to valid GPX that round-trips', () {
    final start = DateTime.utc(2026, 6, 1, 8);
    final track = Track(
      id: 1,
      name: 'Test ride',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 30)),
      distanceMeters: 100,
      durationSeconds: 1800,
      avgSpeedMps: 5,
      maxSpeedMps: 10,
    );
    final points = [
      TrackPoint(
        id: 1,
        trackId: 1,
        time: start,
        latitude: 43.7384,
        longitude: 7.4246,
        altitude: 12,
        speedMps: 5,
        heartRate: 150,
        cadenceRpm: 90,
        power: 200,
      ),
      TrackPoint(
        id: 2,
        trackId: 1,
        time: start.add(const Duration(seconds: 10)),
        latitude: 43.7390,
        longitude: 7.4250,
        altitude: 13,
        speedMps: 6,
        heartRate: null,
        cadenceRpm: null,
        power: null,
      ),
    ];

    final xml = GpxExporter.export(track, points);
    expect(xml, contains('<gpx'));
    expect(xml, contains('Test ride'));

    final parsed = GpxReader().fromString(xml);
    final pts = parsed.trks.single.trksegs.single.trkpts;
    expect(pts.length, 2);
    expect(pts.first.lat, closeTo(43.7384, 1e-6));
    expect(pts.first.lon, closeTo(7.4246, 1e-6));
    expect(pts.first.ele, 12);
    expect(pts.first.extensions['heartrate'], '150');
  });
}
