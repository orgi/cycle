import '../../../core/db/database.dart';
import '../../../core/metrics/ride_metrics_accumulator.dart';
import '../../../core/models/geo_sample.dart';
import '../../../core/models/ride_metrics.dart';
import '../../../core/models/bike_settings.dart';
import '../../../core/utils/gps_outlier_filter.dart';

/// Outcome of cleaning a recorded track.
class TrackRepairResult {
  const TrackRepairResult({required this.removed, required this.kept});

  /// Number of spike outlier points removed.
  final int removed;

  /// Number of points that remained.
  final int kept;
}

GeoSample _toSample(TrackPoint p) => GeoSample(
  latitude: p.latitude,
  longitude: p.longitude,
  time: p.time,
  speedMps: p.speedMps,
);

/// Recomputes ride stats from recorded [points] (outliers skipped), the way a
/// live ride would — with the auto-pause of [bike], the bike it was ridden on.
RideMetrics computeStatsFromPoints(
  List<TrackPoint> points,
  BikeSettings bike,
) {
  final filter = GpsOutlierFilter();
  final acc = RideMetricsAccumulator(
    autoPauseEnabled: bike.autoPauseEnabled,
    autoPauseThresholdMps: bike.autoPauseThresholdMps,
  );
  var m = const RideMetrics.zero();
  for (final p in points) {
    final s = _toSample(p);
    if (filter.accept(s)) m = acc.add(s);
  }
  return m;
}

/// Recovers rides interrupted by a crash/kill: any track still marked unfinished
/// (`endedAt == null`) has its stats recomputed from the points that *were*
/// saved live, and is finalised — so a killed recording is no longer stuck at
/// zero. Empty leftovers (created but never given a point) are dropped.
///
/// Returns the id of the **most recent** ride if it was interrupted recently
/// (within [resumableWithin]) so the caller can offer to resume it; otherwise
/// `null`.
Future<int?> recoverInterruptedTracks(
  AppDatabase db,
  BikeSettingsLookup settingsFor, {
  Duration resumableWithin = const Duration(hours: 6),
}) async {
  final tracks = await db.allTracks(); // newest first
  final now = DateTime.now();
  int? resumable;
  for (var i = 0; i < tracks.length; i++) {
    final t = tracks[i];
    if (t.endedAt != null) continue; // already finalised
    final points = await db.pointsFor(t.id);
    if (points.isEmpty) {
      await db.purgeTrack(t.id); // crash artefact with no data: erase
      continue;
    }
    // Only the newest ride, interrupted recently, is offered for resume.
    if (i == 0 && now.difference(points.last.time) <= resumableWithin) {
      resumable = t.id;
    }
    final m = computeStatsFromPoints(points, settingsFor(t.bikeProfileId));
    await db.finalizeTrack(
      t.id,
      endedAt: points.last.time,
      distanceMeters: m.distanceMeters,
      durationSeconds: m.elapsed.inSeconds,
      avgSpeedMps: m.avgSpeedMps,
      maxSpeedMps: m.maxSpeedMps,
    );
  }
  return resumable;
}

/// Recomputes and saves one track's distance/duration/avg/max from its
/// already-recorded points, without touching the points themselves — for
/// rides recorded before a change to [RideMetricsAccumulator]'s maths (e.g.
/// the GPS-jitter noise gate) so old rides read consistently with new ones.
/// [bike] is the bike it was ridden on (its auto-pause applies).
/// Returns the recomputed distance in metres, or null if the track has no
/// points (nothing to recompute).
Future<double?> recalculateTrackStats(
  AppDatabase db,
  BikeSettings bike,
  int trackId,
) async {
  final points = await db.pointsFor(trackId);
  if (points.isEmpty) return null;
  final m = computeStatsFromPoints(points, bike);
  await db.updateTrackStats(
    trackId,
    distanceMeters: m.distanceMeters,
    durationSeconds: m.elapsed.inSeconds,
    avgSpeedMps: m.avgSpeedMps,
    maxSpeedMps: m.maxSpeedMps,
  );
  return m.distanceMeters;
}

