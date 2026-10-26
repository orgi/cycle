import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'csc_calculator.dart';
import 'gatt.dart';
import 'gatt_parsers.dart';
import 'sensor_service.dart';
import 'sensor_snapshot_merger.dart';

/// Real [SensorService] backed by universal_ble (BSD-3). Connects to the
/// standard cycling GATT services, subscribes to their measurement
/// characteristics and feeds the (separately unit-tested) parsers + CSC
/// calculator. Hardware-verified on a physical device (emulators have no BLE);
/// the connection logic itself is unit-tested against a fake platform
/// (`UniversalBle.setInstance`).
///
/// **Reconnection never scans.** A target is linked with a one-shot *direct*
/// connect by its saved id; if the sensor isn't reachable, a passive
/// `autoConnect` registration lets the OS link it when it next advertises.
/// Neither competes with the GPS on a shared radio, unlike the app-level scan
/// loop this replaced (see CLAUDE.md, BLE sensors). A bounded retry window
/// re-tries direct connects for a few minutes after startup and ride start.
///
/// Two universal_ble specifics shape this class:
/// * A connect's `timeout` only bounds how long *Dart* waits; the native
///   request keeps going. So a direct attempt that timed out is cancelled with
///   [UniversalBle.disconnect] before falling back to autoConnect, and a pending
///   autoConnect is cancelled before the next direct attempt — otherwise each
///   retry would leave another GATT client registered.
/// * Device names only arrive with scan results, so they're cached from scans;
///   a sensor linked without a scan this session gets its name from the
///   system's connected-device list.
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
  // cycles so the retry window doesn't need to re-wire anything).
  final Map<String, StreamSubscription<bool>> _connSubs = {};
  final Map<String, String> _names = {};
  double _wheelCircumferenceMeters = 2.105;

  /// Device ids we're actively pursuing right now (the active bike profile's
  /// allow-listed paired sensors). A sensor that's paired but out of scope
  /// for the current bike simply isn't in here — its pairing is remembered
  /// by the caller, not by this service.
  final Set<String> _targets = {};
  final Set<String> _autoConnectRegistered = {};

  /// Devices with a direct connect in progress. [resumeConnections] starts one
  /// through [connect] and then runs a retry tick at once, which would start a
  /// second: two native connects to one sensor, two GATT clients (only the
  /// newer one tracked by universal_ble), subscriptions wired twice. Seen on
  /// the A33 on the first resume after backgrounding.
  final Set<String> _directInFlight = {};

  /// Devices whose link is up at the radio level: set on the connection
  /// event, before service discovery. A sensor counts as linked in [_connected]
  /// only once discovery finished, so a link that drops *during* discovery
  /// would otherwise look like a failed attempt and leave nothing pending.
  final Set<String> _linkUp = {};

  /// What *should* be pursued, independent of whether we're currently
  /// suspended. [suspendConnections] tears down the live links but keeps this,
  /// so [resumeConnections] can restore exactly what was there — and a bike
  /// switch while suspended updates the plan without waking the radio.
  final Set<String> _desiredTargets = {};
  bool _suspended = false;

  /// Suspend/resume run one after the other, never interleaved. The power gate
  /// fires them without awaiting, and on iOS (no grace period, the app frozen
  /// at the lock) both arrive together on unlock: the suspension's teardown,
  /// still awaiting, then removed the target and cancelled the connection the
  /// resume had just started, leaving the sensor unpursued. Seen on the iPhone.
  Future<void> _transition = Future<void>.value();

  // Bounded direct-connect retry window (no scanning). Re-armed on startup and
  // on ride start; ticks periodically to direct-connect any target that isn't
  // linked yet, and stops at the deadline or once all targets are connected.
  Timer? _retryTimer;
  DateTime? _retryDeadline;
  static const _retryWindow = Duration(minutes: 5);
  static const _retryInterval = Duration(seconds: 30);

  /// iOS: a CoreBluetooth connect never times out, so a pending (auto)connect
  /// already waits for the sensor indefinitely. Cancelling it to issue a
  /// "direct" one — needed on Android, where a direct connect gives up after
  /// ~30 s and autoConnect is a separate, slow mode — only restarts that wait;
  /// the iPhone log showed it every 12-18 s until the strap linked.
  static bool get _pendingConnectWaits =>
      defaultTargetPlatform == TargetPlatform.iOS;

  /// How long a direct connect may take before we fall back to autoConnect.
  @visibleForTesting
  static Duration directConnectTimeout = const Duration(seconds: 12);

  // The running scan, if any: [stopScan] finishes it early.
  Future<void> Function()? _finishScan;

  @override
  void setWheelCircumference(double meters) {
    if (meters <= 0) return;
    _wheelCircumferenceMeters = meters;
    // Sensors already linked too: the active bike can change mid-ride.
    for (final csc in _csc.values) {
      csc.wheelCircumferenceMeters = meters;
    }
  }

  static final List<String> _serviceUuids = [
    GattIds.full(GattIds.heartRateService),
    GattIds.full(GattIds.cscService),
    GattIds.full(GattIds.cyclingPowerService),
  ];

  @override
  Future<bool> ensureReady() async {
    try {
      // Android 12+: BLUETOOTH_SCAN/CONNECT are runtime permissions (no
      // location needed — the manifest declares BLUETOOTH_SCAN neverForLocation).
      // Throws if the rider denies them.
      if (!await UniversalBle.hasPermissions()) {
        await UniversalBle.requestPermissions();
      }
      var state = await UniversalBle.getBluetoothAvailabilityState();
      if (state == AvailabilityState.unknown ||
          state == AvailabilityState.resetting) {
        state = await UniversalBle.availabilityStream
            .firstWhere((s) =>
                s != AvailabilityState.unknown &&
                s != AvailabilityState.resetting)
            .timeout(const Duration(seconds: 4),
                onTimeout: () => AvailabilityState.unknown);
      }
      return state == AvailabilityState.poweredOn;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<List<DiscoveredSensor>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) {
    final found = <String, DiscoveredSensor>{};
    late final StreamController<List<DiscoveredSensor>> out;
    StreamSubscription<BleDevice>? sub;
    Timer? timer;
    var finished = false;

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      timer?.cancel();
      await sub?.cancel();
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      if (_finishScan == finish) _finishScan = null;
      await out.close();
    }

    out = StreamController<List<DiscoveredSensor>>(
      onListen: () async {
        _finishScan = finish;
        sub = UniversalBle.scanStream.listen((d) {
          final kinds = _kindsFromServices(d.services);
          if (kinds.isEmpty) return;
          final name = d.name;
          if (name != null && name.isNotEmpty) _names[d.deviceId] = name;
          found[d.deviceId] =
              DiscoveredSensor(id: d.deviceId, name: _nameOf(d.deviceId), kinds: kinds);
          if (!out.isClosed) out.add(found.values.toList());
        });
        timer = Timer(timeout, finish);
        try {
          await UniversalBle.startScan(
              scanFilter: ScanFilter(withServices: _serviceUuids));
        } catch (e, st) {
          if (!out.isClosed) out.addError(e, st);
          await finish();
        }
      },
      onCancel: finish,
    );
    return out.stream;
  }

  @override
  Future<void> stopScan() async {
    final finish = _finishScan;
    if (finish != null) return finish();
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
  }

  @override
  Future<void> connect(String deviceId, {bool autoConnect = false}) async {
    _desiredTargets.add(deviceId);
    if (_suspended) return; // recorded; restored by resumeConnections()
    _targets.add(deviceId);
    _connected[deviceId] ??= ConnectedSensor(
      id: deviceId,
      name: _nameOf(deviceId),
      kinds: const {},
      connected: false,
      reconnecting: true,
    );
    _emitConnected();
    _ensureConnSub(deviceId);
    // One-shot DIRECT connect (not passive autoConnect): a direct connect links
    // fast when the sensor is advertising — which a worn HR strap / a spinning
    // cadence sensor is — whereas passive `autoConnect=true` frequently just
    // never links a present sensor (confirmed on-device). Crucially a direct
    // connect does NOT scan, so it doesn't compete with the GPS radio. If the
    // sensor isn't reachable right now it falls back to passive autoConnect.
    // This is the same path the manual reconnect tap uses.
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
    if (_connected[deviceId]?.connected == true) return;
    if (_pendingConnectWaits && _autoConnectRegistered.contains(deviceId)) {
      return; // already waiting for it (see _pendingConnectWaits)
    }
    if (!_directInFlight.add(deviceId)) return; // one attempt at a time
    try {
      await _directConnect(deviceId);
    } finally {
      _directInFlight.remove(deviceId);
    }
  }

  Future<void> _directConnect(String deviceId) async {
    _ensureConnSub(deviceId);
    // A pending autoConnect is a GATT client of its own; a direct connect next
    // to it would register a second one (and each retry tick another).
    if (_autoConnectRegistered.remove(deviceId)) await _cancel(deviceId);
    try {
      await UniversalBle.connect(deviceId,
          autoConnect: false, timeout: directConnectTimeout);
    } catch (_) {
      // Asleep / out of range. The native attempt outlives Dart's timeout, so
      // cancel it, then register passive autoConnect so the sensor links when
      // it next advertises (quiet on the radio, no scan). _registerAutoConnect
      // skips this if we were suspended (or the target dropped) meanwhile:
      // re-registering then would quietly re-create the very registration the
      // suspension tore down.
      if (_connected[deviceId]?.connected == true) return; // linked anyway
      await _cancel(deviceId);
      _registerAutoConnect(deviceId);
    }
  }

  /// Cancels any native connection or pending connect for [deviceId].
  Future<void> _cancel(String deviceId) async {
    try {
      await UniversalBle.disconnect(deviceId,
          timeout: const Duration(seconds: 5));
    } catch (_) {}
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
    if (existing?.connected != true) await _cancel(deviceId);
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

  Future<void> _serialized(Future<void> Function() op) =>
      _transition = _transition.then((_) => op()).catchError((_) {});

  @override
  Future<void> suspendConnections() => _serialized(_suspend);

  @override
  Future<void> resumeConnections() => _serialized(_resume);

  Future<void> _suspend() async {
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

  Future<void> _resume() async {
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
    _connSubs[deviceId] =
        UniversalBle.connectionStream(deviceId).listen((connected) {
      if (connected) {
        _linkUp.add(deviceId);
        unawaited(_onConnected(deviceId));
      } else {
        final wasLinked = _linkUp.remove(deviceId);
        _onDisconnected(deviceId);
        // Mid-ride drop of an active target: register passive autoConnect so
        // the OS re-links it when it reappears. Passive (no scan) so it stays
        // quiet on the radio and doesn't disturb GPS; a direct-connect retry
        // here could fight a brief out-of-range blip. The user can also tap
        // the stat to force a direct reconnect. Only after a real link (even
        // one that dropped during service discovery, as when the A33 tore
        // down a link left over from a killed app process): a failed or
        // cancelled *attempt* also reports "disconnected", and its caller
        // decides what comes next.
        if (wasLinked && _targets.contains(deviceId)) {
          _registerAutoConnect(deviceId);
        }
      }
    });
  }

  /// Registers native autoConnect for [deviceId]: the OS re-links whenever the
  /// sensor next advertises (wakes / back in range), with no app-level
  /// scanning — quiet on the radio, so it doesn't fight the GPS. The
  /// registration outlives the Dart-side wait; [_cancel] removes it.
  void _registerAutoConnect(String deviceId) {
    if (_suspended || !_targets.contains(deviceId)) return;
    if (!_autoConnectRegistered.add(deviceId)) return;
    _ensureConnSub(deviceId);
    unawaited(UniversalBle.connect(deviceId,
            autoConnect: true, timeout: const Duration(seconds: 10))
        .catchError((_) {}));
  }

  /// Discover services + subscribe to measurements after a (re)connect.
  Future<void> _onConnected(String deviceId) async {
    // A connect that landed after we suspended (or after the target was
    // dropped): let it go rather than wiring up subscriptions nothing reads.
    if (_suspended || !_targets.contains(deviceId)) {
      await _cancel(deviceId);
      return;
    }
    try {
      _autoConnectRegistered.remove(deviceId);
      final services = await UniversalBle.discoverServices(deviceId);
      for (final s in _subs[deviceId] ?? const <StreamSubscription>[]) {
        await s.cancel(); // drop any stale subs from a previous connection
      }
      final subs = <StreamSubscription<dynamic>>[];
      final kinds = <SensorKind>{};
      for (final service in services) {
        for (final kind in SensorKind.values) {
          if (!_isUuid(service.uuid, kind.serviceId)) continue;
          kinds.add(kind);
          for (final char in service.characteristics) {
            if (!_isUuid(char.uuid, kind.measurementId)) continue;
            subs.add(UniversalBle.characteristicValueStream(deviceId, char.uuid)
                .listen((data) => _onData(deviceId, kind, data)));
            await UniversalBle.subscribeNotifications(
                deviceId, service.uuid, char.uuid);
          }
        }
      }
      _subs[deviceId] = subs;
      _csc[deviceId] =
          CscCalculator(wheelCircumferenceMeters: _wheelCircumferenceMeters);
      if (!_names.containsKey(deviceId)) await _lookUpName(deviceId);
      _connected[deviceId] = ConnectedSensor(
          id: deviceId, name: _nameOf(deviceId), kinds: kinds, connected: true);
      _emitConnected();
    } catch (_) {
      // A quick re-drop can race discovery; the next connection event retries.
    }
  }

  /// Name for a sensor linked without a scan this session: the system's list
  /// of connected devices has it. Filtered by our services on Apple (required
  /// there); unfiltered on Android, where a service filter would make
  /// universal_ble connect to every system device to discover its services.
  Future<void> _lookUpName(String deviceId) async {
    try {
      final devices = await UniversalBle.getSystemDevices(
        withServices:
            defaultTargetPlatform == TargetPlatform.iOS ? _serviceUuids : null,
      );
      for (final d in devices) {
        final name = d.name;
        if (d.deviceId.toLowerCase() == deviceId.toLowerCase() &&
            name != null &&
            name.isNotEmpty) {
          _names[deviceId] = name;
        }
      }
    } catch (_) {}
  }

  /// A drop (sensor out of range / standby). Keep it as a target so autoConnect
  /// or the retry window re-establishes it; just tear down the live
  /// subscriptions and mark it offline.
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

  /// Stops pursuing [deviceId]: tears down the live connection/subscriptions,
  /// cancels any pending connect, and forgets its live status. Used both for a
  /// user-initiated unpair and for a bike-profile switch taking a sensor out of
  /// scope — the caller decides which of those it is and whether the pairing
  /// itself is kept.
  Future<void> _removeTarget(String deviceId) async {
    _targets.remove(deviceId);
    _autoConnectRegistered.remove(deviceId);
    _linkUp.remove(deviceId);
    await _connSubs.remove(deviceId)?.cancel();
    for (final s in _subs.remove(deviceId) ?? const <StreamSubscription>[]) {
      await s.cancel();
    }
    _csc.remove(deviceId);
    _clearReadings(deviceId);
    _connected.remove(deviceId);
    _emitConnected();
    // Unlike flutter_blue_plus, this also aborts a connect that is still in
    // flight, so a suspension releases every GATT client right away.
    await _cancel(deviceId);
  }

  @override
  Stream<List<ConnectedSensor>> connectedSensors() => _connectedCtrl.stream;

  @override
  Stream<SensorSnapshot> snapshots() => _snapshots.stream;

  void _onData(String deviceId, SensorKind kind, Uint8List data) {
    if (data.isEmpty) return;
    final csc = _csc[deviceId];
    final reading = switch (kind) {
      SensorKind.heartRate =>
        SensorSnapshot(heartRate: GattParsers.parseHeartRate(data).bpm),
      SensorKind.speedCadence => () {
          if (csc == null) return null;
          final result = csc.update(GattParsers.parseCsc(data));
          return SensorSnapshot(
            wheelSpeedMps: result.speedMetersPerSecond,
            cadenceRpm: result.cadenceRpm,
          );
        }(),
      SensorKind.power =>
        SensorSnapshot(power: GattParsers.parsePower(data).watts),
    };
    if (reading == null) return;
    _snapshots.add(_merger.update(deviceId, reading));
  }

  /// Forgets everything [deviceId] contributed and tells listeners, so the
  /// dashboard falls back to "—" and the next recorded point doesn't inherit a
  /// value from a sensor that's no longer there.
  void _clearReadings(String deviceId) {
    if (_merger.remove(deviceId)) _snapshots.add(_merger.merged);
  }

  /// True when [uuid] (short or full 128-bit, any case) is the SIG id [shortId].
  static bool _isUuid(String uuid, String shortId) {
    final u = uuid.toLowerCase();
    return u == shortId || u == GattIds.full(shortId);
  }

  Set<SensorKind> _kindsFromServices(List<String> serviceUuids) => {
        for (final kind in SensorKind.values)
          if (serviceUuids.any((u) => _isUuid(u, kind.serviceId))) kind,
      };

  String _nameOf(String deviceId) => _names[deviceId] ?? 'Unknown sensor';

  void _emitConnected() => _connectedCtrl.add(_connected.values.toList());
}
