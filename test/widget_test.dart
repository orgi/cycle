import 'package:cycle/core/models/ride_metrics.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('dashboard renders all metric values', (tester) async {
    const metrics = RideMetrics(
      distanceMeters: 1234, // 1.23 km
      currentSpeedMps: 7.0, // 25.2 km/h
      avgSpeedMps: 5.0, // 18.0 km/h
      maxSpeedMps: 10.0, // 36.0 km/h
      elapsed: Duration(minutes: 5, seconds: 3),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rideMetricsProvider.overrideWithValue(metrics)],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );

    expect(find.text('SPEED'), findsOneWidget); // label is upper-cased
    expect(find.text('25.2'), findsOneWidget); // current speed km/h
    expect(find.text('1.23'), findsOneWidget); // distance km
    expect(find.text('18.0'), findsOneWidget); // avg km/h
    expect(find.text('36.0'), findsOneWidget); // max km/h
    expect(find.text('0:05:03'), findsOneWidget); // elapsed
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('dashboard does not overflow on a small screen', (tester) async {
    // Reproduces the small-tile layout that overflowed on the emulator.
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const metrics = RideMetrics(
      distanceMeters: 12345,
      currentSpeedMps: 12.3,
      avgSpeedMps: 10,
      maxSpeedMps: 20,
      elapsed: Duration(hours: 1, minutes: 23, seconds: 45),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rideMetricsProvider.overrideWithValue(metrics)],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Start toggles to Stop and wakes the screen',
      (tester) async {
    final wake = RecordingScreenWakeService();
    final location = FakeLocationService();
    addTearDown(location.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          screenWakeServiceProvider.overrideWithValue(wake),
          locationServiceProvider.overrideWithValue(location),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );

    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pump();

    expect(find.text('Stop'), findsOneWidget);
    expect(wake.enableCount, 1);
  });
}
