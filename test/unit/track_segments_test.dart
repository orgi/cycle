import 'package:cycle/features/tracks/presentation/widgets/track_segments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns empty for fewer than two points', () {
    expect(buildTrackRuns([]), isEmpty);
    expect(buildTrackRuns([25]), isEmpty);
  });

  test('one run for a constant speed', () {
    final runs = buildTrackRuns([25, 25, 25, 25]);
    expect(runs, hasLength(1));
    expect(runs.single.start, 0);
    expect(runs.single.end, 3);
  });

  test('consecutive runs share their boundary index (continuous line)', () {
    final runs = buildTrackRuns([10, 10, 60, 60]);
    expect(runs.length, greaterThanOrEqualTo(2));
    for (var i = 0; i < runs.length - 1; i++) {
      expect(runs[i].end, runs[i + 1].start,
          reason: 'run $i must end where run ${i + 1} starts');
    }
    // Covers the whole track end-to-end.
    expect(runs.first.start, 0);
    expect(runs.last.end, 3);
  });

  test('every run spans at least two points (no degenerate segments)', () {
    // A trailing point that flips bucket would otherwise make a 1-point run.
    final runs = buildTrackRuns([20, 20, 20, 60]);
    for (final r in runs) {
      expect(r.end, greaterThan(r.start));
    }
    expect(runs.last.end, 3);
  });

  test('caps the number of runs by merging closest neighbours', () {
    // Alternating speeds would otherwise yield ~100 runs.
    final speeds = [for (var i = 0; i < 100; i++) i.isEven ? 12.0 : 58.0];
    final runs = buildTrackRuns(speeds, maxRuns: 10);
    expect(runs.length, lessThanOrEqualTo(10));
    // Still continuous and covering the full track.
    expect(runs.first.start, 0);
    expect(runs.last.end, 99);
    for (var i = 0; i < runs.length - 1; i++) {
      expect(runs[i].end, runs[i + 1].start);
    }
  });

  test('representative speed sits within the run', () {
    final runs = buildTrackRuns([30, 30, 30]);
    expect(runs.single.kmh, closeTo(30, 1e-9));
  });
}
