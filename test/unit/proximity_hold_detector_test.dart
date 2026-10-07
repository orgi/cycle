import 'dart:async';

import 'package:cycle/core/controls/proximity_hold_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// A timer the test fires by hand.
class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this._onFire);
  final Duration duration;
  final void Function() _onFire;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _onFire();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

void main() {
  late List<_ManualTimer> timers;
  late int holds;
  late ProximityHoldDetector detector;

  setUp(() {
    timers = [];
    holds = 0;
    detector = ProximityHoldDetector(
      onHold: () => holds++,
      timer: (d, f) {
        final t = _ManualTimer(d, f);
        timers.add(t);
        return t;
      },
    );
  });

  test('a cover held for the full duration fires once', () {
    detector.update(true);
    expect(timers.single.duration, const Duration(seconds: 2));
    timers.single.fire();
    expect(holds, 1);
  });

  test('a brief cover (brushing hand, raindrop) does nothing', () {
    detector.update(true);
    detector.update(false); // uncovered before 2 s
    timers.single.fire(); // the cancelled timer can't fire any more
    expect(holds, 0);
  });

  test('keeping the hand there does not fire again (no start-then-stop)', () {
    detector.update(true);
    timers.single.fire();
    detector.update(true); // repeated "covered" while still held
    expect(timers, hasLength(1));
    expect(holds, 1);
  });

  test('uncover then hold again fires a second time', () {
    detector.update(true);
    timers.last.fire();
    detector.update(false);
    detector.update(true);
    timers.last.fire();
    expect(holds, 2);
  });

  test('dispose cancels a pending hold', () {
    detector.update(true);
    detector.dispose();
    timers.single.fire();
    expect(holds, 0);
  });
}
