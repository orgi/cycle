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
///
/// Reconnection is driven by our own scan-and-connect retry loop, not by
/// Android's native `autoConnect=true` GATT mode alone: that mode is a
/// low-priority background op, and on real devices it was observed to be
/// wildly non-deterministic with 2-3 sensors registered at once — one sensor
/// reconnecting instantly while another sat for 20+ minutes with no error, no
/// timeout, and no way to tell "still trying" from "stuck". Instead, for every
/// active target we do a short *targeted* active scan (`withRemoteIds`) and
/// connect the moment it's seen, retrying on a backoff if it isn't found,
/// while also registering the passive `autoConnect=true` link as a low-cost
/// backstop in case active scanning is paused.
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
  // cycles so the retry loop doesn't need to re-wire anything).
  final Map<String, StreamSubscription<dynamic>> _connSubs = {};
  double _wheelCircumferenceMeters = 2.105;

  /// Device ids we're actively pursuing right now (the active bike profile's
  /// allow-listed paired sensors). A sensor that's paired but out of scope
  /// for the current bike simply isn't in here — its pairing is remembered
  /// by the caller, not by this service.
  final Set<String> _targets = {};
  final Set<String> _autoConnectRegistered = {};
  // Targets that have connected at least once this session. A drop of one of
  // these is handled by passive autoConnect only — we do NOT re-arm the active
  // scan loop for it. Sustained active BLE scanning competes with GNSS for the
  // radio on combined Wi-Fi/BT/GPS chips (degrades the GPS fix mid-ride), and
  // the reliability problem the active scan solves — a sensor that never links
  // at all — only happens before the first connect. So active scanning is
  // bounded to the pre-first-connect phase; after that it's passive, like the
  // original implementation, keeping the GPS fix clean during a ride.
  final Set<String> _everConnected = {};
  bool _retryLoopRunning = false;
  int _consecutiveEmptyRounds = 0;

  static const _scanWindow = Duration(seconds: 8);
  static const _backoffSteps = [
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 60),
  ];

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
    _targets.add(deviceId);
    _connected[deviceId] ??= ConnectedSensor(
      id: deviceId,
      name: _nameOf(BluetoothDevice.fromId(deviceId)),
      kinds: const {},
      connected: false,
      reconnecting: true,
    );
    _emitConnected();
    _ensureConnSub(deviceId);
    _kickRetryLoop();
  }

  @override
  Future<void> disconnect(String deviceId) => _removeTarget(deviceId);

  @override
  Future<void> setActiveTargets(Set<String> ids) async {
    for (final id in _targets.difference(ids).toList()) {
      await _removeTarget(id);
    }
    for (final id in ids.difference(_targets).toList()) {
      await connect(id);
    }
  }

  void _ensureConnSub(String deviceId) {
    if (_connSubs.containsKey(deviceId)) return;
    final device = BluetoothDevice.fromId(deviceId);
    _connSubs[deviceId] = device.connectionState.listen((st) {
      if (st == BluetoothConnectionState.connected) {
        unawaited(_onConnected(device, deviceId));
      } else if (st == BluetoothConnectionState.disconnected) {
        _onDisconnected(deviceId);
        if (_targets.contains(deviceId)) _kickRetryLoop();
      }
    });
  }

  void _kickRetryLoop() {
    if (_retryLoopRunning) return;
    unawaited(_retryLoop());
  }

  /// Actively scans for targets that have never connected yet, connecting each
  /// the instant it's seen; backs off between rounds. Registers a passive
  /// autoConnect backstop for every disconnected target (including
  /// previously-connected ones), but does NOT actively scan for a target that
  /// has already connected once — that's left to passive autoConnect so the
  /// active radio is quiet during a ride (see [_everConnected]). Ends once no
  /// never-connected target remains.
  Future<void> _retryLoop() async {
    _retryLoopRunning = true;
    try {
      while (true) {
        // Passive backstop for anything disconnected — cheap, no radio scan.
        for (final id in _missingTargets()) {
          unawaited(_registerAutoConnect(id));
        }
        final toScan = _scanTargets();
        if (toScan.isEmpty) return;
        await _scanRound(toScan);
        if (_scanTargets().isEmpty) return;
        final step = _backoffSteps[
            _consecutiveEmptyRounds.clamp(0, _backoffSteps.length - 1)];
        _consecutiveEmptyRounds++;
        await Future<void>.delayed(step);
      }
    } finally {
      _retryLoopRunning = false;
      _consecutiveEmptyRounds = 0;
    }
  }

  Set<String> _missingTargets() =>
      _targets.where((id) => _connected[id]?.connected != true).toSet();

  /// Disconnected targets that warrant an *active* scan: only those never yet
  /// connected this session. Once connected, a later drop relies on passive
  /// autoConnect instead, to keep active scanning off the radio during a ride.
  Set<String> _scanTargets() =>
      _missingTargets().where((id) => !_everConnected.contains(id)).toSet();

  Future<void> _scanRound(Set<String> missing) async {
    final found = <String>{};
    late final StreamSubscription<List<ScanResult>> sub;
    sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        if (!missing.contains(id)) continue;
        // Record the advertised kinds even if we never manage to fully
        // connect: merely being seen tells us what the sensor *is*, which is
        // all a dashboard tile's visibility needs.
        _noteAdvertisedKinds(id, _nameOf(r.device),
            _kindsFromServices(r.advertisementData.serviceUuids));
        if (found.add(id)) {
          unawaited(_directConnect(r.device, id));
        }
      }
    });
    try {
      // Filter by our known cycling services (the same filter [scan] uses for
      // manual pairing, and proven to work) and match the target ids
      // ourselves in Dart above, rather than the native `withRemoteIds`
      // device-address filter — that path is far less exercised and, unlike
      // the service filter, isn't what's already known-good for pairing.
      // lowPower (not the default lowLatency): an aggressive scan competes
      // for radio time with an already-connected sensor's notifications —
      // e.g. HR data visibly stalling while this loop keeps hunting for a
      // still-missing cadence/power sensor. We're a background retry, not a
      // user-initiated one-shot scan, so it's fine for this to take longer.
      await FlutterBluePlus.startScan(
        withServices: _serviceGuids,
        timeout: _scanWindow,
        androidScanMode: AndroidScanMode.lowPower,
      );
      await Future<void>.delayed(_scanWindow);
    } catch (_) {
      // Scan failure (adapter off, etc.) — the next round/backstop retries.
    } finally {
      await sub.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  /// Merge kinds learned from a scan advertisement into the sensor's known
  /// entry and emit, so listeners (and thus the paired-sensor store) pick up
  /// the sensor's type without needing a full GATT connection.
  void _noteAdvertisedKinds(
      String deviceId, String name, Set<SensorKind> kinds) {
    if (kinds.isEmpty) return;
    final existing = _connected[deviceId];
    final merged = existing == null ? kinds : {...existing.kinds, ...kinds};
    if (existing != null && merged.length == existing.kinds.length) {
      return; // nothing new
    }
    _connected[deviceId] = ConnectedSensor(
      id: deviceId,
      name: (existing?.name.isNotEmpty ?? false) ? existing!.name : name,
      kinds: merged,
      connected: existing?.connected ?? false,
      reconnecting: existing?.reconnecting ?? _targets.contains(deviceId),
    );
    _emitConnected();
  }

  Future<void> _directConnect(BluetoothDevice device, String deviceId) async {
    _ensureConnSub(deviceId);
    try {
      await device.connect(
        license: License.nonprofit,
        autoConnect: false,
        mtu: 512,
        timeout: _scanWindow,
      );
    } catch (_) {
      // Left for the next scan round / autoConnect backstop to retry.
    }
  }

  /// Cheap, passive backstop while we're between active scan rounds: Android
  /// reconnects opportunistically if the sensor happens to reappear.
  Future<void> _registerAutoConnect(String deviceId) async {
    if (_autoConnectRegistered.contains(deviceId)) return;
    _autoConnectRegistered.add(deviceId);
    _ensureConnSub(deviceId);
    try {
      await BluetoothDevice.fromId(deviceId)
          .connect(license: License.nonprofit, autoConnect: true, mtu: null);
    } catch (_) {}
  }

  /// Discover services + subscribe to measurements after a (re)connect.
  Future<void> _onConnected(BluetoothDevice device, String deviceId) async {
    try {
      _autoConnectRegistered.remove(deviceId);
      // Mark it linked at least once this session: from here on a drop is
      // handled by passive autoConnect, not a fresh active scan (see
      // [_everConnected]).
      _everConnected.add(deviceId);
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
      // A quick re-drop can race discovery; the retry loop/next event retries.
    }
  }

  /// A drop (sensor out of range / standby). Keep it as a target so the retry
  /// loop re-establishes it; just tear down the live subscriptions and mark
  /// it offline.
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
        connected: false,
        reconnecting: _targets.contains(deviceId),
      );
      _emitConnected();
    }
  }

  /// Stops pursuing [deviceId]: tears down the live connection/subscriptions
  /// and forgets its live status. Used both for a user-initiated unpair and
  /// for a bike-profile switch taking a sensor out of scope — the caller
  /// decides which of those it is and whether the pairing itself is kept.
  Future<void> _removeTarget(String deviceId) async {
    _targets.remove(deviceId);
    _autoConnectRegistered.remove(deviceId);
    _everConnected.remove(deviceId);
    await _connSubs.remove(deviceId)?.cancel();
    for (final s in _subs.remove(deviceId) ?? const <StreamSubscription>[]) {
      await s.cancel();
    }
    _csc.remove(deviceId);
    _connected.remove(deviceId);
    _emitConnected();
    try {
      await BluetoothDevice.fromId(deviceId).disconnect();
    } catch (_) {}
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
