import 'package:cycle/core/models/bike_profile.dart';
import 'package:cycle/core/sensors/gatt.dart';
import 'package:cycle/core/sensors/sensor_catalog.dart';
import 'package:cycle/core/sync/profile_sync.dart';
import 'package:flutter_test/flutter_test.dart';

KnownSensor s(String name, String clock,
        {bool removed = false, String? address}) =>
    KnownSensor(
      name: name,
      kinds: const {SensorKind.heartRate},
      clock: clock,
      removed: removed,
      address: address,
    );

void main() {
  test('sensors are matched by name, ignoring case and spaces', () {
    expect(KnownSensor.keyOf(' HRM-Pro:123456 '), KnownSensor.keyOf('hrm-pro:123456'));
  });

  test('newest pair/remove wins, in any order', () {
    final a = const SensorCatalog().put(s('HRM-Pro:1', '005'));
    final b = const SensorCatalog().put(s('HRM-Pro:1', '009', removed: true));
    final c = const SensorCatalog().put(s('HRM-Pro:1', '012', address: 'AA:BB'));
    final m1 = SensorCatalog.merge(SensorCatalog.merge(a, b), c);
    final m2 = SensorCatalog.merge(c, SensorCatalog.merge(b, a));
    expect(m1, m2);
    expect(m1['hrm-pro:1']!.removed, isFalse); // re-paired after the removal
    expect(m1['hrm-pro:1']!.address, 'AA:BB');
    expect(SensorCatalog.merge(a, b)['hrm-pro:1']!.removed, isTrue);
  });

  test('JSON round trip', () {
    final cat = const SensorCatalog()
        .put(s('HRM-Pro:1', '005', address: 'AA:BB'))
        .put(s('SPD-1', '006', removed: true));
    expect(SensorCatalog.fromJson(cat.toJson()), cat);
  });

  test('a bike\'s sensor choice and its name merge independently', () {
    ProfilesDoc d(BikeProfile p) => ProfilesDoc(profiles: {p.id: p}, deleted: const {});
    final renamed = d(const BikeProfile(
        id: 'b', name: 'Racer', colorArgb: 1, clock: '009',
        sensorKeys: {'hr'}, sensorsClock: '001'));
    final sensorsEdited = d(const BikeProfile(
        id: 'b', name: 'Road', colorArgb: 1, clock: '002',
        sensorKeys: {'hr', 'spd-1'}, sensorsClock: '010'));
    for (final m in [
      ProfilesDoc.merge(renamed, sensorsEdited),
      ProfilesDoc.merge(sensorsEdited, renamed),
    ]) {
      expect(m.profiles['b']!.name, 'Racer');
      expect(m.profiles['b']!.sensorKeys, {'hr', 'spd-1'});
    }
  });

  test('the catalog and sensor choices travel in the profiles file', () {
    final doc = ProfilesDoc(
      profiles: {
        'b': const BikeProfile(
            id: 'b', name: 'Road', colorArgb: 1, sensorKeys: {'hr'}, sensorsClock: '003'),
      },
      deleted: const {},
      sensors: const SensorCatalog().put(s('HR', '004', address: 'AA')),
    );
    final back = ProfilesDoc.decode(doc.encode());
    expect(back.signature, doc.signature);
    expect(back.profiles['b']!.sensorKeys, {'hr'});
    expect(back.sensors['hr']!.address, 'AA');
  });
}
