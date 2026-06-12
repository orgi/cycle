import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/sensors/presentation/sensors_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('scan lists sensors, then connect moves it to Connected',
      (tester) async {
    final fake = FakeSensorService(discoverable: const [
      DiscoveredSensor(
        id: 'hr-1',
        name: 'Garmin HRM-Pro',
        kinds: {SensorKind.heartRate},
      ),
    ]);
    addTearDown(fake.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sensorServiceProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: SensorsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Scan → the sensor is discovered.
    await tester.tap(find.byKey(const Key('scanButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discovered_hr-1')), findsOneWidget);
    expect(find.text('Garmin HRM-Pro'), findsOneWidget);
    expect(find.text('Heart Rate'), findsOneWidget);

    // Connect → it moves to the Connected section.
    await tester.tap(find.descendant(
      of: find.byKey(const Key('discovered_hr-1')),
      matching: find.text('Connect'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connected_hr-1')), findsOneWidget);
    expect(find.byKey(const Key('discovered_hr-1')), findsNothing);
    expect(find.text('Disconnect'), findsOneWidget);
  });
}
