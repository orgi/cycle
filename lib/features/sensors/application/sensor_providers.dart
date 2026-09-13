import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sensors/ble_sensor_service.dart';
import '../../../core/sensors/gatt.dart';
import '../../../core/sensors/paired_sensors_store.dart';
import '../../../core/sensors/sensor_service.dart';
import '../../settings/application/bike_profile_providers.dart';

/// Bluetooth sensor backend. Overridden with a fake in tests / on the emulator.
final sensorServiceProvider =
    Provider<SensorService>((ref) => BleSensorService());

/// Persists paired sensors (id/name/kinds) for auto-reconnect. Overridable in
/// tests.
final pairedSensorsStoreProvider =
    Provider<PairedSensorsStore>((ref) => SharedPrefsPairedSensorsStore());

/// Tracks which sensors the user has paired, persists them, and drives which
/// of them the backend actively pursues right now — the active bike profile's
/// sensor selection (or all paired sensors, if that profile hasn't been
/// configured). Its [build] runs when first read — keep it read at startup,
/// e.g. from the home screen. Connect/disconnect from the UI go through here
/// so the paired set stays in sync; a bike-profile switch is picked up via
/// [ref.listen] so switching bikes disconnects out-of-scope sensors and
/// starts pursuing newly in-scope ones without any extra wiring at the call
/// site.
final sensorConnectionProvider =
    NotifierProvider<SensorConnectionController, Set<PairedSensor>>(
        SensorConnectionController.new);

class SensorConnectionController extends Notifier<Set<PairedSensor>> {
  @override
  Set<PairedSensor> build() {
    final service = ref.read(sensorServiceProvider);
    // A sensor paired under the pre-kinds format (migrated from the old
    // id-only list) has no persisted kinds, so it never lit up a dashboard
    // tile even once connected and selected for the active bike. Backfill the
    // real kinds the moment a connection actually reveals them. Subscribed
    // directly (not via connectedSensorsProvider) so this is armed
    // synchronously — going through the StreamProvider risks subscribing
    // after a connect that happens fast enough to already have fired, which
    // a broadcast stream never replays.
    final sub = service.connectedSensors().listen((connected) {
      _absorbKinds(
          connected.map((c) => (id: c.id, name: c.name, kinds: c.kinds)));
    });
    ref.onDispose(sub.cancel);
    // Load paired sensors and start pursuing the active bike's selection, off
    // the build path so startup never blocks (a failed reconnect — sensor out
    // of range — is ignored).
    ref.read(pairedSensorsStoreProvider).load().then((sensors) async {
      if (sensors.isEmpty) return;
      state = sensors.toSet();
      try {
        await service.ensureReady();
      } catch (_) {}
      await _applyActiveTargets();
    });
    // A bike-profile switch (manual pick, hardware-button cycle) or an edit
    // to its sensor selection changes which sensors should be pursued.
    ref.listen(bikeProfilesProvider, (prev, next) {
      if (prev?.activeId != next.activeId ||
          prev?.active?.sensorIds != next.active?.sensorIds) {
        _applyActiveTargets();
      }
    });
    // A scan (manual, from the Sensors screen) reveals a paired sensor's kinds
    // from its advertisement without ever connecting — the other half of the
    // backfill below.
    ref.listen(scanResultsProvider, (_, found) {
      _absorbKinds(found.map((d) => (id: d.id, name: d.name, kinds: d.kinds)));
    });
    return const {};
  }

  /// Records the sensor *kinds* (HR / cadence / power) for already-paired
  /// sensors as soon as we learn them — whether from a full connection or
  /// merely from seeing the sensor advertise during a scan. This is what a
  /// dashboard tile's visibility keys off, and a sensor paired under the old
  /// id-only format (migrated with empty kinds) would otherwise never light up
  /// a tile until it happened to fully connect. Now merely being *seen* by the
  /// phone once — which the reconnect scan does on its own while a bike that
  /// lists the sensor is active — is enough, so the tile then shows even while
  /// the sensor is disconnected, exactly as configured.
  void _absorbKinds(
      Iterable<({String id, String name, Set<SensorKind> kinds})> seen) {
    final kindsById = <String, Set<SensorKind>>{};
    final nameById = <String, String>{};
    for (final s in seen) {
      if (s.kinds.isEmpty) continue;
      kindsById.update(s.id, (existing) => {...existing, ...s.kinds},
          ifAbsent: () => {...s.kinds});
      if (s.name.isNotEmpty) nameById[s.id] = s.name;
    }
    if (kindsById.isEmpty) return;
    var changed = false;
    final updated = <PairedSensor>{};
    for (final p in state) {
      final learned = kindsById[p.id];
      final merged = learned == null ? p.kinds : {...p.kinds, ...learned};
      // Also upgrade a migrated placeholder name (which is just the device id)
      // to the real one once a scan/connection reveals it.
      final learnedName = nameById[p.id];
      final name = (learnedName != null && p.name == p.id) ? learnedName : p.name;
      if (merged.length != p.kinds.length || name != p.name) {
        updated.add(PairedSensor(id: p.id, name: name, kinds: merged));
        changed = true;
      } else {
        updated.add(p);
      }
    }
    if (changed) {
      state = updated;
      unawaited(_persist());
    }
  }

