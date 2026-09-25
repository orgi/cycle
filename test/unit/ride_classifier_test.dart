import 'package:cycle/core/db/database.dart';
import 'package:cycle/features/tracks/application/ride_classifier.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> seedTrack({
    required DateTime startedAt,
    String? bikeProfileId,
    double distanceMeters = 0,
    List<TrackPointsCompanion> points = const [],
  }) async {
    final id = await db.createTrack(startedAt, bikeProfileId: bikeProfileId);
    for (final p in points) {
      await db.addPoint(p);
    }
    await db.finalizeTrack(id,
        endedAt: startedAt,
        distanceMeters: distanceMeters,
        durationSeconds: 1,
        avgSpeedMps: 0,
        maxSpeedMps: 0);
    return id;
  }

  TrackPointsCompanion point(int trackId, DateTime t,
          {int? heartRate, double? cadenceRpm, int? power}) =>
      TrackPointsCompanion.insert(
        trackId: trackId,
        time: t,
        latitude: 0,
        longitude: 0,
        heartRate: Value(heartRate),
        cadenceRpm: Value(cadenceRpm),
        power: Value(power),
      );

  test('no point-level criteria: returns exactly the SQL-level candidates',
      () async {
    final a = await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
    await seedTrack(startedAt: DateTime.utc(2026, 1, 2), bikeProfileId: 'p1');

    final result = await filterTracksForClassification(
        db, const RideClassifierFilter(onlyUnassigned: true));
    expect(result.map((t) => t.id), [a]);
  });

  test('requireCadenceData narrows to rides with at least one cadence point',
      () async {
    final withCadence = await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
    await db.addPoint(point(withCadence, DateTime.utc(2026, 1, 1),
        cadenceRpm: 80));
    final without = await seedTrack(startedAt: DateTime.utc(2026, 1, 2));
    await db.addPoint(point(without, DateTime.utc(2026, 1, 2)));

    final result = await filterTracksForClassification(
        db, const RideClassifierFilter(requireCadenceData: true));
    expect(result.map((t) => t.id), [withCadence]);
  });

  test('requireHeartRateData and requirePowerData are independent', () async {
    final hrOnly = await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
    await db.addPoint(point(hrOnly, DateTime.utc(2026, 1, 1), heartRate: 140));
    final powerOnly = await seedTrack(startedAt: DateTime.utc(2026, 1, 2));
    await db.addPoint(point(powerOnly, DateTime.utc(2026, 1, 2), power: 200));

    final byHr = await filterTracksForClassification(
        db, const RideClassifierFilter(requireHeartRateData: true));
    expect(byHr.map((t) => t.id), [hrOnly]);

    final byPower = await filterTracksForClassification(
        db, const RideClassifierFilter(requirePowerData: true));
    expect(byPower.map((t) => t.id), [powerOnly]);
  });

  test('a ride needs ALL required point-level criteria satisfied, not just one',
      () async {
    final both = await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
    await db.addPoint(point(both, DateTime.utc(2026, 1, 1),
        heartRate: 140, cadenceRpm: 80));
    final hrOnly = await seedTrack(startedAt: DateTime.utc(2026, 1, 2));
    await db.addPoint(point(hrOnly, DateTime.utc(2026, 1, 2), heartRate: 140));

    final result = await filterTracksForClassification(
        db,
        const RideClassifierFilter(
            requireHeartRateData: true, requireCadenceData: true));
    expect(result.map((t) => t.id), [both]);
  });

  test('combines a SQL-level and a point-level criterion', () async {
    // Matches both: unassigned + has cadence.
    final match = await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
    await db.addPoint(point(match, DateTime.utc(2026, 1, 1), cadenceRpm: 80));
    // Has cadence but already assigned — excluded by onlyUnassigned.
    final assigned =
        await seedTrack(startedAt: DateTime.utc(2026, 1, 2), bikeProfileId: 'p1');
    await db.addPoint(point(assigned, DateTime.utc(2026, 1, 2), cadenceRpm: 80));
    // Unassigned but no cadence — excluded by requireCadenceData.
    final noCadence = await seedTrack(startedAt: DateTime.utc(2026, 1, 3));
    await db.addPoint(point(noCadence, DateTime.utc(2026, 1, 3)));

    final result = await filterTracksForClassification(
      db,
      const RideClassifierFilter(onlyUnassigned: true, requireCadenceData: true),
    );
    expect(result.map((t) => t.id), [match]);
  });

  test('empty filter matches every ride', () async {
    await seedTrack(startedAt: DateTime.utc(2026, 1, 1));
    await seedTrack(startedAt: DateTime.utc(2026, 1, 2));

    final result =
        await filterTracksForClassification(db, const RideClassifierFilter());
    expect(result.length, 2);
  });
}
