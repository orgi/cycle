import 'package:cycle/core/db/database.dart';
import 'package:cycle/core/models/ride_metrics.dart';
import 'package:cycle/core/services/recording_foreground_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/dashboard/presentation/dashboard_screen.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _metrics = RideMetrics(
  distanceMeters: 1234, // 1.23 km
  currentSpeedMps: 7.0, // 25.2 km/h
  avgSpeedMps: 5.0, // 18.0 km/h
  maxSpeedMps: 10.0, // 36.0 km/h
  elapsed: Duration(minutes: 5, seconds: 3),
);

void main() {
  late FakeSensorService sensors;

  setUp(() => sensors = FakeSensorService());
  tearDown(() => sensors.dispose());

  testWidgets('renders all metric values', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rideMetricsProvider.overrideWithValue(_metrics),
          sensorServiceProvider.overrideWithValue(sensors),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('SPEED'), findsOneWidget);
    expect(find.text('25.2'), findsOneWidget); // current speed km/h
    expect(find.text('1.23'), findsOneWidget); // distance km
    expect(find.text('18.0'), findsOneWidget); // avg km/h
    expect(find.text('36.0'), findsOneWidget); // max km/h
    expect(find.text('0:05:03'), findsOneWidget); // elapsed
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('does not overflow on a small screen', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rideMetricsProvider.overrideWithValue(_metrics),
          sensorServiceProvider.overrideWithValue(sensors),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Start toggles to Stop and wakes the screen',
      (tester) async {
    final wake = RecordingScreenWakeService();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sensorServiceProvider.overrideWithValue(sensors),
          locationServiceProvider.overrideWithValue(FakeLocationService()),
          screenWakeServiceProvider.overrideWithValue(wake),
          appDatabaseProvider.overrideWithValue(db),
          recordingForegroundServiceProvider
              .overrideWithValue(const NoopRecordingForegroundService()),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsOneWidget);
    await tester.tap(find.byKey(const Key('startStopButton')));
    await tester.pumpAndSettle();

    expect(find.text('Stop'), findsOneWidget);
    expect(wake.enableCount, 1);
  });
}