  Future<void> connect(DiscoveredSensor sensor) async {
    final paired =
        PairedSensor(id: sensor.id, name: sensor.name, kinds: sensor.kinds);
    state = {...state.where((p) => p.id != sensor.id), paired};
    await _persist();
    // Make sure a restrictive active profile doesn't immediately drop a
    // sensor the user just paired from the scan screen.
    final bikeCtrl = ref.read(bikeProfilesProvider.notifier);
    final active = ref.read(bikeProfilesProvider).active;
    if (active != null && active.sensorIds != null) {
      await bikeCtrl.setSensorIds(active.id, {...active.sensorIds!, sensor.id});
    }
    await ref.read(sensorServiceProvider).connect(sensor.id, autoConnect: true);
    await _applyActiveTargets();
  }

  Future<void> disconnect(String deviceId) async {
    await ref.read(sensorServiceProvider).disconnect(deviceId);
    state = state.where((p) => p.id != deviceId).toSet();
    await _persist();
  }

  /// Quick user-triggered reconnect (a tapped stat tile) of the active-bike
  /// sensors of [kind]. One-shot direct-connect per sensor, no scanning.
  /// Returns how many sensors were kicked (0 if none apply here).
  ///
  /// Also kicks sensors whose kind we don't know yet (paired under the old
  /// id-only format and not connected since, so their kind was never learned) —
  /// a reconnect is harmless, and once it links its kind is backfilled and
  /// future taps are precise. This is what makes a flaky, never-cleanly-linked
  /// speed sensor reconnectable from a stat tile at all.
  Future<int> reconnectKind(SensorKind kind) async {
    final allow = ref.read(bikeProfilesProvider).active?.sensorIds;
    final service = ref.read(sensorServiceProvider);
    var kicked = 0;
    for (final p in state) {
      if (!(p.kinds.contains(kind) || p.kinds.isEmpty)) continue;
      if (allow != null && !allow.contains(p.id)) continue;
      await service.reconnect(p.id);
      kicked++;
    }
    return kicked;
  }

  /// Quick user-triggered reconnect of one specific paired sensor by id (the
  /// Sensors screen's per-device reconnect — unambiguous, by name).
  Future<void> reconnectDevice(String deviceId) =>
      ref.read(sensorServiceProvider).reconnect(deviceId);

  Future<void> _applyActiveTargets() async {
    final allow = ref.read(bikeProfilesProvider).active?.sensorIds;
    final paired = state.map((p) => p.id).toSet();
    final targets = allow == null ? paired : paired.intersection(allow);
    await ref.read(sensorServiceProvider).setActiveTargets(targets);
  }

  Future<void> _persist() =>
      ref.read(pairedSensorsStoreProvider).save(state.toList());
}

/// Live merged sensor values (HR, cadence, wheel speed, power).
final sensorSnapshotProvider = StreamProvider<SensorSnapshot>(
  (ref) => ref.watch(sensorServiceProvider).snapshots(),
);

/// Sensors currently connected.
final connectedSensorsProvider = StreamProvider<List<ConnectedSensor>>(
  (ref) => ref.watch(sensorServiceProvider).connectedSensors(),
);

/// Sensors discovered during an active scan (empty when not scanning).
final scanResultsProvider =
    NotifierProvider<ScanController, List<DiscoveredSensor>>(
        ScanController.new);

class ScanController extends Notifier<List<DiscoveredSensor>> {
  @override
  List<DiscoveredSensor> build() => const [];

  bool _scanning = false;
  bool get scanning => _scanning;

  Future<void> startScan() async {
    if (_scanning) return;
    final service = ref.read(sensorServiceProvider);
    await service.ensureReady();
    _scanning = true;
    state = const [];
    try {
      await for (final found in service.scan()) {
        state = found;
      }
    } finally {
      _scanning = false;
      state = List.of(state); // force a rebuild so the spinner hides
    }
  }

  Future<void> stopScan() async {
    await ref.read(sensorServiceProvider).stopScan();
    _scanning = false;
  }
}
