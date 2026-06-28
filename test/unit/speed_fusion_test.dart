import 'package:cycle/core/sensors/speed_fusion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  test('no data → zero', () {
    expect(SpeedFusion().fused(t0), 0);
  });

  test('sleeping sensor (BLE ~0) while GPS moving → GPS, not green', () {
    final f = SpeedFusion()
      ..updateGps(8) // ~29 km/h
      ..updateBle(0, t0); // sensor reports 0 (asleep) but we're moving
    expect(f.fused(t0), 8);
    expect(f.isUsingBle(t0), isFalse);
  });

  test('genuinely stopped (BLE 0, GPS 0) stays on the sensor 0', () {
    final f = SpeedFusion()
      ..updateGps(0)
      ..updateBle(0, t0);
    expect(f.fused(t0), 0);
    expect(f.isUsingBle(t0), isTrue);
  });

  test('moving with a live sensor keeps BLE', () {
    final f = SpeedFusion()
      ..updateGps(8)
      ..updateBle(8.5, t0);
    expect(f.fused(t0), 8.5);
    expect(f.isUsingBle(t0), isTrue);
  });

  test('GPS used when no BLE sensor', () {
    final f = SpeedFusion()..updateGps(5);
    expect(f.fused(t0), 5);
    expect(f.isUsingBle(t0), isFalse);
  });

  test('fresh BLE wins over GPS', () {
    final f = SpeedFusion()
      ..updateGps(5)
      ..updateBle(8, t0);
    expect(f.fused(t0), 8);
    expect(f.isUsingBle(t0), isTrue);
  });

  test('stale BLE falls back to GPS', () {
    final f = SpeedFusion(bleFreshness: const Duration(seconds: 3))
      ..updateGps(5)
      ..updateBle(8, t0);
    final later = t0.add(const Duration(seconds: 4));
    expect(f.fused(later), 5);
    expect(f.isUsingBle(later), isFalse);
  });

  test('clearBle falls back to GPS immediately (sensor disconnected)', () {
    final f = SpeedFusion()
      ..updateGps(5)
      ..updateBle(8, t0);
    expect(f.fused(t0), 8); // BLE fresh
    f.clearBle();
    expect(f.fused(t0), 5); // dropped → GPS, no waiting for freshness
    expect(f.isUsingBle(t0), isFalse);
  });
}
