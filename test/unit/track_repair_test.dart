import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/features/tracks/application/track_repair.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
  // Auto-pause off so the recompute reflects only spike removal.
  const settings = AppSettings(autoPauseEnabled: false);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> addPoint(
    int trackId,
    int sec,
    double lat,
    double lon, {
    double? speed,
  }) => db.addPoint(
    TrackPointsCompanion.insert(
      trackId: trackId,
      time: t0.add(Duration(seconds: sec)),
      latitude: lat,
      longitude: lon,
      speedMps: Value(speed),
    ),
  );

  test('removes a spike point and recomputes stats', () async {
    final id = await db.createTrack(t0);
    // Riding east ~11 m/s… actually ~5.5 m/s per 0.0001° over 1 s.
    await addPoint(id, 0, 0, 0.0000, speed: 5);
    await addPoint(id, 1, 0, 0.0001, speed: 5);
    await addPoint(id, 2, 0, 0.0050, speed: 5); // SPIKE ~556 m east
    await addPoint(id, 3, 0, 0.0002, speed: 5); // back on track
    await addPoint(id, 4, 0, 0.0003, speed: 5);

    final result = await repairTrackSpikes(db, settings, id);
    expect(result.removed, 1);
    expect(result.kept, 4);

    final remaining = await db.pointsFor(id);
    expect(remaining.length, 4);
    // No remaining point is the spike.
    expect(remaining.any((p) => p.longitude > 0.004), isFalse);

    final track = await db.track(id);
    // 4 legs of ~11 m along the cleaned path ≈ 33 m total (0→0.0003° over 3 legs
    // that were kept), certainly far below the ~1100 m a spike out-and-back adds.
    expect(track!.distanceMeters, lessThan(100));
    expect(track.distanceMeters, greaterThan(0));
  });

  test('no spikes → nothing removed', () async {
    final id = await db.createTrack(t0);
    for (var i = 0; i < 5; i++) {
      await addPoint(id, i, 0, 0.0001 * i, speed: 5);
    }
    final result = await repairTrackSpikes(db, settings, id);
    expect(result.removed, 0);
    expect((await db.pointsFor(id)).length, 5);
  });

  test(
    'recovers an interrupted (never finalised) ride from its points',
    () async {
      final id = await db.createTrack(
        t0,
      ); // endedAt stays null (killed mid-ride)
      for (var i = 0; i < 6; i++) {
        await addPoint(id, i, 0, 0.0001 * i, speed: 5);
      }
      // Before recovery: zero stats, no end time.
      var track = await db.track(id);
      expect(track!.endedAt, isNull);
      expect(track.distanceMeters, 0);

      // Old timestamps → recovered but not offered for resume.
      expect(await recoverInterruptedTracks(db, settings), isNull);

      track = await db.track(id);
      expect(track!.endedAt, isNotNull);
      expect(track.distanceMeters, greaterThan(0));
      expect(track.durationSeconds, greaterThan(0));
      expect(track.avgSpeedMps, greaterThan(0));
      // A finalised ride is left alone on a second pass.
      expect(await recoverInterruptedTracks(db, settings), isNull);
    },
  );

  test('offers resume for the newest recently-interrupted ride', () async {
    final base = DateTime.now().subtract(const Duration(minutes: 3));
    final id = await db.createTrack(base);
    for (var i = 0; i < 4; i++) {
      await db.addPoint(
        TrackPointsCompanion.insert(
          trackId: id,
          time: base.add(Duration(seconds: i)),
          latitude: 0,
          longitude: 0.0001 * i,
          speedMps: const Value(5),
        ),
      );
    }
    expect(await recoverInterruptedTracks(db, settings), id);
  });

  test('drops an empty interrupted track (crash before any point)', () async {
    final id = await db.createTrack(t0);
    expect(await recoverInterruptedTracks(db, settings), isNull);
    expect(await db.track(id), isNull); // deleted
  });

  test(
    'recalculateTrackStats recomputes a finalised ride\'s distance',
    () async {
      final id = await db.createTrack(t0);
      for (var i = 0; i < 5; i++) {
        await addPoint(id, i, 0, 0.0001 * i, speed: 5);
      }
      // Finalise with a deliberately wrong stored distance (as if computed by
      // an older, jitter-prone version of the maths).
      await db.finalizeTrack(
        id,
        endedAt: t0.add(const Duration(seconds: 4)),
        distanceMeters: 9999,
        durationSeconds: 4,
        avgSpeedMps: 1,
        maxSpeedMps: 1,
      );

      final recomputed = await recalculateTrackStats(db, settings, id);
      expect(recomputed, isNotNull);
      expect(recomputed, lessThan(100));

      final track = await db.track(id);
      expect(track!.distanceMeters, recomputed);
    },
  );

  test(
    'recalculateTrackStats returns null for a track with no points',
    () async {
      final id = await db.createTrack(t0);
      await db.finalizeTrack(
        id,
        endedAt: t0,
        distanceMeters: 0,
        durationSeconds: 0,
        avgSpeedMps: 0,
        maxSpeedMps: 0,
      );
      expect(await recalculateTrackStats(db, settings, id), isNull);
    },
  );

  test('recalculateAllTrackStats updates every finalised ride, skips '
      'interrupted ones', () async {
    final finished = await db.createTrack(t0);
    for (var i = 0; i < 5; i++) {
      await addPoint(finished, i, 0, 0.0001 * i, speed: 5);
    }
    await db.finalizeTrack(
      finished,
      endedAt: t0.add(const Duration(seconds: 4)),
      distanceMeters: 9999,
      durationSeconds: 4,
      avgSpeedMps: 1,
      maxSpeedMps: 1,
    );

    final interrupted = await db.createTrack(t0); // endedAt stays null
    await addPoint(interrupted, 0, 0, 0);

    final n = await recalculateAllTrackStats(db, settings);
    expect(n, 1);
    final track = await db.track(finished);
    expect(track!.distanceMeters, lessThan(100));
  });
}
