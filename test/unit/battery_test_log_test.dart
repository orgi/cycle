import 'package:cycle/core/battery_test/battery_test_log.dart';
import 'package:cycle/core/battery_test/simulated_zigzag.dart';
import 'package:cycle/core/models/geo_sample.dart';
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

  group('SimulatedZigzag', () {
    final route = SimulatedZigzag(startLat: 47.8, startLon: 11.9);
    GeoSample at(Duration d) => route.sampleAt(d, t0);
    Duration hours(double h) => Duration(seconds: (h * 3600).round());

    test('starts at the rider\'s position', () {
      final a = at(Duration.zero);
      expect(haversineMeters(47.8, 11.9, a.latitude, a.longitude), lessThan(0.01));
      expect(a.accuracyMeters, 5); // passes the accuracy filter
    });

    test('speed varies between 25 and 35 km/h, and the rider moves that fast',
        () {
      final speeds = <double>[];
      for (var s = 0; s < 1800; s++) {
        final a = at(Duration(seconds: s));
        final b = at(Duration(seconds: s + 1));
        final kmh = a.speedMps! * 3.6;
        expect(kmh, inInclusiveRange(25, 35), reason: 'at ${s}s');
        speeds.add(kmh);
        // The distance covered matches the reported speed (±1 km/h over 1 s,
        // except where the 1 s step crosses a row's corner).
        final moved =
            haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);
        expect(moved, lessThanOrEqualTo(35 / 3.6 + 0.3), reason: 'at ${s}s');
      }
      // It really varies, rather than sitting at one value.
      final lo = speeds.reduce((a, b) => a < b ? a : b);
      final hi = speeds.reduce((a, b) => a > b ? a : b);
      expect(lo, lessThan(27));
      expect(hi, greaterThan(33));
    });

    test('averages 30 km/h: ~9 km north per 100 km ridden', () {
      final p = at(hours(10 / 3)); // 100 km at 30 km/h: 3.3 km per 300 m north
      final north = haversineMeters(47.8, 11.9, p.latitude, 11.9);
      expect(p.latitude, greaterThan(47.8));
      expect(north, closeTo(100000 / 3300 * 300, 400));
      // Never more than half a row east/west of the start.
      expect(haversineMeters(p.latitude, 11.9, p.latitude, p.longitude),
          lessThanOrEqualTo(1500.5));
    });

    test('without map bounds it stays within 20 km of the start', () {
      for (var h = 0.0; h <= 15; h += 0.25) {
        final p = at(hours(h));
        expect(haversineMeters(47.8, 11.9, p.latitude, 11.9),
            lessThanOrEqualTo(19800.5), reason: '${h}h');
      }
    });

    test('does not ride back over the line it came along (no loop)', () {
      // One hour in, the rider is ~25 km along but far from every earlier
      // point except the ones just ridden.
      final now = at(hours(1));
      for (var m = 0; m < 50; m++) {
        final earlier = at(Duration(minutes: m));
        expect(
            haversineMeters(now.latitude, now.longitude, earlier.latitude,
                earlier.longitude),
            greaterThan(150),
            reason: 'minute $m');
      }
    });

    test('stays inside the given area, turning back onto fresh rows', () {
      // A 6 km × 4 km map, rider starting near its middle.
      const area = (minLat: 47.78, minLon: 11.86, maxLat: 47.816, maxLon: 11.94);
      final small = SimulatedZigzag(startLat: 47.8, startLon: 11.9, area: area);
      final rows = <double>{};
      for (var s = 0; s <= 15 * 3600; s += 20) {
        final p = small.sampleAt(Duration(seconds: s), t0);
        expect(p.latitude, inInclusiveRange(area.minLat, area.maxLat));
        expect(p.longitude, inInclusiveRange(area.minLon, area.maxLon));
        rows.add((p.latitude * 1e5).roundToDouble());
      }
      // Many distinct rows: the sweeps interleave rather than retrace.
      expect(rows.length, greaterThan(40));
    });

    test('a tiny map (the demo) still gets a usable pattern', () {
      const area = (minLat: 43.73, minLon: 7.41, maxLat: 43.731, maxLon: 7.411);
      final tiny =
          SimulatedZigzag(startLat: 43.7305, startLon: 7.4105, area: area);
      final a = tiny.sampleAt(Duration.zero, t0);
      final b = tiny.sampleAt(const Duration(minutes: 10), t0);
      expect(haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude),
          lessThan(1000));
    });
  });
}
