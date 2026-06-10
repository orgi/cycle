import 'dart:async';

import 'package:cycle/core/models/geo_sample.dart';
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
