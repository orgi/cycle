import 'package:cycle/core/metrics/ride_profile.dart';
import 'package:cycle/features/tracks/presentation/widgets/ride_elevation_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 101 points, evenly spaced: a point per 1 % of the chart's width.
  final profile = RideProfile([
    for (var i = 0; i < 101; i++)
      (latitude: 43 + i * 0.001, longitude: 7.0, altitude: 100.0 + i),
  ]);

  Future<List<int>> pumpChart(WidgetTester tester) async {
    final picked = <int>[];
    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Center(
          child: SizedBox(
            width: 400,
            height: 120,
            child: RideElevationChart(
              profile: profile,
              selected: selected,
              onSelect: (i) => setState(() {
                selected = i;
                picked.add(i);
              }),
            ),
          ),
        ),
      ),
    ));
    return picked;
  }

  Offset at(WidgetTester tester, double fraction) {
    final rect = tester.getRect(find.byType(RideElevationChart));
    return rect.centerLeft + Offset(rect.width * fraction, 0);
  }

  // A pinch used to make the selection jump between the two fingers on every
  // frame on iOS (38, 66, 32, 68, …) — "two dots" on the profile and the map.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('a pinch follows the first finger only ($platform)',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final picked = await pumpChart(tester);
      final a = await tester.startGesture(at(tester, 0.4), pointer: 1);
      await tester.pump(const Duration(milliseconds: 16));
      final b = await tester.startGesture(at(tester, 0.6), pointer: 2);
      for (var k = 0; k < 10; k++) {
        await a.moveBy(const Offset(-8, 0)); // 2 % to the left
        await tester.pump(const Duration(milliseconds: 16));
        await b.moveBy(const Offset(8, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(picked, [40, 38, 36, 34, 32, 30, 28, 26, 24, 22, 20]);

      // All fingers up: the next touch selects again.
      await tester.tapAt(at(tester, 0.75));
      await tester.pumpAndSettle();
      expect(picked.last, 75);
      expect(find.byKey(const Key('rideElevationSelection')), findsOneWidget);
      // Reset in the test body: Flutter checks it before tear-downs run.
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('a finger put down while the first one drags is ignored, also '
      'after the first lifts', (tester) async {
    final picked = await pumpChart(tester);
    final a = await tester.startGesture(at(tester, 0.2), pointer: 1);
    final b = await tester.startGesture(at(tester, 0.9), pointer: 2);
    await a.up();
    await b.moveBy(const Offset(-40, 0));
    await tester.pump();
    await b.up();
    await tester.pumpAndSettle();
    expect(picked, [20]);
  });
}
