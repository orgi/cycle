import 'package:cycle/features/map/presentation/time_stat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 10, 23, 0, 0);

  test('a ride shows its time; amber PAUSED while auto-paused', () {
    final t = timeStat(
        rideElapsed: const Duration(minutes: 5, seconds: 3),
        paused: false,
        now: now);
    expect((t.label, t.value, t.amber), ('TIME', '0:05:03', false));
    final p = timeStat(
        rideElapsed: const Duration(minutes: 5), paused: true, now: now);
    expect((p.label, p.amber), ('PAUSED', true));
  });

  test('during a battery test: how long the test has been running', () {
    final t = timeStat(
      rideElapsed: Duration.zero,
      paused: false,
      batteryTestStartedAt: now.subtract(const Duration(hours: 2, minutes: 7)),
      now: now,
    );
    expect((t.label, t.value, t.amber), ('TEST', '2:07:00', false));
  });

  test('never negative (clock skew)', () {
    final t = timeStat(
      rideElapsed: Duration.zero,
      paused: false,
      batteryTestStartedAt: now.add(const Duration(seconds: 5)),
      now: now,
    );
    expect(t.value, '0:00:00');
  });
}
