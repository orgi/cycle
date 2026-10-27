import 'dart:math' as math;

import 'package:cycle/core/metrics/elevation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AltitudeSmoother', () {
    test('averages the last few altitudes', () {
      final s = AltitudeSmoother(window: 3);
      expect(s.value, isNull);
      expect(s.add(100), 100);
      expect(s.add(103), 101.5);
      expect(s.add(106), 103);
      expect(s.add(109), 106); // 100 has dropped out
      s.reset();
      expect(s.value, isNull);
    });
  });

  group('ClimbCounter', () {
    double climb(List<double> altitudes, {double threshold = 5}) {
      final c = ClimbCounter(thresholdMeters: threshold);
      altitudes.forEach(c.add);
      return c.climbMeters;
    }

    test('a steady climb counts in full', () {
      expect(climb([for (var a = 500.0; a <= 600; a += 1) a]), 100);
    });

    test('noise smaller than the threshold never adds up', () {
      expect(
          climb([for (var i = 0; i < 600; i++) i.isEven ? 500.0 : 504.0]), 0);
    });

    test('a dip smaller than the threshold does not end a climb', () {
      expect(climb([500, 510, 506, 520]), 20);
    });

    test('climbs separated by real descents each count', () {
      expect(climb([500, 550, 520, 580, 400, 450]), 50 + 60 + 50);
    });

    test(
        'a descent counts nothing, and the climb after it starts at the '
        'bottom', () {
      expect(climb([600, 590, 570, 520, 523, 530]), 10);
    });

    test(
        'a start that wobbles below the first height still counts from the '
        'low point', () {
      expect(climb([100, 98, 96, 103]), 7);
    });
  });

  group('ElevationProfileBuilder', () {
    test('keeps a point every spacing, plus the newest fix', () {
      final b = ElevationProfileBuilder(spacingMeters: 10);
      for (var d = 0.0; d <= 25; d += 5) {
        b.add(d, 500 + d);
      }
      expect(b.profile.points, const [
        ProfilePoint(0, 500),
        ProfilePoint(10, 510),
        ProfilePoint(20, 520),
        ProfilePoint(25, 525),
      ]);
    });

    test('a long ride stays a bounded number of points, start and end kept',
        () {
      final b = ElevationProfileBuilder(maxPoints: 100, spacingMeters: 10);
      for (var d = 0.0; d <= 100000; d += 5) {
        b.add(d, 500 + 100 * math.sin(d / 5000));
      }
      final points = b.profile.points;
      expect(points.length, lessThanOrEqualTo(101));
      expect(points.length, greaterThan(40));
      expect(points.first.distanceMeters, 0);
      expect(points.last.distanceMeters, 100000);
      for (var i = 1; i < points.length; i++) {
        expect(points[i].distanceMeters,
            greaterThan(points[i - 1].distanceMeters));
      }
    });

    test('the same profile object until something is added', () {
      final b = ElevationProfileBuilder()..add(0, 1);
      expect(identical(b.profile, b.profile), isTrue);
      final before = b.profile;
      b.add(3, 2);
      expect(identical(before, b.profile), isFalse);
    });
  });

  group('ElevationProfile', () {
    test('min, max and thinning', () {
      final p = ElevationProfile([
        for (var i = 0; i < 1000; i++) ProfilePoint(i * 10.0, 500.0 + i % 7),
      ]);
      expect(p.minElevation, 500);
      expect(p.maxElevation, 506);
      final t = p.thinned(100);
      expect(t.points.length, inInclusiveRange(100, 101));
      expect(t.points.first, p.points.first);
      expect(t.points.last, p.points.last);
      expect(identical(p.thinned(5000), p), isTrue);
    });
  });

  group('RideElevation', () {
    test('smoothed height, climb and profile from the same fixes', () {
      final e = RideElevation();
      expect(e.elevationMeters, isNull);
      expect(e.profile.isEmpty, isTrue);
      final points = <({double? altitude, double? speedMps})>[];
      for (var i = 0; i <= 300; i++) {
        // 300 m of climb with ±3 m of GPS jitter, and a few fixes without
        // a height.
        final a = i % 50 == 7 ? null : 400 + i + (i.isEven ? 3.0 : -3.0);
        points.add((altitude: a, speedMps: 2));
        e.add(a, i * 5.0, 2);
      }
      expect(e.climbMeters, closeTo(300, 6));
      expect(e.elevationMeters, closeTo(700, 3));
      expect(e.profile.points.last.distanceMeters, 1500);
      // The saved ride's points give the same climb.
      expect(rideClimbMeters(points), e.climbMeters);
    });

    test('jitter along a flat road adds next to no climb', () {
      final rnd = math.Random(7);
      final points = [
        for (var i = 0; i < 3600; i++)
          (altitude: 520 + (rnd.nextDouble() - 0.5) * 6, speedMps: 6.0),
      ];
      expect(rideClimbMeters(points), lessThan(10));
    });

    test('standing still adds no climb, however the height wanders', () {
      final e = RideElevation();
      for (var i = 0; i < 1800; i++) {
        // A slow 20 m wander over half an hour at a café.
        e.add(520 + 10 * math.sin(i / 200), 1000, 0.1);
      }
      expect(e.climbMeters, 0);
      expect(e.elevationMeters, isNotNull); // the height still shows
      for (var i = 1; i <= 30; i++) {
        e.add(524 + i * 2.0, 1000 + i * 4.0, 3); // riding on, 60 m up
      }
      expect(e.climbMeters, closeTo(60, 6));
    });

    test('reset starts a new ride', () {
      final e = RideElevation()
        ..add(500, 0, 3)
        ..add(520, 100, 3);
      e.reset();
      expect(e.climbMeters, 0);
      expect(e.elevationMeters, isNull);
      expect(e.profile.points, isEmpty);
    });
  });
}
