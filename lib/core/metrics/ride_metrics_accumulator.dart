import 'dart:math' as math;

import '../models/geo_sample.dart';
import '../models/ride_metrics.dart';
import '../utils/geo.dart';

/// Folds a sequence of [GeoSample]s into running [RideMetrics].
///
/// Pure Dart and stateful-by-design: feed it each new sample with [add] and it
/// returns the updated snapshot. Lives outside the Riverpod/UI layers so the
/// distance/speed maths can be unit-tested in isolation.
class RideMetricsAccumulator {
  RideMetricsAccumulator({
    this.autoPauseEnabled = false,
    this.autoPauseThresholdMps = 5.0 / 3.6, // 5 km/h
  });

  /// When enabled, samples below [autoPauseThresholdMps] don't add to moving
  /// time or distance (so red lights / breaks are excluded from time + average).
  bool autoPauseEnabled;
  double autoPauseThresholdMps;

  GeoSample? _last;
  DateTime? _startTime;
  double _distanceMeters = 0;
  double _maxSpeedMps = 0;
  int _movingMillis = 0;
  bool _paused = false;

  /// Whether the ride is currently auto-paused (last sample below threshold).
  bool get paused => _paused;

  // Distance is accumulated via streaming path simplification (an
  // incremental, buffered Douglas-Peucker-style simplifier), not by summing
  // every raw leg and not by integrating reported speed — see the doc
  // comment on [_feedSimplifier] for why both of those were tried and
  // reverted.
  GeoSample? _anchor; // last committed point
  final List<GeoSample> _pending = []; // points since _anchor, not yet committed
  double _committedMeters = 0;

  /// Points within this perpendicular distance of the anchor→newest candidate
  /// line are treated as noise on an otherwise-straight bit of path and
  /// folded in without adding their own zig-zag length. Swept 3-10 m against
  /// two real rides with independently-known (Komoot-planned) distances —
  /// 27.20 km and 40.80 km, ~1000-1600 recorded points each: 5 m gave the
  /// best balance, landing both within ~0.75% (-0.74% / +0.64%). Also robust
  /// against adversarial synthetic jitter (alternating ±2.5 m still resolves
  /// cleanly; real GPS jitter is typically 1-2 m).
  static const double _simplifyEpsilonMeters = 5.0;

  /// A pending point this far beyond either end of the anchor→newest line —
  /// back the way the rider came — means the ride turned back there: a dead
  /// end, an out-and-back, a missed turn. Every point of such a ride lies on
  /// one line, so [_simplifyEpsilonMeters] alone never broke the run and the
  /// way out and back counted as the few metres between the anchor and the
  /// newest fix (1.5 km out and back, nearly straight, came to 450 m).
  /// Not 5 m: on the A33's rides of June/July 2026, along-road GPS noise
  /// then added 3-4% (counted as tiny turn-backs); from 30 m none of the
  /// ~830 rides in a full backup changed except those with real turn-backs
  /// (up to +1.75 km), which keep their full length at any value up to 50 m.
  static const double _turnBackMeters = 30.0;

