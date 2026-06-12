import 'dart:async';

import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/core/services/location_service.dart';
import 'package:cycle/core/services/screen_wake_service.dart';

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

  @override
  Stream<List<ConnectedSensor>> connectedSensors() => _connectedCtrl.stream;

  @override
  Stream<SensorSnapshot> snapshots() => _snapshots.stream;
}
