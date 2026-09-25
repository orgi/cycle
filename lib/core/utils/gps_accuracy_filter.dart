import '../models/geo_sample.dart';

/// Whether [sample] is accurate enough to keep, live, at the source.
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
