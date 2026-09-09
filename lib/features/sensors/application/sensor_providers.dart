import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sensors/ble_sensor_service.dart';
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
    // Load paired sensors and start pursuing the active bike's selection, off
    // the build path so startup never blocks (a failed reconnect — sensor out
    // of range — is ignored).
    ref.read(pairedSensorsStoreProvider).load().then((sensors) async {
      if (sensors.isEmpty) return;
      state = sensors.toSet();
      final service = ref.read(sensorServiceProvider);
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
    return const {};
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
