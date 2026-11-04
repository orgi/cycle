import 'package:cycle/core/controls/ride_continuation.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 29, 12);
  // ~1 m per 0.000009° of latitude.
  GeoSample fix({double north = 0, int ageSeconds = 2, double? accuracy = 5}) =>
      GeoSample(
        latitude: 47 + north / 111195,
        longitude: 11,
        time: now.subtract(Duration(seconds: ageSeconds)),
        accuracyMeters: accuracy,
      );

  bool decide({
    GeoSample? here,
    Duration ago = const Duration(minutes: 10),
    Duration window = const Duration(minutes: 30),
  }) => shouldContinueRide(
    stoppedAt: now.subtract(ago),
    lastLatitude: 47,
    lastLongitude: 11,
    here: here,
    now: now,
    window: window,
  );

  test('continues a ride stopped recently, right here', () {
    expect(decide(here: fix(north: 20)), isTrue);
    expect(decide(here: fix(north: 190)), isTrue);
  });

  test('a new ride once the rider has moved on', () {
    expect(decide(here: fix(north: 250)), isFalse);
    expect(decide(here: fix(north: 5000)), isFalse);
  });

  test('a new ride after the window', () {
    expect(decide(here: fix(), ago: const Duration(minutes: 31)), isFalse);
    expect(
      decide(
        here: fix(),
        ago: const Duration(minutes: 50),
        window: const Duration(minutes: 60),
      ),
      isTrue,
    );
  });

  test('a new ride without a current fix: an old one could be anywhere', () {
    expect(decide(here: null), isFalse);
    expect(decide(here: fix(ageSeconds: 120)), isFalse);
    expect(decide(here: fix(accuracy: 80)), isFalse);
    expect(decide(here: fix(accuracy: null)), isTrue);
  });

  test('a stop in the future (clock change) is not continued', () {
    expect(decide(here: fix(), ago: const Duration(minutes: -5)), isFalse);
  });

  test('isCurrentFix: recent and roughly accurate', () {
    expect(isCurrentFix(fix(ageSeconds: 30), now), isTrue);
    expect(isCurrentFix(fix(ageSeconds: 31), now), isFalse);
    expect(isCurrentFix(fix(accuracy: 50), now), isTrue);
    expect(isCurrentFix(fix(accuracy: 51), now), isFalse);
    expect(isCurrentFix(fix(accuracy: 15), now, maxAccuracyMeters: 20), isTrue);
  });
}
