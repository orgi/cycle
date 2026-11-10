import 'package:cycle/features/tracks/presentation/widgets/speed_color.dart';
import 'package:cycle/core/db/database.dart';
import 'package:cycle/features/tracks/presentation/widgets/track_segments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Uniform step distances for n points (n-1 segments).
  List<double> uniform(int n, [double m = 100]) =>
      [for (var i = 0; i < n - 1; i++) m];

  double runLen(TrackRun r, List<double> seg) {
    var s = 0.0;
    for (var i = r.start; i < r.end; i++) {
      s += seg[i];
    }
    return s;
  }

  test('returns empty for fewer than two points', () {
    expect(buildTrackRuns([], []), isEmpty);
    expect(buildTrackRuns([25], []), isEmpty);
  });

  test('one run for a constant speed', () {
    final runs = buildTrackRuns([25, 25, 25, 25], uniform(4));
    expect(runs, hasLength(1));
    expect(runs.single.start, 0);
    expect(runs.single.end, 3);
  });

  test('consecutive runs share their boundary index (continuous line)', () {
    final speeds = [for (var i = 0; i < 30; i++) 12.0, for (var i = 0; i < 30; i++) 58.0];
    final runs = buildTrackRuns(speeds, uniform(speeds.length));
    expect(runs.length, greaterThanOrEqualTo(2));
    for (var i = 0; i < runs.length - 1; i++) {
      expect(runs[i].end, runs[i + 1].start);
    }
    expect(runs.first.start, 0);
    expect(runs.last.end, speeds.length - 1);
  });

  test('merges a short spike so it does not become its own tiny run', () {
    // 30 slow, a 1-point fast spike, 30 slow. The 100 m spike is far below the
    // length threshold (6000 m / 40 = 150 m) so it must be folded in.
    final speeds = [
      for (var i = 0; i < 30; i++) 15.0,
      58.0,
      for (var i = 0; i < 30; i++) 15.0,
    ];
    final seg = uniform(speeds.length);
    final runs = buildTrackRuns(speeds, seg);
    final total = seg.fold<double>(0, (a, b) => a + b);

    // Continuous + full coverage.
    expect(runs.first.start, 0);
    expect(runs.last.end, speeds.length - 1);
    for (var i = 0; i < runs.length - 1; i++) {
      expect(runs[i].end, runs[i + 1].start);
    }
    // No run is shorter than the threshold (unless everything merged to one).
    if (runs.length > 1) {
      for (final r in runs) {
        expect(runLen(r, seg), greaterThanOrEqualTo(total / 40 - 1e-6));
      }
    }
  });

  test('the length fraction bounds the run count', () {
    final speeds = [for (var i = 0; i < 200; i++) i.isEven ? 12.0 : 58.0];
    final runs = buildTrackRuns(speeds, uniform(200), minRunFraction: 1 / 10);
    expect(runs.length, lessThanOrEqualTo(10));
    expect(runs.first.start, 0);
    expect(runs.last.end, 199);
    for (var i = 0; i < runs.length - 1; i++) {
      expect(runs[i].end, runs[i + 1].start);
    }
  });

  test('representative speed sits within the run', () {
    final runs = buildTrackRuns([30, 30, 30], uniform(3));
    expect(runs.single.kmh, closeTo(30, 1e-9));
  });

  group('RideSpeedTrack', () {
    final t0 = DateTime(2026, 6, 1, 8);
    TrackPoint pt(int i, double lat, double? kmh) => TrackPoint(
          id: i,
          trackId: 1,
          time: t0.add(Duration(seconds: 10 * i)),
          latitude: lat,
          longitude: 7.0,
          speedMps: kmh == null ? null : kmh / 3.6,
        );

    test('drops repeated fixes, measures the distance, colours by speed', () {
      // 1 km slow (8 km/h), then 1 km fast (55 km/h); a stop repeats a fix.
      final pts = [
        for (var i = 0; i <= 10; i++) pt(i, 43 + i * 0.0009, 8),
        pt(11, 43 + 10 * 0.0009, 8), // stopped: the same fix again
        for (var i = 1; i <= 10; i++) pt(11 + i, 43.009 + i * 0.0009, 55),
      ];
      final track = RideSpeedTrack.of(pts);
      expect(track.latitudes, hasLength(21));
      expect(track.meters.first, 0);
      expect(track.meters.last, closeTo(20 * 100.1, 5));

      final bands = track.bands;
      expect(bands.first.fromMeters, 0);
      expect(bands.last.toMeters, track.meters.last);
      for (var i = 1; i < bands.length; i++) {
        expect(bands[i].fromMeters, bands[i - 1].toMeters); // no gaps
      }
      // Slow red at the start, fast violet at the end — the map's colours.
      expect(bands.first.argb, speedColorArgb(track.runs.first.kmh));
      expect(track.runs.first.kmh, lessThan(15));
      expect(track.runs.last.kmh, greaterThan(50));
      expect(bands.last.argb, speedColorArgb(track.runs.last.kmh));
    });

    test('without recorded speeds, the speed comes from distance and time',
        () {
      // ~100 m every 10 s: 36 km/h.
      final track = RideSpeedTrack.of(
          [for (var i = 0; i < 5; i++) pt(i, 43 + i * 0.0009, null)]);
      // The first point has nothing before it (0 km/h); the rest ~36.
      expect(track.runs.last.kmh, closeTo(36, 1.5));
      expect(track.bands.last.argb, speedColorArgb(track.runs.last.kmh));
    });

    test('nothing to colour with fewer than two places', () {
      expect(RideSpeedTrack.of(const []).bands, isEmpty);
      expect(RideSpeedTrack.of([pt(0, 43, 10), pt(1, 43, 10)]).bands, isEmpty);
    });
  });
}
