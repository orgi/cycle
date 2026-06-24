/// Pure helpers for drawing the ride track as speed-coloured segments.
///
/// The map's marker datastore re-initialises every marker sequentially when the
/// view changes; too many markers (a long ride can produce hundreds of colour
/// changes) and the batch can be cut short, and a degenerate (zero-length)
/// segment can even make one re-init throw. Either way later segments stop
/// painting and the gray base line shows through. So we (a) cap the number of
/// runs and (b) only ever build runs spanning ≥ 2 distinct points.
library;

/// A contiguous run of track points that should be drawn in one colour.
/// [start]/[end] are inclusive indices into the (de-duplicated) point list;
/// consecutive runs share their boundary index so the drawn line is continuous.
class TrackRun {
  const TrackRun(this.start, this.end, this.kmh);

  final int start;
  final int end;

  /// Representative speed (km/h) for the run, used to pick its colour.
  final double kmh;
}

/// Splits [speedsKmh] (one value per point) into at most [maxRuns] colour runs.
/// Adjacent points in the same speed bucket merge into one run; if there are
/// still too many runs, the least-contrasting neighbouring runs are merged
/// first so the overall colour gradient is preserved. Returns runs that each
/// span at least two points (`end > start`).
List<TrackRun> buildTrackRuns(
  List<double> speedsKmh, {
  int buckets = 12,
  int maxRuns = 48,
}) {
  final n = speedsKmh.length;
  if (n < 2) return const [];

  int bucketOf(double k) {
    final t = ((k - 10.0) / (60.0 - 10.0)).clamp(0.0, 1.0);
    return (t * buckets).round();
  }

  // Build initial runs, splitting whenever the bucket changes.
  final starts = <int>[];
  final ends = <int>[];
  final sums = <double>[];
  final counts = <int>[];
  var startIdx = 0;
  var curBucket = bucketOf(speedsKmh[0]);
  var sum = speedsKmh[0];
  var count = 1;
  for (var i = 1; i < n; i++) {
    final b = bucketOf(speedsKmh[i]);
    if (b != curBucket) {
      starts.add(startIdx);
      ends.add(i); // shared boundary with the next run
      sums.add(sum);
      counts.add(count);
      startIdx = i;
      curBucket = b;
      sum = speedsKmh[i];
      count = 1;
    } else {
      sum += speedsKmh[i];
      count++;
    }
  }
  starts.add(startIdx);
  ends.add(n - 1);
  sums.add(sum);
  counts.add(count);

  // A trailing single-point run (last point flipped bucket) is degenerate —
  // fold it into the previous run.
  if (starts.length > 1 && ends.last == starts.last) {
    ends[ends.length - 2] = ends.last;
    sums[sums.length - 2] += sums.last;
    counts[counts.length - 2] += counts.last;
    starts.removeLast();
    ends.removeLast();
    sums.removeLast();
    counts.removeLast();
  }

  // Cap the run count by repeatedly merging the neighbouring pair whose average
  // speeds are closest (least visible seam).
  while (starts.length > maxRuns) {
    var bestI = 0;
    var bestDiff = double.infinity;
    for (var i = 0; i < starts.length - 1; i++) {
      final d = (sums[i] / counts[i] - sums[i + 1] / counts[i + 1]).abs();
      if (d < bestDiff) {
        bestDiff = d;
        bestI = i;
      }
    }
    ends[bestI] = ends[bestI + 1];
    sums[bestI] += sums[bestI + 1];
    counts[bestI] += counts[bestI + 1];
    starts.removeAt(bestI + 1);
    ends.removeAt(bestI + 1);
    sums.removeAt(bestI + 1);
    counts.removeAt(bestI + 1);
  }

  return [
    for (var i = 0; i < starts.length; i++)
      TrackRun(starts[i], ends[i], sums[i] / counts[i]),
  ];
}