  RideMetrics add(GeoSample sample) {
    _startTime ??= sample.time;

    var current = _gpsSpeedOrZero(sample);
    final last = _last;
    var leg = 0.0;
    var dtSeconds = 0.0;
    if (last != null) {
      leg = haversineMeters(
        last.latitude,
        last.longitude,
        sample.latitude,
        sample.longitude,
      );
      dtSeconds = sample.time.difference(last.time).inMilliseconds / 1000.0;
      // Prefer the GPS-reported speed; fall back to distance/time.
      if (sample.speedMps == null || sample.speedMps! < 0) {
        current = dtSeconds > 0 ? leg / dtSeconds : 0.0;
      }
    }

    if (current > _maxSpeedMps) {
      _maxSpeedMps = current;
    }

    // Auto-pause: below the threshold, don't grow moving time or distance, so a
    // stop at a light / a break is excluded from the timer and the average.
    // (max speed still tracks the true peak above.) Samples while paused also
    // aren't fed to the simplifier below, so GPS jitter while genuinely
    // stationary can't leak in as phantom distance either.
    _paused = autoPauseEnabled && current < autoPauseThresholdMps;
    // Seed the simplifier on every unpaused sample — including the very first
    // one (of the ride, or after a resume/reset) — not just once `last` exists.
    // Skipping the seed until the *second* unpaused sample would silently
    // drop the real leg between them once it finally runs: `_feedSimplifier`
    // would treat that second sample as if it were the first point ever
    // (setting the anchor with no distance added), rather than measuring the
    // genuine gap from the true first point.
    if (!_paused) {
      _feedSimplifier(sample);
    }
    if (last != null && !_paused) {
      _movingMillis += (dtSeconds * 1000).round();
    }
    _last = sample;

    final elapsed = Duration(milliseconds: _movingMillis);
    final elapsedSeconds = _movingMillis / 1000.0;
    final avg = elapsedSeconds > 0 ? _distanceMeters / elapsedSeconds : 0.0;

    return RideMetrics(
      distanceMeters: _distanceMeters,
      currentSpeedMps: current,
      avgSpeedMps: avg,
      maxSpeedMps: _maxSpeedMps,
      elapsed: elapsed,
      paused: _paused,
    );
  }

  /// Streaming, incremental Douglas-Peucker-style path simplification: every
  /// point since [_anchor] is kept in [_pending]. When a new point arrives,
  /// *all* of the previously-pending points are re-tested against the line
  /// from [_anchor] to this new point — if every one of them still lies
  /// within [_simplifyEpsilonMeters] of that (updated) line, they're all still
  /// explained as noise on one straight bit of path, so nothing is committed
  /// yet. The moment one of them doesn't, the path actually turned there: the
  /// line up to the *last point that was still valid* is committed as real
  /// distance, and a new anchor/pending run starts from there. A point more
  /// than [_turnBackMeters] beyond either end of the line is where the path
  /// turned back on itself: the way to that point is committed, and the
  /// points since — already on the way back — start the next run.
  ///
  /// Testing against the anchor→newest line each step (not just anchor→prior
  /// point) is what makes this robust: a naive two-point "sleeve" that only
  /// ever compares against the *immediately preceding* candidate point lets a
  /// single noisy point corrupt the reference line for the very next
  /// comparison ("noise chasing noise") — verified to overcount by 60%+
  /// against synthetic alternating jitter of just 1.5-2m at this epsilon.
  /// Re-testing the whole pending run against the stable anchor avoids that:
  /// validated clean up to ~2.5m of synthetic alternating jitter at
  /// [_simplifyEpsilonMeters] = 5m, the epsilon tuned against real rides
  /// below.
  ///
  /// Two other approaches were tried and reverted before this:
  /// - **Summing every raw leg** (haversine between every consecutive fix)
  ///   overcounts distance by several percent purely from GPS positional
  ///   jitter — a few metres of noise on *every* fix, continuously, not just
  ///   spikes (the "coastline paradox": the more finely/noisily you sample a
  ///   wiggly line, the longer it measures, even though the real path hasn't
  ///   changed).
  /// - **Integrating the GPS chip's reported (Doppler) speed** over time
  ///   avoids that specific bias but trades it for a different, *larger* one
  ///   in the other direction — field data (two real rides against known
  ///   Komoot-planned route distances) showed it undercounting by 4-6%, and
  ///   every geometric alternative tried (raw sum, fixed-time-window
  ///   displacement, batch Douglas-Peucker simplification) came out *higher*
  ///   than that, not lower, ruling out "just needs more smoothing" as the
  ///   explanation — the reported speed itself isn't a reliable basis for
  ///   distance here.
  ///
  /// This is the streaming (single-pass, small bounded extra state) form of
  /// the same simplification a batch Douglas-Peucker would produce, so it can
  /// drive the live distance display incrementally instead of only a
  /// post-hoc recompute — the batch algorithm needs the whole path to
  /// recursively find the worst-deviating point, which live recording
  /// doesn't have yet.
  void _feedSimplifier(GeoSample sample) {
    final anchor = _anchor;
    if (anchor == null) {
      _anchor = sample;
      _distanceMeters = _committedMeters;
      return;
    }
    if (_pending.isEmpty) {
      _pending.add(sample);
      _distanceMeters = _committedMeters + _legMeters(anchor, sample);
      return;
    }
    var sideways = false;
    var turnedAt = -1;
    var farthest = _turnBackMeters;
    for (var i = 0; i < _pending.length; i++) {
      final (:across, :beyond) = _offsetMeters(_pending[i], anchor, sample);
      if (across > _simplifyEpsilonMeters) sideways = true;
      if (beyond > farthest) {
        farthest = beyond;
        turnedAt = i;
      }
    }
    if (turnedAt >= 0) {
      // Commit the way to the turning point; the points after it are on the
      // way back and start the next run.
      final turn = _pending[turnedAt];
      _committedMeters += _legMeters(anchor, turn);
      _anchor = turn;
      final since = _pending.sublist(turnedAt + 1);
      _pending
        ..clear()
        ..addAll(since)
        ..add(sample);
    } else if (sideways) {
      // Commit up to the last point that was still a valid simplification,
      // and start a fresh run from there.
      final stable = _pending.last;
      _committedMeters += _legMeters(anchor, stable);
      _anchor = stable;
      _pending
        ..clear()
        ..add(sample);
    } else {
      _pending.add(sample);
    }
    _distanceMeters = _committedMeters + _legMeters(_anchor!, _pending.last);
  }

