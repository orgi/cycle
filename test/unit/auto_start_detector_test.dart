import 'package:cycle/core/controls/auto_start_detector.dart';
import 'package:cycle/core/models/geo_sample.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 7, 12);
  GeoSample at(int second, double? kmh) => GeoSample(
        latitude: 0,
        longitude: 0,
        time: t0.add(Duration(seconds: second)),
        speedMps: kmh == null ? null : kmh / 3.6,
      );

  /// Feeds one fix per second from [from] to [to] (inclusive) at [kmh];
  /// returns the seconds at which a start was requested.
  List<int> ride(AutoStartDetector d, int from, int to, double? kmh,
      {bool recording = false}) {
    final starts = <int>[];
    for (var s = from; s <= to; s++) {
      if (d.update(at(s, kmh), recording: recording)) starts.add(s);
    }
    return starts;
  }

  test('starts after riding >= 8 km/h for 5 s, exactly once', () {
    final d = AutoStartDetector();
    expect(ride(d, 0, 20, 20), [5]);
  });

  test('walking / pushing the bike never starts a ride', () {
    final d = AutoStartDetector();
    expect(ride(d, 0, 120, 5), isEmpty);
  });

  test('a short burst or one jittery fix does not start a ride', () {
    final d = AutoStartDetector();
    expect(ride(d, 0, 3, 25), isEmpty); // 3 s fast
    expect(ride(d, 4, 4, 2), isEmpty); // drops below: resets
    expect(ride(d, 5, 8, 25), isEmpty); // another 3 s
    expect(d.isArmed, isTrue);
  });

  test('fixes without a speed are ignored, not counted as stopping', () {
    final d = AutoStartDetector();
    expect(ride(d, 0, 2, 20), isEmpty);
    expect(ride(d, 3, 3, null), isEmpty);
    expect(ride(d, 4, 5, 20), [5]);
  });

  test('never starts while a ride is already recording', () {
    final d = AutoStartDetector();
    expect(ride(d, 0, 30, 25, recording: true), isEmpty);
  });

  group('after a ride stops', () {
    late AutoStartDetector d;
    setUp(() {
      d = AutoStartDetector();
      ride(d, 0, 10, 25, recording: true); // a ride was running
    });

    test('stopping while still rolling does not restart it', () {
      expect(ride(d, 11, 60, 25), isEmpty);
      expect(d.isArmed, isFalse);
    });

    test('re-arms after a minute standing still, then starts the next ride',
        () {
      expect(ride(d, 11, 71, 0), isEmpty); // 60 s stationary
      expect(d.isArmed, isTrue);
      expect(ride(d, 72, 90, 22), [77]);
    });

    test('moving again before the minute is up keeps it disarmed', () {
      expect(ride(d, 11, 50, 0), isEmpty); // 39 s stationary
      expect(ride(d, 51, 52, 15), isEmpty); // rolls off: timer resets
      expect(ride(d, 53, 100, 0), isEmpty); // 47 s stationary
      expect(d.isArmed, isFalse);
      expect(ride(d, 101, 113, 0), isEmpty); // now 60 s
      expect(d.isArmed, isTrue);
    });
  });
}
