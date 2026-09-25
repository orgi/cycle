import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/paired_sensors_store.dart';
import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round-trips id/name/kinds', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPrefsPairedSensorsStore();
    const sensors = [
      PairedSensor(id: 'hr1', name: 'Garmin HRM', kinds: {SensorKind.heartRate}),
      PairedSensor(id: 'cad2', name: 'Cadence', kinds: {SensorKind.speedCadence}),
    ];
    await store.save(sensors);
    final loaded = await store.load();
    expect(loaded, sensors);
  });

  test('migrates the pre-kinds plain id-list format', () async {
    SharedPreferences.setMockInitialValues({
      'paired.sensors': ['hr1', 'cad2'],
    });
    final loaded = await SharedPrefsPairedSensorsStore().load();
    expect(loaded.map((s) => s.id).toSet(), {'hr1', 'cad2'});
    expect(loaded.every((s) => s.kinds.isEmpty), isTrue);
  });

  test('load with nothing saved returns empty', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SharedPrefsPairedSensorsStore().load(), isEmpty);
  });
}
