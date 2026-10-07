import 'package:cycle/core/sensors/sensor_service.dart';
import 'package:cycle/core/sensors/sensor_snapshot_merger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SensorSnapshotMerger merger;

  setUp(() => merger = SensorSnapshotMerger());

  test('a disconnected sensor takes its value with it', () {
    merger.update('hr', const SensorSnapshot(heartRate: 150));
    expect(merger.remove('hr'), isTrue);
    expect(merger.merged.heartRate, isNull);
  });

  test('null within a live link holds the last value (CSC hold)', () {
    merger.update('cad', const SensorSnapshot(cadenceRpm: 82));
    // A notification with no new crank revolution reports null: hold, don't
    // flicker to nothing.
    merger.update('cad', const SensorSnapshot());
    expect(merger.merged.cadenceRpm, 82);
  });

  test("a cadence sensor never resurrects a gone speed sensor's wheel speed",
      () {
    merger.update('spd', const SensorSnapshot(wheelSpeedMps: 5.0));
    merger.update('cad', const SensorSnapshot(cadenceRpm: 80));
    merger.remove('spd');

    // Cadence-only CSC results carry a null speed ("hold"). With one global
    // snapshot that null re-broadcast the dead speed sensor's last value.
    final after = merger.update('cad', const SensorSnapshot(cadenceRpm: 82));
    expect(after.wheelSpeedMps, isNull);
    expect(after.cadenceRpm, 82);
  });

  test('removing one sensor keeps the others', () {
    merger.update('hr', const SensorSnapshot(heartRate: 140));
    merger.update('spd', const SensorSnapshot(wheelSpeedMps: 6.0));
    merger.update('pwr', const SensorSnapshot(power: 210));

    merger.remove('spd');
    expect(merger.merged,
        const SensorSnapshot(heartRate: 140, power: 210));
  });

  test('removing an unknown device is a no-op and reports no change', () {
    merger.update('hr', const SensorSnapshot(heartRate: 140));
    expect(merger.remove('nope'), isFalse);
    expect(merger.merged.heartRate, 140);
  });

  test('a reconnected sensor starts fresh, not from its pre-drop value', () {
    merger.update('hr', const SensorSnapshot(heartRate: 150));
    merger.remove('hr');
    // First notification after relinking happens to carry nothing yet.
    merger.update('hr', const SensorSnapshot());
    expect(merger.merged.heartRate, isNull);
  });
}
