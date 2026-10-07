import 'dart:async';

import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/core/sensors/sensor_snapshot_merger.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_state.dart';
import 'package:cycle/core/services/bike_profiles/bike_profiles_store.dart';
import 'package:cycle/core/services/hardware_button_service.dart';
import 'package:cycle/core/services/location_power_control.dart';
import 'package:cycle/core/services/location_service.dart';
import 'package:cycle/core/services/route_import_service.dart';
import 'package:cycle/core/services/screen_wake_service.dart';
import 'package:cycle/core/services/settings/app_settings.dart';
import 'package:cycle/core/services/settings/settings_store.dart';

/// A [LocationService] driven by the test: push samples via [emit].
class FakeLocationService implements LocationService {
  final StreamController<GeoSample> _controller =
      StreamController<GeoSample>.broadcast();

  bool permissionGranted = true;

  void emit(GeoSample sample) => _controller.add(sample);

  Future<void> dispose() => _controller.close();

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Stream<GeoSample> positions() => _controller.stream;
}

/// A [LocationPowerControl] that records the recording-active flags pushed to
/// the native GPS gate.
class RecordingLocationPowerControl implements LocationPowerControl {
  final List<bool> calls = [];

  @override
  Future<void> setRecordingActive(bool active) async => calls.add(active);
}

/// A [ScreenWakeService] that records how often keep-awake actually toggled
/// (owner reference-counting lives in the base class, so these count real
/// transitions, not every enable/disable call).
class RecordingScreenWakeService extends ScreenWakeService {
  int enableCount = 0;
  int disableCount = 0;

  @override
  Future<void> applyEnabled(bool on) async =>
      on ? enableCount++ : disableCount++;
}

/// A [SensorService] driven by the test: set [discoverable] sensors, drive
/// [emitSnapshot], and connect/disconnect deterministically.
class FakeSensorService implements SensorService {
  FakeSensorService({this.discoverable = const [], this.connectTargets = true});

  List<DiscoveredSensor> discoverable;
  bool ready = true;

  /// When false, [setActiveTargets] registers targets but leaves them
  /// disconnected — lets a test show a paired-but-not-connected sensor.
  bool connectTargets;

  final StreamController<SensorSnapshot> _snapshots =
      StreamController<SensorSnapshot>.broadcast();
  final StreamController<List<ConnectedSensor>> _connectedCtrl =
      StreamController<List<ConnectedSensor>>.broadcast();
  final List<ConnectedSensor> _connected = [];

  void emitSnapshot(SensorSnapshot snapshot) => _snapshots.add(snapshot);

  // Same per-device merge the real service uses, so tests exercise the real
  // "a value lives only as long as its sensor's link" semantics.
  final SensorSnapshotMerger _merger = SensorSnapshotMerger();

  /// A reading from one linked device (like a real GATT notification).
  void emitReading(String deviceId, SensorSnapshot reading) =>
      _snapshots.add(_merger.update(deviceId, reading));

  /// The link to [deviceId] drops on its own (strap taken off, out of range):
  /// it stays a target but its readings go, exactly like the real service.
  void dropLink(String deviceId) {
    final i = _connected.indexWhere((c) => c.id == deviceId);
    if (i >= 0) {
      final c = _connected[i];
      _connected[i] = ConnectedSensor(
          id: c.id, name: c.name, kinds: c.kinds, connected: false);
      _connectedCtrl.add(List.of(_connected));
    }
    if (_merger.remove(deviceId)) _snapshots.add(_merger.merged);
  }

  Future<void> dispose() async {
    await _snapshots.close();
    await _connectedCtrl.close();
  }

  @override
  Future<bool> ensureReady() async => ready;

