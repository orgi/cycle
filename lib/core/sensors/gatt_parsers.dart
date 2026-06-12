import 'dart:typed_data';

import 'sensor_data.dart';

/// Parses raw notification bytes from the standard cycling GATT measurement
/// characteristics. Pure functions — unit-tested against spec byte fixtures.
class GattParsers {
  GattParsers._();

  /// Heart Rate Measurement (0x2A37). Flags bit0 selects uint8 vs uint16 BPM.
  static HeartRateMeasurement parseHeartRate(List<int> data) {
    final bytes = Uint8List.fromList(data);
    final flags = bytes[0];
    final is16bit = (flags & 0x01) != 0;
    final bpm = is16bit ? (bytes[1] | (bytes[2] << 8)) : bytes[1];
    return HeartRateMeasurement(bpm: bpm);
  }

  /// Cycling Speed and Cadence Measurement (0x2A5B).
  static CscMeasurement parseCsc(List<int> data) {
    final bytes = Uint8List.fromList(data);
    final bd = ByteData.sublistView(bytes);
    final flags = bytes[0];
    final wheelPresent = (flags & 0x01) != 0;
    final crankPresent = (flags & 0x02) != 0;

    var offset = 1;
    int? wheelRevs, wheelTime, crankRevs, crankTime;
    if (wheelPresent) {
      wheelRevs = bd.getUint32(offset, Endian.little);
      offset += 4;
      wheelTime = bd.getUint16(offset, Endian.little);
      offset += 2;
    }
    if (crankPresent) {
      crankRevs = bd.getUint16(offset, Endian.little);
      offset += 2;
      crankTime = bd.getUint16(offset, Endian.little);
      offset += 2;
    }
    return CscMeasurement(
      cumulativeWheelRevs: wheelRevs,
      lastWheelEventTime: wheelTime,
      cumulativeCrankRevs: crankRevs,
      lastCrankEventTime: crankTime,
    );
  }

  /// Cycling Power Measurement (0x2A63). Always carries instantaneous power;
  /// optional fields (parsed in spec order) may include crank revolution data,
  /// from which a power meter's cadence can be derived.
  static CyclingPowerMeasurement parsePower(List<int> data) {
    final bytes = Uint8List.fromList(data);
    final bd = ByteData.sublistView(bytes);
    final flags = bd.getUint16(0, Endian.little);
    final watts = bd.getInt16(2, Endian.little);

    var offset = 4;
    if ((flags & 0x01) != 0) offset += 1; // pedal power balance (uint8)
    if ((flags & 0x04) != 0) offset += 2; // accumulated torque (uint16)
    if ((flags & 0x10) != 0) offset += 6; // wheel rev data (uint32 + uint16)

    int? crankRevs, crankTime;
    if ((flags & 0x20) != 0) {
      // crank revolution data (uint16 + uint16)
      crankRevs = bd.getUint16(offset, Endian.little);
      offset += 2;
      crankTime = bd.getUint16(offset, Endian.little);
      offset += 2;
    }
    return CyclingPowerMeasurement(
      watts: watts,
      cumulativeCrankRevs: crankRevs,
      lastCrankEventTime: crankTime,
    );
  }
}
