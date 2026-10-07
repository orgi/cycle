import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'csc_calculator.dart';
import 'gatt.dart';
import 'gatt_parsers.dart';
import 'sensor_service.dart';
import 'sensor_snapshot_merger.dart';

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

  // Per-device readings, merged across linked sensors only — see
  // SensorSnapshotMerger for why one global snapshot leaked stale values.
  final SensorSnapshotMerger _merger = SensorSnapshotMerger();
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

  /// What *should* be pursued, independent of whether we're currently
  /// suspended. [suspendConnections] tears down the live links but keeps this,
  /// so [resumeConnections] can restore exactly what was there — and a bike
  /// switch while suspended updates the plan without waking the radio.
  final Set<String> _desiredTargets = {};
  bool _suspended = false;

  // Bounded direct-connect retry window (no scanning). Re-armed on startup and
  // on ride start; ticks periodically to direct-connect any target that isn't
  // linked yet, and stops at the deadline or once all targets are connected.
  Timer? _retryTimer;
  DateTime? _retryDeadline;
  static const _retryWindow = Duration(minutes: 5);
  static const _retryInterval = Duration(seconds: 30);

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
    _desiredTargets.add(deviceId);
    if (_suspended) return; // recorded; restored by resumeConnections()
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
    // One-shot DIRECT connect (not passive autoConnect): a direct connect links
    // fast when the sensor is advertising — which a worn HR strap / a spinning
    // cadence sensor is — whereas passive `autoConnect=true` frequently just
    // never links a present sensor (confirmed on-device: the app registered
    // autoConnect for a worn HR sensor and it stayed disconnected). Crucially a
    // direct connect does NOT scan, so — unlike the removed active-scan retry
    // loop — it doesn't compete with the GPS radio. If the sensor isn't
    // reachable right now it falls back to passive autoConnect for later. This
    // is the same path the manual reconnect tap uses (which works).
    unawaited(_attemptDirectConnect(deviceId));
    _armRetryWindow();
  }

  @override
  Future<void> retryConnections() async => _armRetryWindow(immediate: true);

  /// (Re)arm the bounded direct-connect retry window. [immediate] runs a tick
  /// right away (used when a ride starts) instead of waiting for the interval.
  void _armRetryWindow({bool immediate = false}) {
    _retryDeadline = DateTime.now().add(_retryWindow);
    _retryTimer ??= Timer.periodic(_retryInterval, (_) => _retryTick());
    if (immediate) _retryTick();
  }

  void _retryTick() {
    final missing =
        _targets.where((id) => _connected[id]?.connected != true).toList();
    if (missing.isEmpty ||
        _retryDeadline == null ||
        DateTime.now().isAfter(_retryDeadline!)) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryDeadline = null;
      return;
    }
    for (final id in missing) {
      unawaited(_attemptDirectConnect(id));
    }
  }

  /// One-shot direct connect with a passive-autoConnect fallback. No scanning,
  /// so GPS-safe. Shared by initial connect, [reconnect], the retry window, and
  /// post-drop recovery.
  Future<void> _attemptDirectConnect(String deviceId) async {
    if (_suspended || !_targets.contains(deviceId)) return;
    _ensureConnSub(deviceId);
    try {
      await BluetoothDevice.fromId(deviceId).connect(
        license: License.nonprofit,
        autoConnect: false,
        mtu: 512,
        timeout: const Duration(seconds: 12),
      );
    } catch (_) {
      // Asleep / out of range — register passive autoConnect so it links when
      // it next advertises (quiet on the radio, no scan). Unless we were
      // suspended (or the target dropped) while this 12s attempt was in
      // flight: re-registering here would quietly re-create the very
      // registration the suspension just tore down, and nothing would clear it
      // until the app next came to the foreground.
      if (_suspended || !_targets.contains(deviceId)) return;
      await _registerAutoConnect(deviceId);
    }
  }

  @override
  Future<void> disconnect(String deviceId) {
    // Deliberate unpair/deselect — forget it, unlike a suspend teardown which
    // keeps the target so it comes back on resume.
    _desiredTargets.remove(deviceId);
    return _removeTarget(deviceId);
  }

  @override
  Future<void> reconnect(String deviceId) async {
    if (!_targets.contains(deviceId)) return;
    final device = BluetoothDevice.fromId(deviceId);
    _ensureConnSub(deviceId);
    // Mark as being worked on so the UI can show "reconnecting…".
    final existing = _connected[deviceId];
    if (existing != null && !existing.connected) {
      _connected[deviceId] = ConnectedSensor(
        id: existing.id,
        name: existing.name,
        kinds: existing.kinds,
        connected: false,
        reconnecting: true,
      );
      _emitConnected();
    }
    // Clear any half-open link + its autoConnect so the direct attempt is clean.
    _autoConnectRegistered.remove(deviceId);
    try {
      await device.disconnect();
    } catch (_) {}
    await _attemptDirectConnect(deviceId);
  }

  @override
  Future<void> setActiveTargets(Set<String> ids) async {
    _desiredTargets
      ..clear()
      ..addAll(ids);
    // Suspended: record the plan only. Waking the radio to apply a target set
    // nothing is listening to is exactly the drain the suspension exists to
    // avoid; resumeConnections() applies it.
    if (_suspended) return;
    for (final id in _targets.difference(ids).toList()) {
      await _removeTarget(id);
    }
    for (final id in ids.difference(_targets).toList()) {
      await connect(id);
    }
  }

  @override
  Future<void> suspendConnections() async {
    if (_suspended) return;
    _suspended = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryDeadline = null;
    // Tear down every live link + pending autoConnect registration. The
    // desired set is untouched, so resumeConnections() puts it all back.
    for (final id in _targets.toList()) {
      await _removeTarget(id);
    }
  }

  @override
  Future<void> resumeConnections() async {
    if (!_suspended) return;
    _suspended = false;
    if (_desiredTargets.isEmpty) return;
    for (final id in _desiredTargets) {
      await connect(id);
    }
    _armRetryWindow(immediate: true);
  }

  void _ensureConnSub(String deviceId) {
    if (_connSubs.containsKey(deviceId)) return;
    final device = BluetoothDevice.fromId(deviceId);
    _connSubs[deviceId] = device.connectionState.listen((st) {
      if (st == BluetoothConnectionState.connected) {
        unawaited(_onConnected(device, deviceId));
      } else if (st == BluetoothConnectionState.disconnected) {
        _onDisconnected(deviceId);
        // Mid-ride drop of an active target: register passive autoConnect so
        // the OS re-links it when it reappears. Passive (no scan) so it stays
        // quiet on the radio and doesn't disturb GPS; a direct-connect retry
        // here could fight a brief out-of-range blip. The user can also tap the
        // stat to force a direct reconnect.
        if (_targets.contains(deviceId)) {
          unawaited(_registerAutoConnect(deviceId));
        }
      }
    });
  }

  /// Registers Android's native autoConnect for [deviceId]: the OS re-links
  /// whenever the sensor next advertises (wakes / back in range), with no
  /// app-level scanning — quiet on the radio, so it doesn't fight the GPS.
  Future<void> _registerAutoConnect(String deviceId) async {
    if (_suspended || !_targets.contains(deviceId)) return;
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
    // A connect that landed after we suspended (or after the target was
    // dropped): let it go rather than wiring up subscriptions nothing reads.
    if (_suspended || !_targets.contains(deviceId)) {
      try {
        await device.disconnect();
      } catch (_) {}
      return;
    }
    try {
      _autoConnectRegistered.remove(deviceId);
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
    _clearReadings(deviceId);
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
    await _connSubs.remove(deviceId)?.cancel();
    for (final s in _subs.remove(deviceId) ?? const <StreamSubscription>[]) {
      await s.cancel();
    }
    _csc.remove(deviceId);
    _clearReadings(deviceId);
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
    final reading = switch (kind) {
      SensorKind.heartRate =>
        SensorSnapshot(heartRate: GattParsers.parseHeartRate(data).bpm),
      SensorKind.speedCadence => () {
          final result = _csc[deviceId]!.update(GattParsers.parseCsc(data));
          return SensorSnapshot(
            wheelSpeedMps: result.speedMetersPerSecond,
            cadenceRpm: result.cadenceRpm,
          );
        }(),
      SensorKind.power =>
        SensorSnapshot(power: GattParsers.parsePower(data).watts),
    };
    _snapshots.add(_merger.update(deviceId, reading));
  }

  /// Forgets everything [deviceId] contributed and tells listeners, so the
  /// dashboard falls back to "—" and the next recorded point doesn't inherit a
  /// value from a sensor that's no longer there.
  void _clearReadings(String deviceId) {
    if (_merger.remove(deviceId)) _snapshots.add(_merger.merged);
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
