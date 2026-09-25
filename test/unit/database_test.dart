import 'package:cycle/core/db/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('create track, add points, finalize, query', () async {
    final start = DateTime.utc(2026, 1, 1, 8);
    final id = await db.createTrack(start, name: 'Morning ride');

    await db.addPoint(TrackPointsCompanion.insert(
      trackId: id,
      time: start,
      latitude: 43.0,
      longitude: 7.0,
      heartRate: const Value(150),
      power: const Value(220),
    ));
    await db.addPoint(TrackPointsCompanion.insert(
      trackId: id,
      time: start.add(const Duration(seconds: 1)),
      latitude: 43.001,
      longitude: 7.0,
    ));

    await db.finalizeTrack(
      id,
      endedAt: start.add(const Duration(minutes: 30)),
      distanceMeters: 12000,
      durationSeconds: 1800,
      avgSpeedMps: 6.67,
      maxSpeedMps: 12.0,
    );

    final track = await db.track(id);
    expect(track, isNotNull);
    expect(track!.name, 'Morning ride');
    expect(track.distanceMeters, 12000);
    expect(track.endedAt, isNotNull);

    final points = await db.pointsFor(id);
    expect(points.length, 2);
    expect(points.first.heartRate, 150);
    expect(points.first.power, 220);
    expect(points.last.heartRate, isNull);
  });

  test('watchTracks returns newest first', () async {
    await db.createTrack(DateTime.utc(2026, 1, 1), name: 'older');
    await db.createTrack(DateTime.utc(2026, 1, 2), name: 'newer');
    final tracks = await db.allTracks();
    expect(tracks.map((t) => t.name), ['newer', 'older']);
  });

  test('deleteTrack cascades to its points', () async {
    final id = await db.createTrack(DateTime.utc(2026, 1, 1));
    await db.addPoint(TrackPointsCompanion.insert(
        trackId: id, time: DateTime.utc(2026, 1, 1), latitude: 1, longitude: 2));

    await db.deleteTrack(id);
    expect(await db.track(id), isNull);
    expect(await db.pointsFor(id), isEmpty);
  });

  test('createTrack stamps a bike profile; defaults to null', () async {
    final withProfile = await db.createTrack(DateTime.utc(2026, 1, 1),
        bikeProfileId: 'p1');
    final withoutProfile = await db.createTrack(DateTime.utc(2026, 1, 1));

    expect((await db.track(withProfile))!.bikeProfileId, 'p1');
    expect((await db.track(withoutProfile))!.bikeProfileId, isNull);
  });

  test('setTrackBikeProfile corrects/clears the profile on an existing track',
      () async {
    final id = await db.createTrack(DateTime.utc(2026, 1, 1),
        bikeProfileId: 'p1');

    await db.setTrackBikeProfile(id, 'p2');
    expect((await db.track(id))!.bikeProfileId, 'p2');

    await db.setTrackBikeProfile(id, null);
    expect((await db.track(id))!.bikeProfileId, isNull);
  });

  test('assignAllTracksToBikeProfile overwrites every ride, returns the count',
      () async {
    final a = await db.createTrack(DateTime.utc(2026, 1, 1));
    final b = await db.createTrack(DateTime.utc(2026, 1, 2), bikeProfileId: 'p1');
    final c = await db.createTrack(DateTime.utc(2026, 1, 3), bikeProfileId: 'p2');

    final n = await db.assignAllTracksToBikeProfile('cube');
    expect(n, 3);
    expect((await db.track(a))!.bikeProfileId, 'cube');
    expect((await db.track(b))!.bikeProfileId, 'cube');
    expect((await db.track(c))!.bikeProfileId, 'cube');
  });

  test('assignTracksToBikeProfile updates exactly the given ids', () async {
    final a = await db.createTrack(DateTime.utc(2026, 1, 1));
    final b = await db.createTrack(DateTime.utc(2026, 1, 2));
    final c = await db.createTrack(DateTime.utc(2026, 1, 3));

    final n = await db.assignTracksToBikeProfile([a, c], 'cube');
    expect(n, 2);
    expect((await db.track(a))!.bikeProfileId, 'cube');
    expect((await db.track(b))!.bikeProfileId, isNull);
    expect((await db.track(c))!.bikeProfileId, 'cube');
  });

  test('assignTracksToBikeProfile with an empty list is a no-op', () async {
    expect(await db.assignTracksToBikeProfile(const [], 'cube'), 0);
  });

  Future<int> seedTrack({
    required DateTime startedAt,
    String? bikeProfileId,
    double distanceMeters = 0,
    double avgSpeedMps = 0,
    double maxSpeedMps = 0,
  }) =>
      db.createTrack(startedAt, bikeProfileId: bikeProfileId).then((id) async {
        await db.finalizeTrack(
          id,
          endedAt: startedAt,
          distanceMeters: distanceMeters,
          durationSeconds: 1,
          avgSpeedMps: avgSpeedMps,
          maxSpeedMps: maxSpeedMps,
        );
        return id;
      });

  group('tracksMatching', () {
    test('onlyUnassigned filters out rides with a bike', () async {
      final a = await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
      await seedTrack(startedAt: DateTime.utc(2026, 1, 2), bikeProfileId: 'p1');

      final result = await db.tracksMatching(onlyUnassigned: true);
      expect(result.map((t) => t.id), [a]);
    });

    test('distance range filters both ends', () async {
      final short =
          await seedTrack(startedAt: DateTime.utc(2026, 1, 1), distanceMeters: 5000);
      final mid =
          await seedTrack(startedAt: DateTime.utc(2026, 1, 2), distanceMeters: 20000);
      await seedTrack(startedAt: DateTime.utc(2026, 1, 3), distanceMeters: 50000);

      final result = await db.tracksMatching(
          minDistanceMeters: 10000, maxDistanceMeters: 30000);
      expect(result.map((t) => t.id), [mid]);
      expect(result.any((t) => t.id == short), isFalse);
    });

    test('avg/max speed ranges filter independently', () async {
      final a = await seedTrack(
          startedAt: DateTime.utc(2026, 1, 1), avgSpeedMps: 5, maxSpeedMps: 8);
      await seedTrack(
          startedAt: DateTime.utc(2026, 1, 2), avgSpeedMps: 15, maxSpeedMps: 20);

      final byAvg = await db.tracksMatching(maxAvgSpeedMps: 10);
      expect(byAvg.map((t) => t.id), [a]);

      final byMax = await db.tracksMatching(minMaxSpeedMps: 15);
      expect(byMax.map((t) => t.id), isNot(contains(a)));
    });

    test('date range filters startedAt', () async {
      await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
      final mid = await seedTrack(startedAt: DateTime.utc(2026, 6, 1));
      await seedTrack(startedAt: DateTime.utc(2026, 12, 1));

      final result = await db.tracksMatching(
        startedAfter: DateTime.utc(2026, 3, 1),
        startedBefore: DateTime.utc(2026, 9, 1),
      );
      expect(result.map((t) => t.id), [mid]);
    });

    test('combines multiple criteria (AND)', () async {
      final match = await seedTrack(
        startedAt: DateTime.utc(2026, 6, 1),
        distanceMeters: 20000,
        avgSpeedMps: 6,
      );
      // Right distance, wrong date.
      await seedTrack(
        startedAt: DateTime.utc(2026, 1, 1),
        distanceMeters: 20000,
        avgSpeedMps: 6,
      );
      // Right date, wrong distance.
      await seedTrack(
        startedAt: DateTime.utc(2026, 6, 2),
        distanceMeters: 1000,
        avgSpeedMps: 6,
      );

      final result = await db.tracksMatching(
        minDistanceMeters: 10000,
        startedAfter: DateTime.utc(2026, 3, 1),
        startedBefore: DateTime.utc(2026, 9, 1),
      );
      expect(result.map((t) => t.id), [match]);
    });

    test('no criteria returns every ride, newest first', () async {
      await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
      await seedTrack(startedAt: DateTime.utc(2026, 1, 2));

      final result = await db.tracksMatching();
      expect(result.length, 2);
      expect(result.first.startedAt.isAfter(result.last.startedAt), isTrue);
    });
  });
}
