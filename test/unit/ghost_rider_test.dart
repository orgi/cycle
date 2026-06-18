import 'package:cycle/core/utils/geo.dart';
import 'package:cycle/features/routing/domain/follow_route.dart';
import 'package:cycle/features/routing/domain/ghost_rider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Straight north-bound route, ~111 m between points.
  final untimed = FollowRoute.fromCoordinates('r', const [
    (43.7380, 7.4250),
    (43.7390, 7.4250),
    (43.7400, 7.4250),
  ]);

  group('constant target speed (untimed route)', () {
    final ghost = GhostRider(untimed, targetSpeedMps: 10); // 10 m/s

    test('distance advances at the target speed', () {
      expect(ghost.distanceAt(const Duration(seconds: 5)), closeTo(50, 0.001));
    });

    test('clamps to the route length', () {
      expect(
        ghost.distanceAt(const Duration(hours: 1)),
        closeTo(untimed.totalMeters, 0.001),
      );
    });

    test('position interpolates along the route', () {
      // 10 m/s for ~5.5 s ≈ 55 m ≈ half the first leg.
      final firstLeg = haversineMeters(43.7380, 7.4250, 43.7390, 7.4250);
      final pos = ghost.positionAt(
          Duration(milliseconds: (firstLeg / 2 / 10 * 1000).round()));
      expect(pos.latitude, closeTo((43.7380 + 43.7390) / 2, 1e-4));
      expect(pos.longitude, closeTo(7.4250, 1e-6));
    });
  });

  group('timed replay (GPX with timestamps)', () {
    final t0 = DateTime.utc(2026, 1, 1, 10);
    // Same geometry but with timestamps: 10 s between points.
    final timed = FollowRoute.fromGpxPoints('r', [
      (lat: 43.7380, lon: 7.4250, time: t0),
      (lat: 43.7390, lon: 7.4250, time: t0.add(const Duration(seconds: 10))),
      (lat: 43.7400, lon: 7.4250, time: t0.add(const Duration(seconds: 20))),
    ]);

    test('route reports it is timed', () {
      expect(timed.isTimed, isTrue);
      expect(timed.totalDuration, const Duration(seconds: 20));
    });

    test('ghost follows the recorded pace, not the target speed', () {
      final ghost = GhostRider(timed, targetSpeedMps: 999);
      // Halfway through the first 10 s leg → half the first leg distance.
      final half = timed.points[1].distanceFromStartMeters / 2;
      expect(ghost.distanceAt(const Duration(seconds: 5)), closeTo(half, 0.5));
      // At the end time, the ghost is at the route end.
      expect(
        ghost.distanceAt(const Duration(seconds: 20)),
        closeTo(timed.totalMeters, 0.001),
      );
    });
  });
}
