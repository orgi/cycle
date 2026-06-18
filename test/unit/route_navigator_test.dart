import 'package:cycle/core/utils/geo.dart';
import 'package:cycle/features/routing/domain/follow_route.dart';
import 'package:cycle/features/routing/domain/route_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A straight ~north-bound route: three points spaced ~111 m apart in latitude.
  final route = FollowRoute.fromCoordinates('straight', const [
    (43.7380, 7.4250),
    (43.7390, 7.4250),
    (43.7400, 7.4250),
  ]);
  final navigator = RouteNavigator(route, offRouteThresholdMeters: 30);

  test('on the route: tiny cross-track, on route', () {
    final p = navigator.locate(43.7390, 7.4250);
    expect(p.crossTrackMeters, lessThan(1));
    expect(p.offRoute, isFalse);
  });

  test('remaining distance shrinks toward the end', () {
    final atStart = navigator.locate(43.7380, 7.4250);
    final atMid = navigator.locate(43.7390, 7.4250);
    final atEnd = navigator.locate(43.7400, 7.4250);

    expect(atStart.remainingMeters, closeTo(route.totalMeters, 0.5));
    expect(atMid.remainingMeters, closeTo(route.totalMeters / 2, 1.0));
    expect(atEnd.remainingMeters, closeTo(0, 0.5));
  });

  test('projects mid-segment and reports traveled distance', () {
    // 1/4 of the way up the first segment.
    final p = navigator.locate(43.73825, 7.4250);
    final firstLeg = haversineMeters(43.7380, 7.4250, 43.7390, 7.4250);
    expect(p.nearestSegmentIndex, 0);
    expect(p.traveledMeters, closeTo(firstLeg * 0.25, 2.0));
  });

  test('off route when cross-track exceeds threshold', () {
    // ~80 m east of the line (0.001 deg lon ≈ 80 m at this latitude).
    final p = navigator.locate(43.7390, 7.4260);
    expect(p.crossTrackMeters, greaterThan(30));
    expect(p.offRoute, isTrue);
  });

  test('near but within threshold stays on route', () {
    // ~16 m east (0.0002 deg lon).
    final p = navigator.locate(43.7390, 7.4252);
    expect(p.crossTrackMeters, lessThan(30));
    expect(p.offRoute, isFalse);
  });
}
