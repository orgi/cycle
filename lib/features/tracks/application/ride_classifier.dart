import '../../../core/db/database.dart';

/// Criteria for finding old rides to bulk-classify (e.g. assign to a bike).
/// Every field is optional — null/false means "don't filter on this"; an
/// empty [RideClassifierFilter] matches every ride.
class RideClassifierFilter {
  const RideClassifierFilter({
    this.onlyUnassigned = false,
    this.requireCadenceData = false,
    this.requireHeartRateData = false,
    this.requirePowerData = false,
    this.minDistanceMeters,
    this.maxDistanceMeters,
    this.minAvgSpeedMps,
    this.maxAvgSpeedMps,
    this.minMaxSpeedMps,
    this.maxMaxSpeedMps,
    this.startedAfter,
    this.startedBefore,
  });

  final bool onlyUnassigned;

  // "Had a speed sensor" can't be reconstructed for rides recorded before
  // TrackPoints.speedFromSensor existed — the source of the speed value
  // wasn't stored, only the number — so it's deliberately not offered as a
  // classifier criterion. Cadence/HR/power presence *are* reliable, since
  // those columns themselves are the data (null vs. a value).
  final bool requireCadenceData;
  final bool requireHeartRateData;
  final bool requirePowerData;

  final double? minDistanceMeters;
  final double? maxDistanceMeters;
  final double? minAvgSpeedMps;
  final double? maxAvgSpeedMps;
  final double? minMaxSpeedMps;
  final double? maxMaxSpeedMps;

  /// Boundaries are taken as given (inclusive) — callers using a date-only
  /// picker should push [startedBefore] to the end of that day themselves.
  final DateTime? startedAfter;
  final DateTime? startedBefore;

  /// Whether any point-level (per-[TrackPoint]) criteria are set, requiring
  /// each candidate ride's points to be loaded to check.
  bool get needsPointLevelCheck =>
      requireCadenceData || requireHeartRateData || requirePowerData;
}

/// Finds rides matching [filter]: the cheap track-level criteria run as SQL
/// via [AppDatabase.tracksMatching]; any point-level criteria (cadence/HR/
/// power presence) then narrow the result by loading each remaining
/// candidate's points — so the expensive part only touches rides that already
/// passed the SQL-level filter.
Future<List<Track>> filterTracksForClassification(
  AppDatabase db,
  RideClassifierFilter filter,
) async {
  final candidates = await db.tracksMatching(
    onlyUnassigned: filter.onlyUnassigned,
    minDistanceMeters: filter.minDistanceMeters,
    maxDistanceMeters: filter.maxDistanceMeters,
    minAvgSpeedMps: filter.minAvgSpeedMps,
    maxAvgSpeedMps: filter.maxAvgSpeedMps,
    minMaxSpeedMps: filter.minMaxSpeedMps,
    maxMaxSpeedMps: filter.maxMaxSpeedMps,
    startedAfter: filter.startedAfter,
    startedBefore: filter.startedBefore,
  );
  if (!filter.needsPointLevelCheck) return candidates;

  final out = <Track>[];
  for (final t in candidates) {
    final points = await db.pointsFor(t.id);
    if (filter.requireCadenceData && !points.any((p) => p.cadenceRpm != null)) {
      continue;
    }
    if (filter.requireHeartRateData && !points.any((p) => p.heartRate != null)) {
      continue;
    }
    if (filter.requirePowerData && !points.any((p) => p.power != null)) {
      continue;
    }
    out.add(t);
  }
  return out;
}
