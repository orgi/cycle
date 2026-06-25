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
}
