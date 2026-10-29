import 'dart:async';
import 'dart:math' as math;

import 'package:cycle/core/controls/place_trigger_detector.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:cycle/core/models/ride_place.dart';
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

const _home = RidePlace(
  id: 'home',
  name: 'Home',
  latitude: 47,
  longitude: 11,
  radiusMeters: 50,
);

/// A fix [east] metres east of [_home] (accurate unless [accuracy] says so).
GeoSample _at(double east, {double accuracy = 4}) => GeoSample(
  latitude: 47,
  longitude: 11 + east / (111195 * math.cos(47 * math.pi / 180)),
  time: DateTime.utc(2026, 10, 29, 8),
  accuracyMeters: accuracy,
);

void main() {
  late List<_ManualTimer> timers;
  late List<String> started;
  late List<String> stopped;
  late PlaceTriggerDetector detector;

  setUp(() {
    timers = [];
    started = [];
    stopped = [];
    detector = PlaceTriggerDetector(
      onStart: (p) => started.add(p.id),
      onStop: (p) => stopped.add(p.id),
      timer: (d, f) {
        final t = _ManualTimer(d, f);
        timers.add(t);
        return t;
      },
    );
  });

  void feed(
    List<double> eastMeters, {
    List<RidePlace> places = const [_home],
    bool recording = false,
  }) {
    for (final e in eastMeters) {
      detector.update(_at(e), places, recording: recording);
    }
  }

  group('start', () {
    test('leaving a start place starts a ride', () {
      feed([0, 10, 30]);
      expect(started, isEmpty);
      feed([80]);
      expect(started, ['home']);
    });

    test('opening the app away from the place starts nothing', () {
      feed([300, 200, 100]);
      expect(started, isEmpty);
      // Coming home and leaving again does.
      feed([20, 100]);
      expect(started, ['home']);
    });

    test('the edge band changes nothing: no start from jitter on the edge', () {
      feed([45, 60, 48, 65, 49, 69]); // radius 50, out beyond 70
      expect(started, isEmpty);
      feed([71]);
      expect(started, ['home']);
    });

    test('a first fix on the edge leaves the state unknown', () {
      feed([60, 100]);
      expect(started, isEmpty);
    });

    test('inaccurate fixes are ignored', () {
      feed([0]);
      detector.update(_at(500, accuracy: 30), [_home], recording: false);
      expect(started, isEmpty);
      detector.update(_at(500, accuracy: 8), [_home], recording: false);
      expect(started, ['home']);
    });

    test('no start while a ride records, nor from a stop-only place', () {
      feed([0, 100], recording: true);
      expect(started, isEmpty);
      final work = _home.copyWith(trigger: PlaceTrigger.stop);
      feed([0, 100], places: [work]);
      expect(started, isEmpty);
    });

    test('leaving two start places at once starts one ride', () {
      final shop = RidePlace(
        id: 'shop',
        name: 'Shop',
        latitude: 47,
        longitude: 11.0001,
      );
      feed([0], places: [_home, shop]);
      feed([300], places: [_home, shop]);
      expect(started, ['home']);
    });
  });

  group('stop', () {
    test('arriving during a ride stops it after the stay', () {
      feed([500, 200], recording: true);
      feed([30], recording: true);
      expect(stopped, isEmpty);
      expect(detector.stopPending, isTrue);
      expect(timers.single.duration, const Duration(seconds: 20));
      timers.single.fire();
      expect(stopped, ['home']);
      expect(detector.stopPending, isFalse);
    });

    test('a GPS lost inside still stops: the stay is a timer, not fixes', () {
      feed([500, 10], recording: true); // then no more fixes (garage)
      timers.single.fire();
      expect(stopped, ['home']);
    });

    test('riding through (out again before the stay) does not stop', () {
      feed([500, 30, -30, -200], recording: true);
      expect(detector.stopPending, isFalse);
      for (final t in timers) {
        t.fire(); // cancelled: no effect
      }
      expect(stopped, isEmpty);
    });

    test('a ride started inside a stop place is not stopped there', () {
      feed([0, 10, 20], recording: true);
      expect(detector.stopPending, isFalse);
      // Only once it left and came back.
      feed([200, 10], recording: true);
      expect(detector.stopPending, isTrue);
    });

    test(
      'arriving without a ride, or at a start-only place, stops nothing',
      () {
        feed([500, 10]);
        expect(detector.stopPending, isFalse);
        final start = _home.copyWith(trigger: PlaceTrigger.start);
        feed([500, 10], places: [start], recording: true);
        expect(detector.stopPending, isFalse);
      },
    );

    test('stopping by hand during the stay cancels it', () {
      feed([500, 10], recording: true);
      expect(detector.stopPending, isTrue);
      feed([10]); // not recording any more
      expect(detector.stopPending, isFalse);
      timers.single.fire();
      expect(stopped, isEmpty);
    });

    test('deleting the place during the stay cancels it', () {
      feed([500, 10], recording: true);
      detector.update(_at(10), const [], recording: true);
      expect(detector.stopPending, isFalse);
    });

    test('a ride stopped at a both-way place starts again on leaving', () {
      feed([500, 10], recording: true);
      timers.single.fire();
      feed([10, 200]);
      expect(started, ['home']);
    });
  });

  test('a deleted and re-added place starts from unknown again', () {
    feed([0]);
    feed([0], places: const []);
    feed([100]);
    expect(started, isEmpty);
  });

  test('dispose cancels a pending stop', () {
    feed([500, 10], recording: true);
    detector.dispose();
    timers.single.fire();
    expect(stopped, isEmpty);
  });
}
