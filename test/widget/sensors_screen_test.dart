import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/paired_sensors_store.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/sensors/presentation/sensors_screen.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _MemPaired implements PairedSensorsStore {
  _MemPaired(this.saved);
  List<PairedSensor> saved;
  @override
  Future<List<PairedSensor>> load() async => List.of(saved);
  @override
  Future<void> save(List<PairedSensor> sensors) async => saved = List.of(sensors);
}

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
        overrides: [
          sensorServiceProvider.overrideWithValue(fake),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
        ],
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

  testWidgets('a paired-but-disconnected sensor shows a Reconnect button that kicks it',
      (tester) async {
    // Paired speed sensor that isn't currently connected (connectTargets:false).
    final fake = FakeSensorService(connectTargets: false);
    addTearDown(fake.dispose);
    final paired = _MemPaired([
      const PairedSensor(
          id: 'spd-1', name: 'SPD-BLE0187176', kinds: {SensorKind.speedCadence}),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sensorServiceProvider.overrideWithValue(fake),
          pairedSensorsStoreProvider.overrideWithValue(paired),
          bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
        ],
        child: const MaterialApp(home: SensorsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Listed as paired, disconnected, with a Reconnect button.
    expect(find.text('SPD-BLE0187176'), findsOneWidget);
    expect(find.byKey(const Key('reconnect_spd-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reconnect_spd-1')));
    await tester.pumpAndSettle();
    expect(fake.reconnectCalls, contains('spd-1'));
  });
}
