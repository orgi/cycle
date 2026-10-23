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
      (lat: 43.7384, lon: 7.4246, time: DateTime.utc(2026)),
      (lat: 43.7384, lon: 7.4246, time: DateTime.utc(2026, 1, 1, 0, 0, 1)),
      (lat: 43.7394, lon: 7.4246, time: DateTime.utc(2026, 1, 1, 0, 1)),
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
}
