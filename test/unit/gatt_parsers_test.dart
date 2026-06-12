import 'package:cycle/core/sensors/gatt_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('heart rate', () {
    test('uint8 format', () {
      expect(GattParsers.parseHeartRate([0x00, 72]).bpm, 72);
    });
    test('uint16 format', () {
      // flags bit0 set, value little-endian 0x00C8 = 200
      expect(GattParsers.parseHeartRate([0x01, 0xC8, 0x00]).bpm, 200);
    });
  });

  group('CSC', () {
    test('wheel + crank present', () {
      final m = GattParsers.parseCsc([
        0x03, // flags: wheel + crank
        0xE8, 0x03, 0x00, 0x00, // wheel revs = 1000
        0x00, 0x04, // wheel event time = 1024
        0x32, 0x00, // crank revs = 50
        0x00, 0x08, // crank event time = 2048
      ]);
      expect(m.cumulativeWheelRevs, 1000);
      expect(m.lastWheelEventTime, 1024);
      expect(m.cumulativeCrankRevs, 50);
      expect(m.lastCrankEventTime, 2048);
    });

    test('wheel only', () {
      final m = GattParsers.parseCsc([0x01, 0x05, 0, 0, 0, 0x00, 0x04]);
      expect(m.hasWheel, isTrue);
      expect(m.hasCrank, isFalse);
      expect(m.cumulativeWheelRevs, 5);
    });

    test('crank only', () {
      final m = GattParsers.parseCsc([0x02, 0x0A, 0x00, 0x00, 0x04]);
      expect(m.hasWheel, isFalse);
      expect(m.cumulativeCrankRevs, 10);
      expect(m.lastCrankEventTime, 1024);
    });
  });

  group('cycling power', () {
    test('instantaneous power only', () {
      final m = GattParsers.parsePower([0x00, 0x00, 0xC8, 0x00]);
      expect(m.watts, 200);
      expect(m.hasCrank, isFalse);
    });

    test('negative power (sint16)', () {
      expect(GattParsers.parsePower([0x00, 0x00, 0xF6, 0xFF]).watts, -10);
    });

    test('power with crank revolution data', () {
      // flags 0x20 = crank rev data present
      final m = GattParsers.parsePower([
        0x20, 0x00, // flags
        0xC8, 0x00, // power = 200
        0x64, 0x00, // crank revs = 100
        0x00, 0x04, // crank time = 1024
      ]);
      expect(m.watts, 200);
      expect(m.cumulativeCrankRevs, 100);
      expect(m.lastCrankEventTime, 1024);
    });

    test('skips preceding optional fields to reach crank data', () {
      // flags 0x21 = pedal balance (uint8) + crank rev data
      final m = GattParsers.parsePower([
        0x21, 0x00, // flags
        0xC8, 0x00, // power = 200
        0x32, // pedal power balance (1 byte) — must be skipped
        0x64, 0x00, // crank revs = 100
        0x00, 0x04, // crank time = 1024
      ]);
      expect(m.watts, 200);
      expect(m.cumulativeCrankRevs, 100);
    });
  });
}
