import 'package:cycle/core/utils/geo.dart';
import 'package:cycle/features/routing/domain/follow_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromCoordinates computes cumulative distances', () {
    final route = FollowRoute.fromCoordinates('r', const [
      (43.7384, 7.4246),
      (43.7394, 7.4246),
      (43.7404, 7.4246),
    ]);

    expect(route.points.length, 3);
    expect(route.points.first.distanceFromStartMeters, 0);

    final leg = haversineMeters(43.7384, 7.4246, 43.7394, 7.4246);
    expect(route.points[1].distanceFromStartMeters, closeTo(leg, 0.01));
    expect(route.points[2].distanceFromStartMeters, closeTo(2 * leg, 0.5));
    expect(route.totalMeters, closeTo(2 * leg, 0.5));
  });

  test('collapses consecutive duplicate points (zero-length legs)', () {
    final route = FollowRoute.fromCoordinates('r', const [
      (43.7384, 7.4246),
      (43.7384, 7.4246), // exact duplicate, dropped
      (43.7394, 7.4246),
    ]);
    expect(route.points.length, 2);
  });

  test('throws when fewer than two distinct points', () {
    expect(
      () => FollowRoute.fromCoordinates('r', const [
        (43.7384, 7.4246),
        (43.7384, 7.4246),
      ]),
      throwsFormatException,
    );
  });

  test('fingerprint: same geometry = same id, whatever the name or times', () {
    final a = FollowRoute.fromCoordinates('A', const [
      (43.7384, 7.4246),
      (43.7394, 7.4246),
    ]);
    final b = FollowRoute.fromGpxPoints('B', [
      (lat: 43.7384, lon: 7.4246, ele: null, time: DateTime.utc(2026)),
      (lat: 43.7384, lon: 7.4246, ele: null, time: DateTime.utc(2026, 1, 1, 0, 0, 1)),
      (lat: 43.7394, lon: 7.4246, ele: null, time: DateTime.utc(2026, 1, 1, 0, 1)),
    ]);
    final moved = FollowRoute.fromCoordinates('A', const [
      (43.7384, 7.4246),
      (43.7395, 7.4246),
    ]);
    final reversed = FollowRoute.fromCoordinates('A', const [
      (43.7394, 7.4246),
      (43.7384, 7.4246),
    ]);
    expect(a.fingerprint, hasLength(32));
    expect(b.fingerprint, a.fingerprint);
    expect(moved.fingerprint, isNot(a.fingerprint));
    expect(reversed.fingerprint, isNot(a.fingerprint));
  });

  group('elevation', () {
    // Points ~111 m apart going north: up 100 m, down 40, up 60.
    FollowRoute route(List<double?> heights) => FollowRoute.fromGpxPoints('E', [
          for (var i = 0; i < heights.length; i++)
            (lat: 47 + i * 0.001, lon: 11.0, ele: heights[i], time: null),
        ]);
    final hilly = route([500, 550, 600, 580, 560, 590, 620]);

    test('profile, total climb and height along the route', () {
      expect(hilly.hasElevation, isTrue);
      expect(hilly.elevationProfile.points.length, 7);
      expect(hilly.totalClimbMeters, 160);
      final d1 = hilly.points[1].distanceFromStartMeters;
      expect(hilly.elevationAt(0), 500);
      expect(hilly.elevationAt(d1 / 2), closeTo(525, 1e-9));
      expect(hilly.elevationAt(hilly.totalMeters + 50), 620);
    });

    test('the climb still ahead shrinks as the rider gets on', () {
      final p = hilly.points;
      expect(hilly.climbRemainingMeters(0), 160);
      // Halfway up the first climb: 25 m of it done.
      expect(
          hilly.climbRemainingMeters(p[1].distanceFromStartMeters / 2),
          closeTo(135, 1e-9));
      // At the first top: only the 60 m after the dip is left.
      expect(hilly.climbRemainingMeters(p[2].distanceFromStartMeters), 60);
      // Going down doesn't change it.
      expect(hilly.climbRemainingMeters(p[4].distanceFromStartMeters), 60);
      expect(hilly.climbRemainingMeters(hilly.totalMeters), 0);
    });

    test('a route without heights has no profile', () {
      final flat = route([null, null, null]);
      expect(flat.hasElevation, isFalse);
      expect(flat.elevationAt(10), isNull);
      expect(flat.totalClimbMeters, 0);
      expect(flat.climbRemainingMeters(0), 0);
    });

    test('heights don\'t change the route\'s identity', () {
      expect(route([500, 550, 600]).fingerprint,
          route([null, null, null]).fingerprint);
    });
  });
}
