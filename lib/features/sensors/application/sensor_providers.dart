import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sensors/ble_sensor_service.dart';
import '../../../core/sensors/paired_sensors_store.dart';
import '../../../core/sensors/sensor_service.dart';

/// Bluetooth sensor backend. Overridden with a fake in tests / on the emulator.
final sensorServiceProvider =
    Provider<SensorService>((ref) => BleSensorService());

/// Persists paired sensor ids for auto-reconnect. Overridable in tests.
final pairedSensorsStoreProvider =
    Provider<PairedSensorsStore>((ref) => SharedPrefsPairedSensorsStore());

/// Tracks which sensors the user has paired, persists them, and reconnects to
/// them on app launch (its [build] runs when first read — keep it read at
/// startup, e.g. from the home screen). Connect/disconnect from the UI go
/// through here so the paired set stays in sync.
final sensorConnectionProvider =
    NotifierProvider<SensorConnectionController, Set<String>>(
        SensorConnectionController.new);

class SensorConnectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // Load the paired ids and reconnect, off the build path so startup never
    // blocks (and a failed reconnect — sensor out of range — is ignored).
    ref.read(pairedSensorsStoreProvider).load().then((ids) async {
      if (ids.isEmpty) return;
      state = ids.toSet();
      final service = ref.read(sensorServiceProvider);
      try {
        await service.ensureReady();
      } catch (_) {}
      for (final id in ids) {
        try {
          // Persistent reconnect: the OS re-links whenever the sensor wakes,
          // so a sensor that was on standby at launch still connects later.
          await service.connect(id, autoConnect: true);
        } catch (_) {}
      }
    });
    return const {};
  }

  Future<void> connect(String deviceId) async {
    await ref.read(sensorServiceProvider).connect(deviceId);
    state = {...state, deviceId};
    await _persist();
  }

  Future<void> disconnect(String deviceId) async {
    await ref.read(sensorServiceProvider).disconnect(deviceId);
    state = {...state}..remove(deviceId);
    await _persist();
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
