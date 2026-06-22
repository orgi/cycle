import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/paired_sensors_store.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _MemStore implements PairedSensorsStore {
  _MemStore([List<String> initial = const []]) : saved = List.of(initial);
  List<String> saved;
  @override
  Future<List<String>> load() async => List.of(saved);
  @override
  Future<void> save(List<String> deviceIds) async => saved = List.of(deviceIds);
}

void main() {
  const hr = DiscoveredSensor(
      id: 'hr1', name: 'HR', kinds: {SensorKind.heartRate});
  const cad = DiscoveredSensor(
      id: 'cad2', name: 'CAD', kinds: {SensorKind.speedCadence});

  test('reconnects previously-paired sensors on startup', () async {
    final fake = FakeSensorService(discoverable: const [hr, cad]);
    final store = _MemStore(['hr1']);
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    // Record connections (subscribe before triggering — the stream doesn't
    // replay).
    final connectedIds = <String>{};
    final sub = fake.connectedSensors().listen(
        (list) => connectedIds
          ..clear()
          ..addAll(list.map((c) => c.id)));
    addTearDown(sub.cancel);

    // Reading the provider runs build() -> load + reconnect.
    container.read(sensorConnectionProvider);
    await pumpEventQueue();

    expect(container.read(sensorConnectionProvider), {'hr1'});
    expect(connectedIds, contains('hr1'));
  });

  test('connect/disconnect keep the persisted set in sync', () async {
    final fake = FakeSensorService(discoverable: const [hr, cad]);
    final store = _MemStore();
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    final ctrl = container.read(sensorConnectionProvider.notifier);
    await ctrl.connect('hr1');
    await ctrl.connect('cad2');
    expect(store.saved..sort(), ['cad2', 'hr1']);

    await ctrl.disconnect('hr1');
    expect(store.saved, ['cad2']);
    expect(container.read(sensorConnectionProvider), {'cad2'});
  });
}
