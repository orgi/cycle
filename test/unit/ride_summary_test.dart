import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/utils/ride_summary.dart';
import 'package:flutter_test/flutter_test.dart';

Track _track({
  required DateTime startedAt,
  required double distanceMeters,
  required int durationSeconds,
}) {
  return Track(
    id: 0,
    name: 't',
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: durationSeconds)),
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    avgSpeedMps: durationSeconds > 0 ? distanceMeters / durationSeconds : 0,
    maxSpeedMps: 0,
  );
}

void main() {
  final now = DateTime(2026, 7, 3, 12); // Friday

  test('startOfWeek/Month/Year', () {
    expect(startOfWeek(now), DateTime(2026, 6, 29)); // Monday
    expect(startOfMonth(now), DateTime(2026, 7, 1));
    expect(startOfYear(now), DateTime(2026, 1, 1));
  });

  test('summarizeSince excludes rides before the cutoff', () {
    final tracks = [
      _track(
          startedAt: DateTime(2026, 7, 2),
          distanceMeters: 10000,
          durationSeconds: 3600),
      _track(
          startedAt: DateTime(2026, 6, 20),
          distanceMeters: 5000,
          durationSeconds: 1800),
    ];
    final summary = summarizeSince(tracks, startOfWeek(now));
    expect(summary.rideCount, 1);
    expect(summary.distanceKm, 10);
    expect(summary.duration, const Duration(hours: 1));
    expect(summary.avgSpeedKmh, 10);
  });

  test('summarizeSince with no matching rides is empty', () {
    final summary = summarizeSince(const [], startOfWeek(now));
    expect(summary.rideCount, 0);
    expect(summary.distanceKm, 0);
  });

  test('computeRideSummaries buckets week/month/year', () {
    final tracks = [
      _track(
          startedAt: DateTime(2026, 7, 2), // this week + month + year
          distanceMeters: 10000,
          durationSeconds: 3600),
      _track(
          startedAt: DateTime(2026, 6, 20), // this year only
          distanceMeters: 20000,
          durationSeconds: 7200),
      _track(
          startedAt: DateTime(2026, 1, 5), // this year only
          distanceMeters: 30000,
          durationSeconds: 5400),
      _track(
          startedAt: DateTime(2025, 12, 31), // none
          distanceMeters: 40000,
          durationSeconds: 1000),
    ];
    final s = computeRideSummaries(tracks, now: now);
    expect(s.week.rideCount, 1);
    expect(s.month.rideCount, 1);
    expect(s.year.rideCount, 3);
    expect(s.year.distanceKm, 60);
  });
}