  static double _legMeters(GeoSample a, GeoSample b) =>
      haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Where [p] lies relative to the line from [a] to [b], in metres:
  /// [across] it (perpendicular distance to the infinite line through them)
  /// and [beyond] either end along it (0 between them). Projects to a flat
  /// local plane (equirectangular, centred at [a]) — accurate for the short
  /// spans between consecutive GPS fixes this is used on.
  static ({double across, double beyond}) _offsetMeters(
    GeoSample p,
    GeoSample a,
    GeoSample b,
  ) {
    const earthRadius = 6371000.0;
    final lat0 = a.latitude * math.pi / 180.0;
    double x(double lon) => lon * math.pi / 180.0 * earthRadius * math.cos(lat0);
    double y(double lat) => lat * math.pi / 180.0 * earthRadius;

    final ax = x(a.longitude), ay = y(a.latitude);
    final bx = x(b.longitude), by = y(b.latitude);
    final px = x(p.longitude), py = y(p.latitude);

    final dx = bx - ax, dy = by - ay;
    if (dx == 0 && dy == 0) {
      return (
        across: math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay)),
        beyond: 0.0,
      );
    }
    final length = math.sqrt(dx * dx + dy * dy);
    final along = ((px - ax) * dx + (py - ay) * dy) / length;
    return (
      across: ((px - ax) * dy - (py - ay) * dx).abs() / length,
      beyond: along < 0 ? -along : math.max(0.0, along - length),
    );
  }

  /// Resets all running totals so the accumulator can be reused for a new ride.
  void reset() {
    _last = null;
    _startTime = null;
    _distanceMeters = 0;
    _maxSpeedMps = 0;
    _movingMillis = 0;
    _paused = false;
    _anchor = null;
    _pending.clear();
    _committedMeters = 0;
  }

  /// Resumes an interrupted ride: seed the running totals from the points that
  /// were already recorded, and start a **fresh leg** (`_last = null`) so the
  /// dead-time gap while the app was gone isn't counted as distance or time.
  void resumeWith({
    required double distanceMeters,
    required int movingMillis,
    required double maxSpeedMps,
  }) {
    _distanceMeters = distanceMeters;
    _committedMeters = distanceMeters;
    _movingMillis = movingMillis;
    _maxSpeedMps = maxSpeedMps;
    _last = null;
    _startTime = null;
    _paused = false;
    _anchor = null;
    _pending.clear();
  }

  double _gpsSpeedOrZero(GeoSample s) =>
      (s.speedMps != null && s.speedMps! >= 0) ? s.speedMps! : 0.0;
}
