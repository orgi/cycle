import 'dart:async';

import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/core/services/hardware_button_service.dart';
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

/// A [ScreenWakeService] that records how often it was toggled.
class RecordingScreenWakeService implements ScreenWakeService {
  int enableCount = 0;
  int disableCount = 0;

  @override
  Future<void> enable() async => enableCount++;

  @override
  Future<void> disable() async => disableCount++;
}

/// A [SensorService] driven by the test: set [discoverable] sensors, drive
/// [emitSnapshot], and connect/disconnect deterministically.
class FakeSensorService implements SensorService {
  FakeSensorService({this.discoverable = const []});

  List<DiscoveredSensor> discoverable;
  bool ready = true;

  final StreamController<SensorSnapshot> _snapshots =
      StreamController<SensorSnapshot>.broadcast();
  final StreamController<List<ConnectedSensor>> _connectedCtrl =
      StreamController<List<ConnectedSensor>>.broadcast();
  final List<ConnectedSensor> _connected = [];

  void emitSnapshot(SensorSnapshot snapshot) => _snapshots.add(snapshot);

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
  Future<void> connect(String deviceId) async {
    final d = discoverable.firstWhere((s) => s.id == deviceId);
    _connected
      ..removeWhere((c) => c.id == deviceId)
      ..add(ConnectedSensor(
          id: d.id, name: d.name, kinds: d.kinds, connected: true));
    _connectedCtrl.add(List.of(_connected));
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _connected.removeWhere((c) => c.id == deviceId);
    _connectedCtrl.add(List.of(_connected));
  }

  /// Last value pushed via [setWheelCircumference].
  double wheelCircumference = 2.105;

  @override
  void setWheelCircumference(double meters) => wheelCircumference = meters;

  @override
  Stream<List<ConnectedSensor>> connectedSensors() => _connectedCtrl.stream;

  @override
  Stream<SensorSnapshot> snapshots() => _snapshots.stream;
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
