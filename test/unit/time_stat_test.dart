import 'package:cycle/features/map/presentation/time_stat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 10, 23, 0, 0);

  test('a ride shows its time; amber PAUSED while auto-paused', () {
    final t = timeStat(
        rideElapsed: const Duration(minutes: 5, seconds: 3),
        recording: true,
        paused: false,
        now: now);
    expect((t.label, t.value, t.amber, t.state),
        ('TIME', '0:05:03', false, RideState.recording));
    final p = timeStat(
        rideElapsed: const Duration(minutes: 5),
        recording: true,
        paused: true,
        now: now);
    expect((p.label, p.amber, p.state), ('PAUSED', true, RideState.paused));
  });

  test('no ride: stopped, never paused', () {
    for (final paused in [false, true]) {
      final t = timeStat(
          rideElapsed: const Duration(minutes: 42),
          recording: false,
          paused: paused,
          now: now);
      expect((t.label, t.amber, t.state), ('TIME', false, RideState.stopped));
    }
  });

  test('during a battery test: how long the test has been running', () {
    final t = timeStat(
      rideElapsed: Duration.zero,
      recording: false,
      paused: false,
      batteryTestStartedAt: now.subtract(const Duration(hours: 2, minutes: 7)),
      now: now,
    );
    expect((t.label, t.value, t.amber, t.state),
        ('TEST', '2:07:00', false, null));
  });

  test('never negative (clock skew)', () {
    final t = timeStat(
      rideElapsed: Duration.zero,
      recording: false,
      paused: false,
      batteryTestStartedAt: now.add(const Duration(seconds: 5)),
      now: now,
    );
    expect(t.value, '0:00:00');
  });
}
