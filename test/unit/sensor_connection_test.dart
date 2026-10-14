import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/paired_sensors_store.dart';
import 'package:cycle/core/sensors/sensor_catalog.dart';
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
      sensorCatalogStoreProvider.overrideWithValue(MemorySensorCatalogStore()),
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
      sensorCatalogStoreProvider.overrideWithValue(MemorySensorCatalogStore()),
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
      sensorCatalogStoreProvider.overrideWithValue(MemorySensorCatalogStore()),
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
      sensorCatalogStoreProvider.overrideWithValue(MemorySensorCatalogStore()),
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

  test('reconnectKind kicks a one-shot reconnect for that kind, honouring the profile',
      () async {
    final fake = FakeSensorService(discoverable: const [hr, cad]);
    final store = _MemStore([
      pairedHr,
      const PairedSensor(id: 'cad2', name: 'CAD', kinds: {SensorKind.speedCadence}),
    ]);
    const bikeState = BikeProfilesState(
      profiles: [
        // Only the cadence sensor is selected for this bike.
        BikeProfile(id: 'b1', name: 'Gravel', colorArgb: 1, sensorIds: {'cad2'}),
      ],
      activeId: 'b1',
    );
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
      sensorCatalogStoreProvider.overrideWithValue(MemorySensorCatalogStore()),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikeState)),
    ]);
    addTearDown(container.dispose);
    final ctrl = container.read(sensorConnectionProvider.notifier);
    await pumpEventQueue();

    // Cadence is in the profile → reconnect kicks it.
    expect(await ctrl.reconnectKind(SensorKind.speedCadence), 1);
    expect(fake.reconnectCalls, contains('cad2'));

    // HR is paired but NOT selected for this bike → not kicked.
    fake.reconnectCalls.clear();
    expect(await ctrl.reconnectKind(SensorKind.heartRate), 0);
    expect(fake.reconnectCalls, isEmpty);
  });

  test('reconnectCsc targets the speed vs cadence sensor by name (not both)',
      () async {
    // A speed sensor and a cadence sensor are the same GATT type; distinguish
    // by name so tapping SPEED reconnects only the speed sensor and CAD only
    // the cadence one.
    final fake = FakeSensorService();
    final store = _MemStore([
      const PairedSensor(
          id: 'spd', name: 'SPD-BLE0187176', kinds: {SensorKind.speedCadence}),
      const PairedSensor(
          id: 'cad', name: 'CAD-BLE0254805', kinds: {SensorKind.speedCadence}),
    ]);
    final container = ProviderContainer(overrides: [
      sensorServiceProvider.overrideWithValue(fake),
      pairedSensorsStoreProvider.overrideWithValue(store),
      sensorCatalogStoreProvider.overrideWithValue(MemorySensorCatalogStore()),
      bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore()),
    ]);
    addTearDown(container.dispose);
    final ctrl = container.read(sensorConnectionProvider.notifier);
    await pumpEventQueue();

    fake.reconnectCalls.clear();
    expect(await ctrl.reconnectCsc(wantSpeed: true), 1);
    expect(fake.reconnectCalls, ['spd']);

    fake.reconnectCalls.clear();
    expect(await ctrl.reconnectCsc(wantSpeed: false), 1);
    expect(fake.reconnectCalls, ['cad']);
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
      sensorCatalogStoreProvider.overrideWithValue(MemorySensorCatalogStore()),
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

  group('sensors across phones', () {
    const hrm = DiscoveredSensor(
        id: 'AA:BB:CC:00:00:01', name: 'HRM-Pro:123456', kinds: {SensorKind.heartRate});
    const iosHrm = DiscoveredSensor(
        id: '4F1C-UUID-ON-THIS-IPHONE', name: 'HRM-Pro:123456', kinds: {SensorKind.heartRate});

    ProviderContainer phone({
      required bool android,
      FakeSensorService? service,
      _MemStore? paired,
      MemorySensorCatalogStore? catalog,
      BikeProfilesState bikes = const BikeProfilesState(
        profiles: [BikeProfile(id: 'road', name: 'Road', colorArgb: 1)],
        activeId: 'road',
      ),
    }) {
      final c = ProviderContainer(overrides: [
        sensorServiceProvider.overrideWithValue(service ?? FakeSensorService()),
        pairedSensorsStoreProvider.overrideWithValue(paired ?? _MemStore()),
        sensorCatalogStoreProvider
            .overrideWithValue(catalog ?? MemorySensorCatalogStore()),
        bikeProfilesStoreProvider.overrideWithValue(FakeBikeProfilesStore(bikes)),
        sensorIdsPortableProvider.overrideWithValue(android),
      ]);
      addTearDown(c.dispose);
      c.listen(bikeProfilesProvider, (_, _) {});
      c.read(sensorConnectionProvider);
      return c;
    }

    test('pairing records the sensor for the other phones; Android shares '
        'its address, iOS does not', () async {
      final a = phone(android: true);
      await pumpEventQueue();
      await a.read(sensorConnectionProvider.notifier).connect(hrm);
      expect(a.read(sensorCatalogProvider)['hrm-pro:123456']!.address, hrm.id);

      final i = phone(android: false);
      await pumpEventQueue();
      await i.read(sensorConnectionProvider.notifier).connect(iosHrm);
      expect(i.read(sensorCatalogProvider)['hrm-pro:123456']!.address, isNull);
    });

    test('an Android phone links a sensor another Android phone paired, '
        'without scanning, and puts it on the synced bike', () async {
      final fake = FakeSensorService();
      final c = phone(android: true, service: fake, bikes: const BikeProfilesState(
        profiles: [
          BikeProfile(id: 'road', name: 'Road', colorArgb: 1,
              sensorKeys: {'hrm-pro:123456'}, sensorsClock: '000000000000009@x'),
        ],
        activeId: 'road',
      ));
      await pumpEventQueue();
      final connected = <String>{};
      final sub = fake.connectedSensors().listen((l) => connected
        ..clear()
        ..addAll(l.map((e) => e.id)));
      addTearDown(sub.cancel);

      // Sync delivers the catalog from the other phone.
      await c.read(sensorCatalogProvider.notifier).replaceFromSync(
          const SensorCatalog().put(KnownSensor(
              name: hrm.name, kinds: hrm.kinds, address: hrm.id, clock: '000000000000010@x')));
      await pumpEventQueue();

      expect(c.read(sensorConnectionProvider).map((p) => p.id), [hrm.id]);
      expect(c.read(bikeProfilesProvider).active!.sensorIds, {hrm.id});
      expect(connected, contains(hrm.id));
    });

    test('an iPhone links a known sensor when a scan finds it by name, and '
        'it joins the bikes chosen on the other phone', () async {
      final fake = FakeSensorService(discoverable: const [iosHrm]);
      final catalog = MemorySensorCatalogStore(const SensorCatalog().put(KnownSensor(
          name: hrm.name, kinds: hrm.kinds, address: hrm.id, clock: '000000000000010@x')));
      final c = phone(android: false, service: fake, catalog: catalog,
          bikes: const BikeProfilesState(
        profiles: [
          BikeProfile(id: 'road', name: 'Road', colorArgb: 1,
              sensorKeys: {'hrm-pro:123456'}, sensorsClock: '000000000000009@x'),
          BikeProfile(id: 'mtb', name: 'MTB', colorArgb: 2,
              sensorKeys: {}, sensorsClock: '000000000000009@x'),
        ],
        activeId: 'road',
      ));
      await pumpEventQueue();
      // Not linked yet: iOS can't use the Android address.
      expect(c.read(sensorConnectionProvider), isEmpty);

      await c.read(scanResultsProvider.notifier).startScan();
      await pumpEventQueue();

      expect(c.read(sensorConnectionProvider).map((p) => p.id), [iosHrm.id]);
      final bikes = {for (final b in c.read(bikeProfilesProvider).profiles) b.id: b};
      expect(bikes['road']!.sensorIds, {iosHrm.id});
      expect(bikes['mtb']!.sensorIds, isEmpty);
    });

    test('removing a sensor on one phone removes it on the others', () async {
      final fake = FakeSensorService();
      final c = phone(android: true, service: fake,
          paired: _MemStore([PairedSensor(id: hrm.id, name: hrm.name, kinds: hrm.kinds)]));
      await pumpEventQueue();
      expect(c.read(sensorConnectionProvider), hasLength(1));

      await c.read(sensorCatalogProvider.notifier).replaceFromSync(
          const SensorCatalog().put(KnownSensor(
              name: hrm.name, kinds: hrm.kinds, clock: '000000000000099@x', removed: true)));
      await pumpEventQueue();
      expect(c.read(sensorConnectionProvider), isEmpty);
    });

    test('choosing a bike\'s sensors stores names, keeping ones only another '
        'phone has linked', () async {
      final c = phone(android: false,
          paired: _MemStore([PairedSensor(id: iosHrm.id, name: iosHrm.name, kinds: iosHrm.kinds)]),
          bikes: const BikeProfilesState(
            profiles: [
              BikeProfile(id: 'road', name: 'Road', colorArgb: 1,
                  sensorKeys: {'spd-77'}, sensorsClock: '000000000000001@x'),
            ],
            activeId: 'road',
          ));
      await pumpEventQueue();
      await c.read(sensorConnectionProvider.notifier).setBikeSensors('road', {iosHrm.id});
      final road = c.read(bikeProfilesProvider).active!;
      expect(road.sensorKeys, {'hrm-pro:123456', 'spd-77'});
      expect(road.sensorIds, {iosHrm.id});
      expect(road.sensorsClock!.compareTo('000000000000001@x'), greaterThan(0));
    });

    test('sensors and bike choices from before sync are adopted with the '
        'oldest clock', () async {
      final c = phone(android: true,
          paired: _MemStore([PairedSensor(id: hrm.id, name: hrm.name, kinds: hrm.kinds)]),
          bikes: BikeProfilesState(
            profiles: [
              BikeProfile(id: 'road', name: 'Road', colorArgb: 1, sensorIds: {hrm.id}),
            ],
            activeId: 'road',
          ));
      await pumpEventQueue();
      await pumpEventQueue();
      expect(c.read(sensorCatalogProvider)['hrm-pro:123456']!.address, hrm.id);
      final road = c.read(bikeProfilesProvider).active!;
      expect(road.sensorKeys, {'hrm-pro:123456'});
      expect(road.sensorsClock, startsWith('000000000000000@'));
    });
  });
}
