import '../models/geo_sample.dart';

/// Whether [sample] is accurate enough to record.
///
/// Applied by the consumers that build a ride from fixes — `RideController`
/// (distance/time/max + saved points), the drawn track line and auto-start —
/// **not** at the location source: the location dot and the speed display get
/// every fix. Dropping inaccurate fixes at the source froze the dot whenever
/// the chip's estimate drifted past 10 m, which on the A33 happens mostly while
/// standing still (rides since the native GPS fix: nearly every gap in the
/// recorded fixes is at 0 km/h, 3-79 s long), so the dot didn't show where the
/// rider had stopped.
///
/// Replaces speed/distance-based outlier rejection (the old `GpsOutlierFilter`
/// live use, and `RideMetricsAccumulator`'s flat per-leg distance cap): field
/// data showed neither could reliably tell a genuine fix from a bad one — a
/// slow sustained drift (e.g. multipath under tree cover) never looks "too
/// fast" so it sailed through un-flagged, while a legitimate fast/sparse-fix
/// descent after a GPS gap of tens of seconds produced a large-but-plausible
/// leg that got its whole distance discarded. The GPS chip's own accuracy
/// estimate is a much more direct signal for "was this fix any good" than
/// inferring it from speed after the fact.
///
/// A fix with no reported accuracy (`null`) is kept — some providers don't
/// always report one, and rejecting on missing data would silently blackhole
/// fixes rather than fail toward keeping them.
bool isAccurateEnough(GeoSample sample, {double maxAccuracyMeters = 10.0}) {
  final accuracy = sample.accuracyMeters;
  return accuracy == null || accuracy <= maxAccuracyMeters;
}
