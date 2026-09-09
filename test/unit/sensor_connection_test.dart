import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/paired_sensors_store.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/features/sensors/application/sensor_providers.dart';
import 'package:cycle/features/settings/application/bike_profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _MemStore implements PairedSensorsStore {
  _MemStore([List<PairedSensor> initial = const []]) : saved = List.of(initial);
  List<PairedSensor> saved;
  @override
  Future<List<PairedSensor>> load() async => List.of(saved);
  @override
  Future<void> save(List<PairedSensor> sensors) async => saved = List.of(sensors);
}

void main() {
  const hr = DiscoveredSensor(
      id: 'hr1', name: 'HR', kinds: {SensorKind.heartRate});
  const cad = DiscoveredSensor(
      id: 'cad2', name: 'CAD', kinds: {SensorKind.speedCadence});
  const pairedHr = PairedSensor(id: 'hr1', name: 'HR', kinds: {SensorKind.heartRate});

  test('reconnects previously-paired sensors on startup', () async {
    final fake = FakeSensorService(discoverable: const [hr, cad]);
    final store = _MemStore([pairedHr]);
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
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

    expect(
        container.read(sensorConnectionProvider).map((p) => p.id).toSet(),
        {'hr1'});
    expect(connectedIds, contains('hr1'));
  });

  test('connect/disconnect keep the persisted set in sync', () async {
    final fake = FakeSensorService(discoverable: const [hr, cad]);
    final store = _MemStore();
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
    ]);
    addTearDown(container.dispose);

    final ctrl = container.read(sensorConnectionProvider.notifier);
    await ctrl.connect(hr);
    await ctrl.connect(cad);
    expect(store.saved.map((p) => p.id).toList()..sort(), ['cad2', 'hr1']);

    await ctrl.disconnect('hr1');
    expect(store.saved.map((p) => p.id), ['cad2']);
    expect(
        container.read(sensorConnectionProvider).map((p) => p.id).toSet(),
        {'cad2'});
  });

  test('backfills kinds for a sensor paired under the pre-kinds format once connected',
      () async {
    // Simulates a sensor paired before kinds were persisted (migrated from
    // the old id-only list): known by id, but with no recorded kinds.
    final fake = FakeSensorService(discoverable: const [cad]);
    final store = _MemStore([const PairedSensor(id: 'cad2', name: 'cad2', kinds: {})]);
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
    ]);
    addTearDown(container.dispose);

    container.read(sensorConnectionProvider);
    await pumpEventQueue();

    final updated =
        container.read(sensorConnectionProvider).firstWhere((p) => p.id == 'cad2');
    expect(updated.kinds, {SensorKind.speedCadence});
    expect(updated.name, 'CAD');
    // The fix persists too, not just the in-memory state.
    expect(store.saved.firstWhere((p) => p.id == 'cad2').kinds,
        {SensorKind.speedCadence});
  });

  test('backfills kinds from a scan advertisement alone, without ever connecting',
      () async {
    // The reported bug: a cadence sensor paired under the old id-only format
    // (empty kinds) that is NOT a target of the active bike — so it never
    // connects — must still learn its kind from merely being seen in a scan,
    // so its dashboard tile can show.
    final fake = FakeSensorService(discoverable: const [cad]);
    final store = _MemStore([
      const PairedSensor(id: 'hr1', name: 'HR', kinds: {SensorKind.heartRate}),
      const PairedSensor(id: 'cad2', name: 'cad2', kinds: {}),
    ]);
    const bikeState = BikeProfilesState(
      profiles: [
        // Only HR is pursued; cadence is paired but not a target for this bike.
        BikeProfile(id: 'b1', name: 'Road', colorArgb: 1, sensorIds: {'hr1'}),
      ],
      activeId: 'b1',
    );
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikeState)),
    ]);
    addTearDown(container.dispose);

    var connectedIds = <String>{};
    final sub = fake
        .connectedSensors()
        .listen((list) => connectedIds = list.map((c) => c.id).toSet());
    addTearDown(sub.cancel);

    container.read(sensorConnectionProvider);
    await pumpEventQueue();

    // cadence never connected (not a target) …
    expect(connectedIds.contains('cad2'), isFalse);

    // … but a scan reveals its kind, which gets absorbed + persisted.
    await container.read(scanResultsProvider.notifier).startScan();
    await pumpEventQueue();

    final cadence =
        container.read(sensorConnectionProvider).firstWhere((p) => p.id == 'cad2');
    expect(cadence.kinds, {SensorKind.speedCadence});
    expect(store.saved.firstWhere((p) => p.id == 'cad2').kinds,
        {SensorKind.speedCadence});
  });

  test('a bike profile with a restrictive sensor selection only pursues its own',
      () async {
    final fake = FakeSensorService(discoverable: const [hr, cad]);
    final store = _MemStore([pairedHr, const PairedSensor(id: 'cad2', name: 'CAD', kinds: {SensorKind.speedCadence})]);
    const bikeState = BikeProfilesState(
      profiles: [
        BikeProfile(id: 'b1', name: 'Gravel', colorArgb: 1, sensorIds: {'cad2'}),
      ],
      activeId: 'b1',
    );
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikeState)),
    ]);
    addTearDown(container.dispose);

    var connectedIds = <String>{};
    final sub = fake
        .connectedSensors()
        .listen((list) => connectedIds = list.map((c) => c.id).toSet());
    addTearDown(sub.cancel);

    container.read(sensorConnectionProvider);
    await pumpEventQueue();

    expect(connectedIds, {'cad2'});
  });
}
