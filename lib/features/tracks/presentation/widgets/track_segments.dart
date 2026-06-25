/// Pure helpers for drawing the ride track as speed-coloured segments.
///
/// The track is drawn as a continuous gray base line plus speed-coloured
/// segments on top. A segment only shows if it's long enough to render at the
/// current zoom; at the zoomed-out "fit the whole ride" view, a segment shorter
/// than a few pixels is invisible and the gray base shows through. Noisy GPS
/// speed produces lots of tiny single-step segments, so we merge any run shorter
/// than a fraction of the whole track into a neighbour — guaranteeing every
/// drawn segment is long enough to be visible (and capping the count as a
/// side-effect).
library;

/// A contiguous run of track points drawn in one colour. [start]/[end] are
/// inclusive indices; consecutive runs share their boundary index so the drawn
/// line is continuous.
class TrackRun {
  const TrackRun(this.start, this.end, this.kmh);

  final int start;
  final int end;

  /// Representative speed (km/h) for the run, used to pick its colour.
  final double kmh;
}

/// Splits a track into speed-coloured runs. [speedsKmh] has one value per point;
/// [segMeters] has the distance from point i to i+1 (length `points-1`). Runs
/// shorter than [minRunFraction] of the total track length are merged into the
/// neighbour with the closer speed, so no run is too short to render when the
/// whole ride is fitted on screen. `1/minRunFraction` also bounds the run count.
List<TrackRun> buildTrackRuns(
  List<double> speedsKmh,
  List<double> segMeters, {
  int buckets = 12,
  double minRunFraction = 1 / 40,
}) {
  final n = speedsKmh.length;
  if (n < 2) return const [];

  // Cumulative distance so a run's length is O(1).
  final cum = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    cum[i] = cum[i - 1] + (i - 1 < segMeters.length ? segMeters[i - 1] : 0.0);
  }
  final total = cum[n - 1];
  final minLen = total * minRunFraction;

  int bucketOf(double k) {
    final t = ((k - 10.0) / (60.0 - 10.0)).clamp(0.0, 1.0);
    return (t * buckets).round();
  }

  // Initial runs: split whenever the bucket changes.
  final starts = <int>[];
  final ends = <int>[];
  final sums = <double>[];
  final counts = <int>[];
  var st = 0;
  var cur = bucketOf(speedsKmh[0]);
  var sum = speedsKmh[0];
  var cnt = 1;
  for (var i = 1; i < n; i++) {
    final b = bucketOf(speedsKmh[i]);
    if (b != cur) {
      starts.add(st);
      ends.add(i); // shared boundary with the next run
      sums.add(sum);
      counts.add(cnt);
      st = i;
      cur = b;
      sum = speedsKmh[i];
      cnt = 1;
    } else {
      sum += speedsKmh[i];
      cnt++;
    }
  }
  starts.add(st);
  ends.add(n - 1);
  sums.add(sum);
  counts.add(cnt);

  double avg(int i) => sums[i] / counts[i];
  double len(int i) => cum[ends[i]] - cum[starts[i]];

  // Repeatedly fold the shortest run (below the threshold) into its
  // closer-speed neighbour. Each merge is contiguous, so the line stays whole.
  while (starts.length > 1) {
    var si = 0;
    var sl = len(0);
    for (var i = 1; i < starts.length; i++) {
      final l = len(i);
      if (l < sl) {
        sl = l;
        si = i;
      }
    }
    if (sl >= minLen) break;

    final int nb;
    if (si == 0) {
      nb = 1;
    } else if (si == starts.length - 1) {
      nb = si - 1;
    } else {
      nb = (avg(si - 1) - avg(si)).abs() <= (avg(si + 1) - avg(si)).abs()
          ? si - 1
          : si + 1;
    }
    final dst = si < nb ? si : nb;
    final src = si < nb ? nb : si;
    ends[dst] = ends[src];
    sums[dst] += sums[src];
    counts[dst] += counts[src];
    starts.removeAt(src);
    ends.removeAt(src);
    sums.removeAt(src);
    counts.removeAt(src);
  }

  return [
    for (var i = 0; i < starts.length; i++)
      TrackRun(starts[i], ends[i], avg(i)),
  ];
}
