import 'dart:async';

import 'package:cycle/core/sensors/ble_sensor_service.dart';
import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

/// A fake universal_ble platform that models what the reconnect logic cares
/// about: native GATT clients per device, whether a sensor is in range, and
/// passive autoConnect registrations that link once the sensor comes into
/// range. Like universal_ble on Android, each `connect` opens a client and
/// remembers only the newest one, so `disconnect` releases just that one: a
/// second connect while one is pending leaks the older client.
class FakeBlePlatform extends UniversalBlePlatform {
  final Set<String> inRange = {};
  final Map<String, Set<SensorKind>> kindsOf = {};
  final Map<String, String> systemNames = {};
  final Map<String, int> clients = {};
  final Set<String> linked = {};
  final Set<String> pendingAuto = {};
  final List<({String id, bool auto})> connects = [];
  final Set<String> subscribed = {};
  final Set<String> dropDuringDiscovery = {};
  bool scanning = false;

  int clientsOf(String id) => clients[id] ?? 0;

  void _link(String id) {
    pendingAuto.remove(id);
    linked.add(id);
    clients[id] = 1;
    updateConnection(id, true);
  }

  /// The sensor wakes up / comes back in range.
  void comeIntoRange(String id) {
    inRange.add(id);
    if (pendingAuto.contains(id)) _link(id);
  }

  /// The link drops (out of range / standby). Like Android, the GATT client
  /// of a non-autoConnect link is closed.
  void drop(String id) {
    inRange.remove(id);
    linked.remove(id);
    clients[id] = 0;
    updateConnection(id, false);
  }

  void notify(String id, String charShortId, List<int> bytes) =>
      updateCharacteristicValue(
          id, GattIds.full(charShortId), Uint8List.fromList(bytes), null);

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      AvailabilityState.poweredOn;

