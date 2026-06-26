import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'csc_calculator.dart';
import 'gatt.dart';
import 'gatt_parsers.dart';
import 'sensor_service.dart';

/// Real [SensorService] backed by flutter_blue_plus. Scans for the standard
/// cycling GATT services, connects, subscribes to the measurement
/// characteristics and feeds the (separately unit-tested) parsers + CSC
/// calculator. Hardware-verified on a physical device (emulators have no BLE).
class BleSensorService implements SensorService {
  final StreamController<SensorSnapshot> _snapshots =
      StreamController<SensorSnapshot>.broadcast();
  final StreamController<List<ConnectedSensor>> _connectedCtrl =
      StreamController<List<ConnectedSensor>>.broadcast();

  SensorSnapshot _snapshot = const SensorSnapshot();
  final Map<String, ConnectedSensor> _connected = {};
  final Map<String, CscCalculator> _csc = {};
  final Map<String, List<StreamSubscription<dynamic>>> _subs = {};
  // Persistent per-device connection-state listeners (survive drop/reconnect
  // cycles so autoConnect can re-establish without re-pairing).
  final Map<String, StreamSubscription<dynamic>> _connSubs = {};
  double _wheelCircumferenceMeters = 2.105;

  @override
  void setWheelCircumference(double meters) {
    if (meters > 0) _wheelCircumferenceMeters = meters;
  }

  static final List<Guid> _serviceGuids = [
    Guid(GattIds.full(GattIds.heartRateService)),
    Guid(GattIds.full(GattIds.cscService)),
    Guid(GattIds.full(GattIds.cyclingPowerService)),
  ];

  @override
  Future<bool> ensureReady() async {
    try {
      if (!await FlutterBluePlus.isSupported) return false;
      final state = await FlutterBluePlus.adapterState
          .firstWhere((s) => s != BluetoothAdapterState.unknown)
          .timeout(const Duration(seconds: 4),
              onTimeout: () => BluetoothAdapterState.unknown);
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<List<DiscoveredSensor>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async* {
    final found = <String, DiscoveredSensor>{};
    await FlutterBluePlus.startScan(
        withServices: _serviceGuids, timeout: timeout);
    await for (final results in FlutterBluePlus.onScanResults) {
      for (final r in results) {
        final kinds = _kindsFromServices(r.advertisementData.serviceUuids);
        if (kinds.isEmpty) continue;
        found[r.device.remoteId.str] = DiscoveredSensor(
          id: r.device.remoteId.str,
          name: _nameOf(r.device),
          kinds: kinds,
        );
      }
      yield found.values.toList();
    }
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<void> connect(String deviceId, {bool autoConnect = false}) async {
    final device = BluetoothDevice.fromId(deviceId);
    // Keep ONE persistent connection-state listener per device: it discovers
    // services on every (re)connect and tears down on every drop. With
    // [autoConnect] the OS re-establishes the link whenever the sensor reappears
    // (wakes from standby / back in range) — that's how auto-reconnect survives
    // a sensor that was idle too long. License.nonprofit covers personal/OSS use.
    await _connSubs[deviceId]?.cancel();
    _connSubs[deviceId] = device.connectionState.listen((st) {
      if (st == BluetoothConnectionState.connected) {
        unawaited(_onConnected(device, deviceId));
      } else if (st == BluetoothConnectionState.disconnected) {
        _onDisconnected(deviceId);
      }
    });
    // List the sensor immediately (as not-yet-connected) so the UI shows it.
    _connected[deviceId] ??= ConnectedSensor(
        id: deviceId, name: _nameOf(device), kinds: const {}, connected: false);
    _emitConnected();
    await device.connect(
      license: License.nonprofit,
      autoConnect: autoConnect,
      mtu: autoConnect ? null : 512,
    );
  }

  /// Discover services + subscribe to measurements after a (re)connect.
  Future<void> _onConnected(BluetoothDevice device, String deviceId) async {
    try {
      final services = await device.discoverServices();
      for (final s in _subs[deviceId] ?? const <StreamSubscription>[]) {
        await s.cancel(); // drop any stale subs from a previous connection
      }
      final subs = <StreamSubscription<dynamic>>[];
      final kinds = <SensorKind>{};
      for (final service in services) {
        final serviceUuid = service.uuid.toString().toLowerCase();
        for (final kind in SensorKind.values) {
          if (!serviceUuid.contains(kind.serviceId)) continue;
          kinds.add(kind);
          for (final char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(kind.measurementId)) {
              await char.setNotifyValue(true);
              subs.add(char.onValueReceived
                  .listen((data) => _onData(deviceId, kind, data)));
            }
          }
        }
      }
      _subs[deviceId] = subs;
      _csc[deviceId] =
          CscCalculator(wheelCircumferenceMeters: _wheelCircumferenceMeters);
      _connected[deviceId] = ConnectedSensor(
          id: deviceId, name: _nameOf(device), kinds: kinds, connected: true);
      _emitConnected();
    } catch (_) {
      // A quick re-drop can race discovery; the next connected event retries.
    }
  }

  /// A drop (sensor out of range / standby). Keep the pairing so autoConnect can
  /// re-establish it; just tear down the live subscriptions and mark it offline.
  void _onDisconnected(String deviceId) {
    for (final s in _subs[deviceId] ?? const <StreamSubscription>[]) {
      unawaited(s.cancel());
    }
    _subs.remove(deviceId);
    _csc.remove(deviceId);
    final existing = _connected[deviceId];
    if (existing != null) {
      _connected[deviceId] = ConnectedSensor(
          id: existing.id,
          name: existing.name,
          kinds: existing.kinds,
          connected: false);
      _emitConnected();
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    // User-initiated: stop autoConnect and forget the device entirely.
    await _connSubs[deviceId]?.cancel();
    _connSubs.remove(deviceId);
    for (final s in _subs[deviceId] ?? const <StreamSubscription>[]) {
      await s.cancel();
    }
    _subs.remove(deviceId);
    _csc.remove(deviceId);
    _connected.remove(deviceId);
    _emitConnected();
    await BluetoothDevice.fromId(deviceId).disconnect();
  }

  @override
  Stream<List<ConnectedSensor>> connectedSensors() => _connectedCtrl.stream;

  @override
  Stream<SensorSnapshot> snapshots() => _snapshots.stream;

  void _onData(String deviceId, SensorKind kind, List<int> data) {
    if (data.isEmpty) return;
    switch (kind) {
      case SensorKind.heartRate:
        _snapshot = _snapshot.copyWith(
            heartRate: GattParsers.parseHeartRate(data).bpm);
      case SensorKind.speedCadence:
        final result = _csc[deviceId]!.update(GattParsers.parseCsc(data));
        _snapshot = _snapshot.copyWith(
          wheelSpeedMps: result.speedMetersPerSecond,
          cadenceRpm: result.cadenceRpm,
        );
      case SensorKind.power:
        _snapshot =
            _snapshot.copyWith(power: GattParsers.parsePower(data).watts);
    }
    _snapshots.add(_snapshot);
  }

  Set<SensorKind> _kindsFromServices(List<Guid> serviceUuids) {
    final uuids = serviceUuids.map((g) => g.toString().toLowerCase()).toList();
    return {
      for (final kind in SensorKind.values)
        if (uuids.any((u) => u.contains(kind.serviceId))) kind,
    };
  }

  String _nameOf(BluetoothDevice device) {
    if (device.platformName.isNotEmpty) return device.platformName;
    if (device.advName.isNotEmpty) return device.advName;
    return 'Unknown sensor';
  }

  void _emitConnected() => _connectedCtrl.add(_connected.values.toList());
}
