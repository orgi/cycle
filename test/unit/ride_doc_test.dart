import 'dart:convert';

import 'package:cycle/core/sync/ride_doc.dart';
import 'package:cycle/core/sync/sync_clock.dart';
import 'package:flutter_test/flutter_test.dart';

String clk(int ms, [String dev = 'aaaaaaaaaa']) =>
    SyncClock.format(DateTime.fromMillisecondsSinceEpoch(ms), dev);

final _start = DateTime.utc(2026, 6, 1, 8);

RideDoc doc({
  String name = 'Ride',
  String? nameClock,
  String? bike,
  String? bikeClock,
  DateTime? deletedAt,
  String? deletedClock,
  String? geometryClock,
  bool purged = false,
  int points = 2,
  double distance = 1000,
}) =>
    RideDoc(
      startedAt: _start,
      name: name,
      nameClock: nameClock,
      bikeProfileId: bike,
      bikeClock: bikeClock,
      deletedAt: deletedAt,
      deletedClock: deletedClock,
      geometry: RideGeometry(
        clock: geometryClock,
        purged: purged,
        pointCount: purged ? 0 : points,
        endedAt: _start.add(const Duration(hours: 1)),
        distanceMeters: distance,
        durationSeconds: 3600,
        avgSpeedMps: 5,
        maxSpeedMps: 10,
        points: [
          if (!purged)
            for (var i = 0; i < points; i++)
              RidePoint(
                time: _start.add(Duration(seconds: i)),
                latitude: 47 + i / 1000,
                longitude: 11,
                heartRate: 140,
                speedFromSensor: true,
              ),
        ],
      ),
    );

void main() {
  test('clocks order by time, then device id; null is oldest', () {
    expect(SyncClock.compare(clk(2), clk(10)), lessThan(0));
    expect(SyncClock.compare(clk(5, 'a'), clk(5, 'b')), lessThan(0));
    expect(SyncClock.compare(null, clk(0)), lessThan(0));
    expect(SyncClock.timeOf(clk(1234))!.millisecondsSinceEpoch, 1234);
  });

  test('edits to different parts on two phones both survive', () {
    final base = doc(nameClock: clk(1), bikeClock: clk(1), geometryClock: clk(1));
    final renamedOnA = doc(
        name: 'Morning loop', nameClock: clk(10), bikeClock: clk(1), geometryClock: clk(1));
    final bikeOnB = doc(
        nameClock: clk(1), bike: 'gravel', bikeClock: clk(20), geometryClock: clk(1));

    final m = RideDoc.merge(RideDoc.merge(base, renamedOnA), bikeOnB);
    expect(m.name, 'Morning loop');
    expect(m.bikeProfileId, 'gravel');
  });

  test('the same part edited on both phones: the newer edit wins', () {
    final a = doc(name: 'A', nameClock: clk(10));
    final b = doc(name: 'B', nameClock: clk(11));
    expect(RideDoc.merge(a, b).name, 'B');
    expect(RideDoc.merge(b, a).name, 'B');
  });

  test('merge is order independent (all phones converge)', () {
    final docs = [
      doc(name: 'x', nameClock: clk(3), bike: 'p1', bikeClock: clk(9)),
      doc(name: 'y', nameClock: clk(7), geometryClock: clk(2), distance: 900),
      doc(deletedAt: DateTime(2026), deletedClock: clk(5)),
      doc(geometryClock: clk(8), points: 3, distance: 1200),
    ];
    String fold(List<RideDoc> l) =>
        l.skip(1).fold(l.first, RideDoc.merge).signature;
    final expected = fold(docs);
    expect(fold(docs.reversed.toList()), expected);
    expect(fold([docs[2], docs[0], docs[3], docs[1]]), expected);
  });

  test('a deletion newer than every edit wins', () {
    final live = doc(nameClock: clk(5), geometryClock: clk(5));
    final deleted = doc(
        nameClock: clk(5), geometryClock: clk(5),
        deletedAt: DateTime(2026, 6, 2), deletedClock: clk(9));
    final m = RideDoc.merge(live, deleted);
    expect(m.isDeleted, isTrue);
  });

  test('an edit made after the deletion brings the ride back', () {
    final deletedOnA = doc(
        nameClock: clk(5), deletedAt: DateTime(2026, 6, 2), deletedClock: clk(9));
    final renamedLaterOnB = doc(name: 'Keep me', nameClock: clk(12));
    final m = RideDoc.merge(deletedOnA, renamedLaterOnB);
    expect(m.isDeleted, isFalse);
    expect(m.name, 'Keep me');
    // Converges the other way round too.
    expect(RideDoc.merge(renamedLaterOnB, deletedOnA).signature, m.signature);
  });

  test('a purge spreads, but a later restore beats it', () {
    final deleted = doc(
        geometryClock: clk(5), deletedAt: DateTime(2026, 6, 2), deletedClock: clk(9));
    final purged = doc(
        geometryClock: clk(5), purged: true,
        deletedAt: DateTime(2026, 6, 2), deletedClock: clk(9));
    expect(RideDoc.merge(deleted, purged).geometry.purged, isTrue);

    final restored = doc(geometryClock: clk(30), deletedClock: clk(30));
    final m = RideDoc.merge(purged, restored);
    expect(m.isDeleted, isFalse);
    expect(m.geometry.purged, isFalse);
    expect(m.geometry.pointCount, 2);
  });

  test('without clocks (pre-sync rides) the fuller copy wins deterministically', () {
    final short = doc(points: 2, distance: 900);
    final full = doc(points: 5, distance: 1000);
    expect(RideDoc.merge(short, full).geometry.pointCount, 5);
    expect(RideDoc.merge(full, short).geometry.pointCount, 5);
  });

  test('covers: a merged doc covers its inputs, not newer ones', () {
    final a = doc(nameClock: clk(1));
    final b = doc(name: 'B', nameClock: clk(2));
    final m = RideDoc.merge(a, b);
    expect(m.covers(a), isTrue);
    expect(m.covers(b), isTrue);
    expect(a.covers(b), isFalse);
  });

  test('gzip JSON round-trip keeps everything', () {
    final d = doc(
      name: 'Ü-Tour',
      nameClock: clk(1),
      bike: 'p1',
      bikeClock: clk(2),
      deletedAt: DateTime.fromMillisecondsSinceEpoch(1780000000000),
      deletedClock: clk(3),
      geometryClock: clk(4),
      points: 3,
    );
    final back = RideDoc.decode(d.encode());
    expect(RideDoc.fromMetaJson(jsonEncode(d.toMetaJson())).signature, d.signature);
    expect(back.signature, d.signature);
    expect(back.name, 'Ü-Tour');
    expect(back.geometry.points, hasLength(3));
    expect(back.geometry.points!.first.heartRate, 140);
    expect(back.geometry.points!.first.speedFromSensor, isTrue);
    expect(back.key, _start.millisecondsSinceEpoch ~/ 1000);
  });

  test('a file from a newer format version is rejected, not misread', () {
    final j = doc().toJson()..['v'] = 99;
    expect(() => RideDoc.fromJson(j), throwsFormatException);
  });
}