  @override
  Future<void> startScan(
      {ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {
    scanning = true;
  }

  @override
  Future<void> stopScan() async => scanning = false;

  @override
  Future<bool> isScanning() async => scanning;

  @override
  Future<void> connect(String deviceId,
      {Duration? connectionTimeout,
      bool autoConnect = false,
      ConnectionPlatformConfig? platformConfig}) async {
    connects.add((id: deviceId, auto: autoConnect));
    clients[deviceId] = clientsOf(deviceId) + 1;
    if (inRange.contains(deviceId)) {
      scheduleMicrotask(() => _link(deviceId));
    } else if (autoConnect) {
      pendingAuto.add(deviceId);
    }
    // A direct connect to an absent sensor just stays pending, like the
    // native request does after Dart's timeout.
  }

  @override
  Future<void> disconnect(String deviceId) async {
    pendingAuto.remove(deviceId);
    if (clientsOf(deviceId) > 0) clients[deviceId] = clientsOf(deviceId) - 1;
    if (linked.remove(deviceId)) updateConnection(deviceId, false);
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      linked.contains(deviceId)
          ? BleConnectionState.connected
          : BleConnectionState.disconnected;

  @override
  Future<List<BleService>> discoverServices(
      String deviceId, bool withDescriptors) async {
    if (dropDuringDiscovery.remove(deviceId)) {
      drop(deviceId);
      inRange.add(deviceId); // still around: only the link went
      throw Exception('link dropped during discovery');
    }
    return [
        for (final kind in kindsOf[deviceId] ?? const <SensorKind>{})
          BleService(GattIds.full(kind.serviceId), [
            BleCharacteristic(GattIds.full(kind.measurementId),
                [CharacteristicProperty.notify], []),
          ]),
    ];
  }

  @override
  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty bleInputProperty) async {
    subscribed.add('$deviceId/$characteristic');
  }

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async =>
      [
        for (final id in linked)
          BleDevice(deviceId: id, name: systemNames[id]),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const hr = 'AA:00:00:00:00:01';
const cadence = 'AA:00:00:00:00:02';

void main() {
  late FakeBlePlatform ble;
  late BleSensorService service;
  late List<List<ConnectedSensor>> connectedEvents;
  late List<SensorSnapshot> snapshots;

  // Real time, short waits: the direct-connect timeout is 50 ms in tests.
  Future<void> settle([int ms = 150]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  ConnectedSensor? sensor(String id) {
    if (connectedEvents.isEmpty) return null;
    for (final s in connectedEvents.last) {
      if (s.id == id) return s;
    }
    return null;
  }

  setUp(() {
    BleSensorService.directConnectTimeout = const Duration(milliseconds: 50);
    ble = FakeBlePlatform()
      ..kindsOf[hr] = {SensorKind.heartRate}
      ..kindsOf[cadence] = {SensorKind.speedCadence};
    UniversalBle.setInstance(ble);
    service = BleSensorService();
    connectedEvents = [];
    snapshots = [];
    service.connectedSensors().listen(connectedEvents.add);
    service.snapshots().listen(snapshots.add);
  });

  // Stops the retry timer so it can't leak into the next test.
  tearDown(() => service.suspendConnections());

  test('a sensor in range links by direct connect, without scanning',
      () async {
    ble.inRange.add(hr);
    await service.connect(hr);
    await settle();

    expect(ble.connects.first, (id: hr, auto: false));
    expect(ble.scanning, isFalse);
    expect(sensor(hr)!.connected, isTrue);
    expect(sensor(hr)!.kinds, {SensorKind.heartRate});
    expect(ble.subscribed, contains('$hr/${GattIds.full('2a37')}'));

    ble.notify(hr, GattIds.heartRateMeasurement, [0x00, 140]);
    await settle(20);
    expect(snapshots.last.heartRate, 140);
  });

  test('an absent sensor falls back to ONE passive autoConnect registration',
      () async {
    await service.connect(hr);
    await settle();

    expect(ble.connects.map((c) => c.auto), [false, true]);
    // The timed-out direct attempt was cancelled first: one client, not two.
    expect(ble.clientsOf(hr), 1);
    expect(sensor(hr)!.connected, isFalse);
    expect(sensor(hr)!.reconnecting, isTrue);

    ble.comeIntoRange(hr); // the OS links it via autoConnect
    await settle();
    expect(sensor(hr)!.connected, isTrue);
  });

  test('retry ticks never pile up GATT clients next to a pending autoConnect',
      () async {
    await service.connect(hr);
    await settle();
    for (var i = 0; i < 3; i++) {
      await service.retryConnections();
      await settle();
      expect(ble.clientsOf(hr), 1, reason: 'after retry ${i + 1}');
    }
  });

  test('suspending releases every client, including an attempt in flight',
      () async {
    ble.inRange.add(cadence);
    await service.connect(cadence); // links
    await service.connect(hr); // absent: direct attempt still in flight
    await settle(10);
    await service.suspendConnections();
    await settle();

    expect(ble.clientsOf(hr), 0);
    expect(ble.clientsOf(cadence), 0);
    // The in-flight attempt timed out after the suspension and must not
    // re-register autoConnect behind its back.
    expect(ble.connects.where((c) => c.id == hr && c.auto), isEmpty);
    expect(connectedEvents.last, isEmpty);
  });

  test('resuming reconnects the targets that were active', () async {
    ble.inRange.add(hr);
    await service.connect(hr);
    await settle();
    await service.suspendConnections();
    await settle();
    expect(sensor(hr), isNull);

    await service.resumeConnections();
    await settle();
    expect(sensor(hr)!.connected, isTrue);
  });

  test('resuming starts ONE direct attempt per sensor, not two', () async {
    // resumeConnections() connects each target and then runs a retry tick at
    // once; on the A33 that opened two GATT clients to the same HR strap.
    await service.connect(hr); // absent: ends up on autoConnect
    await settle();
    await service.suspendConnections();
    await settle();
    ble.connects.clear();

    await service.resumeConnections();
    await settle(10); // both would have started within the same few ms
    expect(ble.connects.where((c) => c.id == hr && !c.auto), hasLength(1));
  });

  test('a link that drops during service discovery falls back to autoConnect',
      () async {
    // Seen on the A33 right after reinstalling: the strap linked in 80 ms,
    // then Android tore that link down mid-discovery; the direct attempt had
    // already succeeded, so nothing was left pending for the sensor.
    ble.inRange.add(hr);
    ble.dropDuringDiscovery.add(hr);
    await service.connect(hr);
    await settle();

    expect(ble.connects.last, (id: hr, auto: true));
    expect(sensor(hr)!.connected, isTrue); // relinked by autoConnect
  });

  test('a resume arriving with an unfinished suspension still reconnects',
      () async {
    // iPhone: frozen at the lock, the app ran both on unlock. The teardown
    // cancelled the connection the resume had just started.
    ble.inRange.add(hr);
    await service.connect(hr);
    await settle();

    final suspended = service.suspendConnections(); // not awaited, like the gate
    final resumed = service.resumeConnections();
    await Future.wait([suspended, resumed]);
    await settle();

    expect(sensor(hr)!.connected, isTrue);
    expect(ble.clientsOf(hr), 1);
  });

  test('iOS: retry ticks leave a pending connect alone', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await service.connect(hr); // absent: falls back to a pending autoConnect
    await settle();
    final before = ble.connects.length;

    for (var i = 0; i < 3; i++) {
      await service.retryConnections();
      await settle();
    }
    expect(ble.connects.length, before); // no cancel-and-reissue churn
    expect(ble.pendingAuto, contains(hr));

    ble.comeIntoRange(hr);
    await settle();
    expect(sensor(hr)!.connected, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  test('a mid-ride drop clears the value and registers autoConnect', () async {
    ble.inRange.add(hr);
    await service.connect(hr);
    await settle();
    ble.notify(hr, GattIds.heartRateMeasurement, [0x00, 150]);
    await settle(20);
    expect(snapshots.last.heartRate, 150);

    ble.drop(hr);
    await settle();
    expect(snapshots.last.heartRate, isNull);
    expect(sensor(hr)!.connected, isFalse);
    expect(ble.connects.last, (id: hr, auto: true));
    expect(ble.clientsOf(hr), 1);

    ble.comeIntoRange(hr);
    await settle();
    expect(sensor(hr)!.connected, isTrue);
  });

  test('switching bikes drops sensors that are out of scope', () async {
    ble.inRange.addAll([hr, cadence]);
    await service.setActiveTargets({hr, cadence});
    await settle();
    expect(connectedEvents.last.map((s) => s.id).toSet(), {hr, cadence});

    await service.setActiveTargets({hr});
    await settle();
    expect(connectedEvents.last.map((s) => s.id).toSet(), {hr});
    expect(ble.clientsOf(cadence), 0);
  });

  test('a sensor linked without a scan gets its name from the system list',
      () async {
    ble.inRange.add(hr);
    ble.systemNames[hr] = 'HRM-Pro:123456';
    await service.connect(hr);
    await settle();
    expect(sensor(hr)!.name, 'HRM-Pro:123456');
  });

  group('scan', () {
    test('reports cycling sensors with their kinds and names, then ends',
        () async {
      final results = <List<DiscoveredSensor>>[];
      final done = Completer<void>();
      service
          .scan(timeout: const Duration(milliseconds: 100))
          .listen(results.add, onDone: done.complete);
      await settle(10);
      expect(ble.scanning, isTrue);

      ble.updateScanResult(BleDevice(
          deviceId: cadence,
          name: 'CADENCE-42',
          services: [GattIds.full(GattIds.cscService)]));
      ble.updateScanResult(BleDevice(
          deviceId: 'BB:00:00:00:00:09',
          name: 'Headphones',
          services: ['0000110b-0000-1000-8000-00805f9b34fb']));
      await done.future.timeout(const Duration(seconds: 2));

      expect(ble.scanning, isFalse);
      expect(results.last.single.id, cadence);
      expect(results.last.single.name, 'CADENCE-42');
      expect(results.last.single.kinds, {SensorKind.speedCadence});

      // The scanned name is remembered for the connection.
      ble.inRange.add(cadence);
      await service.connect(cadence);
      await settle();
      expect(sensor(cadence)!.name, 'CADENCE-42');
    });

    test('stopScan ends a running scan early', () async {
      final done = Completer<void>();
      service.scan().listen((_) {}, onDone: done.complete);
      await settle(10);
      await service.stopScan();
      await done.future.timeout(const Duration(seconds: 1));
      expect(ble.scanning, isFalse);
    });
  });
}