  @override
  Stream<List<DiscoveredSensor>> scan({
    Duration timeout = const Duration(seconds: 12),
  }) async* {
    yield discoverable;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId, {bool autoConnect = false}) async {
    // A device reconnected from persisted pairing (not this session's scan)
    // may not be in [discoverable] — fall back to a bare entry, same as the
    // real service falling back to a generic name until it actually connects.
    final d = discoverable.where((s) => s.id == deviceId).firstOrNull;
    _connected
      ..removeWhere((c) => c.id == deviceId)
      ..add(ConnectedSensor(
          id: deviceId,
          name: d?.name ?? deviceId,
          kinds: d?.kinds ?? const {},
          connected: true));
    _connectedCtrl.add(List.of(_connected));
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _connected.removeWhere((c) => c.id == deviceId);
    _connectedCtrl.add(List.of(_connected));
    if (_merger.remove(deviceId)) _snapshots.add(_merger.merged);
  }

  /// Device ids [reconnect] was called for, in order (for test assertions).
  final List<String> reconnectCalls = [];

  @override
  Future<void> reconnect(String deviceId) async {
    reconnectCalls.add(deviceId);
    await connect(deviceId);
  }

  /// How many times [retryConnections] was called (for test assertions).
  int retryConnectionsCalls = 0;

  @override
  Future<void> retryConnections() async => retryConnectionsCalls++;

  /// Last value pushed via [setWheelCircumference].
  double wheelCircumference = 2.105;

  @override
  void setWheelCircumference(double meters) => wheelCircumference = meters;

  @override
  Stream<List<ConnectedSensor>> connectedSensors() => _connectedCtrl.stream;

  @override
  Stream<SensorSnapshot> snapshots() => _snapshots.stream;

  /// Counts of gate-driven suspend/resume calls, for the sensor power gate.
  int suspendCount = 0;
  int resumeCount = 0;

  @override
  Future<void> suspendConnections() async => suspendCount++;

  @override
  Future<void> resumeConnections() async => resumeCount++;

  @override
  Future<void> setActiveTargets(Set<String> ids) async {
    for (final c in _connected.map((c) => c.id).toList()) {
      if (!ids.contains(c)) await disconnect(c);
    }
    if (!connectTargets) return;
    for (final id in ids) {
      if (!_connected.any((c) => c.id == id)) await connect(id);
    }
  }
}

/// A [RouteImportService] driven by the test: [filesXml] maps a route file name
/// to its GPX contents (the importable folder), and [assetXml] backs `loadAsset`.
class FakeRouteImportService implements RouteImportService {
  FakeRouteImportService({Map<String, String>? filesXml, this.assetXml = ''})
      : filesXml = filesXml ?? {};

  Map<String, String> filesXml;
  String assetXml;

  @override
  Future<List<RouteFile>> listImportableRoutes() async => [
        for (final name in filesXml.keys)
          RouteFile(name: name, path: '/fake/$name.gpx'),
      ];

  @override
  Future<ImportedGpx> readRoute(RouteFile file) async =>
      ImportedGpx(name: file.name, xml: filesXml[file.name] ?? '');

  @override
  Future<ImportedGpx> loadAsset(String assetPath, {required String name}) async {
    return ImportedGpx(name: name, xml: assetXml);
  }

  @override
  Future<String> routesFolderPath() async => '/fake/routes';
}

/// A [HardwareButtonService] the test drives via [press]; records enabled state.
class FakeHardwareButtonService implements HardwareButtonService {
  final StreamController<HardwareButton> _controller =
      StreamController<HardwareButton>.broadcast();
  bool enabled = false;

  void press(HardwareButton button) => _controller.add(button);

  Future<void> dispose() => _controller.close();

  @override
  Stream<HardwareButton> get events => _controller.stream;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

/// An in-memory [SettingsStore] seeded with [initial].
class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([this._settings = const AppSettings()]);
  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

/// An in-memory [BikeProfilesStore] seeded with [initial].
class FakeBikeProfilesStore implements BikeProfilesStore {
  FakeBikeProfilesStore([this._state = BikeProfilesState.empty]);
  BikeProfilesState _state;

  @override
  Future<BikeProfilesState> load() async => _state;

  @override
  Future<void> save(BikeProfilesState state) async => _state = state;
}
