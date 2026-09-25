import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/core/sensors/sensor_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hr = PairedSensor(id: 'hr1', name: 'HR', kinds: {SensorKind.heartRate});
  const cad =
      PairedSensor(id: 'cad2', name: 'CAD', kinds: {SensorKind.speedCadence});

  test('null allow-list shows every paired sensor kind', () {
    final kinds = visibleSensorKinds(paired: {hr, cad}, allowedSensorIds: null);
    expect(kinds, {SensorKind.heartRate, SensorKind.speedCadence});
  });

  test('a restrictive allow-list only shows its own kinds', () {
    final kinds =
        visibleSensorKinds(paired: {hr, cad}, allowedSensorIds: {'cad2'});
    expect(kinds, {SensorKind.speedCadence});
  });

  test('an empty allow-list shows nothing', () {
    final kinds = visibleSensorKinds(paired: {hr, cad}, allowedSensorIds: {});
    expect(kinds, isEmpty);
  });

  test('no paired sensors shows nothing regardless of allow-list', () {
    expect(visibleSensorKinds(paired: const {}, allowedSensorIds: null),
        isEmpty);
  });
}
