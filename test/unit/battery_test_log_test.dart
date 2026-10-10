import 'package:cycle/core/battery_test/battery_test_log.dart';
import 'package:cycle/core/battery_test/simulated_loop.dart';
import 'package:cycle/core/utils/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 10, 8);
  DateTime at(int min) => t0.add(Duration(minutes: min));

  String log(List<String> lines) => '${lines.join('\n')}\n';

  group('BatteryTestLog.parse', () {
    test('no stop line = ran until the phone switched off', () {
      final r = BatteryTestLog.parse('a', log([
        BatteryTestLog.startLine(at(0), 100, 'iOS'),
        for (var m = 1; m <= 300; m++)
          BatteryTestLog.sampleLine(at(m), 100 - m ~/ 3, 55),
      ]))!;
      expect(r.stoppedByHand, isFalse);
      expect(r.runtime, const Duration(hours: 5));
      expect(r.lastAlive, at(300));
      expect(r.startLevel, 100);
      expect(r.endLevel, 0);
      expect(r.used, 100);
      expect(r.drainPerHour, closeTo(20, 1e-9));
      expect(r.platform, 'iOS');
      expect(r.samples.first.realFixes, 55);
    });

    test('stopped by hand: runtime ends at the stop, projection to 0 %', () {
      final r = BatteryTestLog.parse('b', log([
        BatteryTestLog.startLine(at(0), 90, 'iOS'),
        BatteryTestLog.sampleLine(at(30), 85, 60),
        BatteryTestLog.sampleLine(at(60), 80, 60),
        BatteryTestLog.stopLine(at(61), 80),
      ]))!;
      expect(r.stoppedByHand, isTrue);
      expect(r.runtime, const Duration(minutes: 61));
      expect(r.used, 10);
      // 10 points in 61 min → ~9.84 %/h → 100 % lasts ~10:10 h.
      expect(r.projectedFullRuntime!.inMinutes, inInclusiveRange(608, 612));
    });

    test('a torn last line (phone died mid-write) is skipped', () {
      final torn = '{"type":"sample","t":"2026-10-1';
      final content = '${log([
        BatteryTestLog.startLine(at(0), 50, 'android'),
        BatteryTestLog.sampleLine(at(1), 50, 3),
      ])}$torn';
      final r = BatteryTestLog.parse('c', content)!;
      expect(r.samples, hasLength(1));
      expect(r.runtime, const Duration(minutes: 1));
    });

    test('a level that goes up means a charger was connected', () {
      final r = BatteryTestLog.parse('d', log([
        BatteryTestLog.startLine(at(0), 60, 'iOS'),
        BatteryTestLog.sampleLine(at(10), 55, 0),
        BatteryTestLog.sampleLine(at(20), 60, 0),
      ]))!;
      expect(r.chargedDuringTest, isTrue);
    });

    test('too short or without levels: no drain rate (iOS reports 5 % steps)',
        () {
      final short = BatteryTestLog.parse('e', log([
        BatteryTestLog.startLine(at(0), 100, 'iOS'),
        BatteryTestLog.sampleLine(at(5), 95, 0),
      ]))!;
      expect(short.drainPerHour, isNull);
      final unknown = BatteryTestLog.parse('f', log([
        BatteryTestLog.startLine(at(0), null, 'linux'),
        BatteryTestLog.sampleLine(at(60), null, 0),
      ]))!;
      expect(unknown.used, isNull);
      expect(unknown.drainPerHour, isNull);
    });

    test('seen flag and a missing start line', () {
      final r = BatteryTestLog.parse('g', log([
        BatteryTestLog.startLine(at(0), 100, 'iOS'),
        BatteryTestLog.seenLine(at(400)),
      ]))!;
      expect(r.seen, isTrue);
      expect(BatteryTestLog.parse('h', log([
        BatteryTestLog.sampleLine(at(1), 100, 0),
      ])), isNull);
    });
  });

  group('SimulatedLoop', () {
    const loop = SimulatedLoop(centerLat: 47.8, centerLon: 11.9);

    test('stays on the circle around the centre', () {
      for (final s in [0, 17, 60, 333, 1200]) {
        final p = loop.sampleAt(Duration(seconds: s), t0);
        final d = haversineMeters(47.8, 11.9, p.latitude, p.longitude);
        expect(d, closeTo(800, 2), reason: 'at ${s}s');
      }
    });

    test('moves at 25 km/h and laps the loop', () {
      final a = loop.sampleAt(Duration.zero, t0);
      final b = loop.sampleAt(const Duration(seconds: 1), t0);
      final step = haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);
      expect(step, closeTo(25 / 3.6, 0.05));
      expect(a.speedMps, closeTo(25 / 3.6, 1e-9));
      final lapSeconds = loop.circumferenceMeters / (25 / 3.6);
      final lap = loop.sampleAt(
          Duration(milliseconds: (lapSeconds * 1000).round()), t0);
      expect(haversineMeters(a.latitude, a.longitude, lap.latitude, lap.longitude),
          lessThan(0.5));
    });

    test('passes the accuracy filter like a good fix', () {
      expect(loop.sampleAt(Duration.zero, t0).accuracyMeters, 5);
    });
  });
}
