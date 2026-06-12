import 'package:cycle/core/sensors/speed_fusion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  test('no data → zero', () {
    expect(SpeedFusion().fused(t0), 0);
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
}