/// Runs [recalculateTrackStats] over every finalised ride — a one-off "fix my
/// old rides" maintenance action (Settings → Data) after a distance-maths
/// change, so the user doesn't need adb/PC access to correct history. Each
/// ride uses its own bike's auto-pause ([settingsFor]).
/// Returns the number of tracks updated.
Future<int> recalculateAllTrackStats(
  AppDatabase db,
  BikeSettingsLookup settingsFor,
) async {
  final tracks = await db.allTracks();
  var updated = 0;
  for (final t in tracks) {
    if (t.endedAt == null) continue; // interrupted; recovered separately
    final bike = settingsFor(t.bikeProfileId);
    if (await recalculateTrackStats(db, bike, t.id) != null) updated++;
  }
  return updated;
}

/// Removes rides that are exact duplicates of another ride's start time — a
/// one-off "fix my history" maintenance action (Settings → Data) for
/// duplicates created by re-running (or double-tapping into overlapping) an
/// OruxMaps import: two `importFrom` calls in flight at once both read the
/// same "already imported" snapshot before either had written anything back,
/// so every ride in the overlap got inserted twice (confirmed on a real
/// device). For each group of rides sharing a start time, keeps the
/// **lowest id** (the first one inserted) and deletes the rest. Returns the
/// number of rides deleted.
Future<int> removeDuplicateTracks(AppDatabase db) async {
  final tracks = await db.allTracks();
  final seenStarts = <DateTime>{};
  final toDelete = <int>[];
  // allTracks() is newest-first; sort by id ascending so "first seen" for a
  // given start time is the lowest id (first ever inserted), not whichever
  // happens to sort first by start time.
  final byId = [...tracks]..sort((a, b) => a.id.compareTo(b.id));
  for (final t in byId) {
    if (!seenStarts.add(t.startedAt)) toDelete.add(t.id);
  }
  // To the trash, like any delete — restorable for the retention period. The
  // surviving original keeps the start time live, so sync never reads this
  // as "the ride was deleted".
  for (final id in toDelete) {
    await db.deleteTrack(id);
  }
  return toDelete.length;
}

/// Removes GPS "spike" outliers from an already-recorded track and recomputes
/// its distance / duration / average / max from the cleaned points — the same
/// [GpsOutlierFilter] we now apply live, but run after the fact on a ride that
/// was recorded before the fix. Stats use the auto-pause of the ride's bike
/// ([settingsFor]).
Future<TrackRepairResult> repairTrackSpikes(
  AppDatabase db,
  BikeSettingsLookup settingsFor,
  int trackId,
) async {
  final bike = settingsFor((await db.track(trackId))?.bikeProfileId);
  final points = await db.pointsFor(trackId);
  final filter = GpsOutlierFilter();
  final kept = <TrackPoint>[];
  final removedIds = <int>[];
  for (final p in points) {
    if (filter.accept(_toSample(p))) {
      kept.add(p);
    } else {
      removedIds.add(p.id);
    }
  }
  if (removedIds.isEmpty) {
    return TrackRepairResult(removed: 0, kept: kept.length);
  }

  await db.deletePoints(removedIds);

  // Recompute stats over the cleaned points, the way a fresh ride would.
  final acc = RideMetricsAccumulator(
    autoPauseEnabled: bike.autoPauseEnabled,
    autoPauseThresholdMps: bike.autoPauseThresholdMps,
  );
  RideMetrics? m;
  for (final p in kept) {
    m = acc.add(_toSample(p));
  }
  if (m != null) {
    await db.updateTrackStats(
      trackId,
      distanceMeters: m.distanceMeters,
      durationSeconds: m.elapsed.inSeconds,
      avgSpeedMps: m.avgSpeedMps,
      maxSpeedMps: m.maxSpeedMps,
    );
  }
  return TrackRepairResult(removed: removedIds.length, kept: kept.length);
}
