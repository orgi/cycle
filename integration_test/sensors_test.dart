import 'package:cycle/app.dart';
import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/features/dashboard/application/ride_providers.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows live sensor data and pairs a sensor', (tester) async {
    final sensors = FakeSensorService(discoverable: const [
      DiscoveredSensor(
        id: 'hr-1',
        name: 'Garmin HRM-Pro',
        kinds: {SensorKind.heartRate},
      ),
    ]);
    final location = FakeLocationService();
    final wake = RecordingScreenWakeService();
    addTearDown(sensors.dispose);
    addTearDown(location.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sensorServiceProvider.overrideWithValue(sensors),
          locationServiceProvider.overrideWithValue(location),
          screenWakeServiceProvider.overrideWithValue(wake),
        ],
        child: const CycleApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Live heart rate appears on the dashboard.
    sensors.emitSnapshot(const SensorSnapshot(heartRate: 148, cadenceRpm: 92));
    await tester.pumpAndSettle();
    expect(find.text('HEART'), findsOneWidget);
    expect(find.text('148'), findsOneWidget);

    // Pair a sensor from the Sensors screen.
    await tester.tap(find.byKey(const Key('openSensorsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scanButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discovered_hr-1')), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.byKey(const Key('discovered_hr-1')),
      matching: find.text('Connect'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connected_hr-1')), findsOneWidget);
  });
}
