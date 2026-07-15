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
}
