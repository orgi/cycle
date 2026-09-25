// Aggregates recorded rides into rolling week/month/year totals for the Rides
// overview. Pure functions (no Riverpod/widget deps) so they're unit-tested
// directly against a list of tracks.

import '../db/database.dart';

/// Totals for the rides that started on/after a period's start.
class RideSummary {
  const RideSummary({
    required this.rideCount,
    required this.distanceKm,
    required this.duration,
    required this.avgSpeedKmh,
  });

  static const empty = RideSummary(
    rideCount: 0,
    distanceKm: 0,
    duration: Duration.zero,
    avgSpeedKmh: 0,
  );

  final int rideCount;
  final double distanceKm;
  final Duration duration;
  final double avgSpeedKmh;
}

/// This-week/this-month/this-year totals, all as of the same `now`.
class RideSummaries {
  const RideSummaries({
    required this.week,
    required this.month,
    required this.year,
  });

  final RideSummary week;
  final RideSummary month;
  final RideSummary year;
}

/// Local midnight of the Monday on/before [now].
DateTime startOfWeek(DateTime now) {
  final local = now.toLocal();
  final midnight = DateTime(local.year, local.month, local.day);
  return midnight.subtract(Duration(days: midnight.weekday - 1));
}

DateTime startOfMonth(DateTime now) {
  final local = now.toLocal();
  return DateTime(local.year, local.month, 1);
}

DateTime startOfYear(DateTime now) {
  final local = now.toLocal();
  return DateTime(local.year, 1, 1);
}

RideSummary summarizeSince(List<Track> tracks, DateTime since) {
  var rideCount = 0;
  var distanceMeters = 0.0;
  var durationSeconds = 0;
  for (final t in tracks) {
    if (t.startedAt.toLocal().isBefore(since)) continue;
    rideCount++;
    distanceMeters += t.distanceMeters;
    durationSeconds += t.durationSeconds;
  }
  if (rideCount == 0) return RideSummary.empty;
  final distanceKm = distanceMeters / 1000;
  final duration = Duration(seconds: durationSeconds);
  final avgSpeedKmh =
      durationSeconds > 0 ? distanceKm / (durationSeconds / 3600) : 0.0;
  return RideSummary(
    rideCount: rideCount,
    distanceKm: distanceKm,
    duration: duration,
    avgSpeedKmh: avgSpeedKmh,
  );
}

RideSummaries computeRideSummaries(List<Track> tracks, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return RideSummaries(
    week: summarizeSince(tracks, startOfWeek(n)),
    month: summarizeSince(tracks, startOfMonth(n)),
    year: summarizeSince(tracks, startOfYear(n)),
  );
}
