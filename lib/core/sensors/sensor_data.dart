// Parsed payloads from the standard cycling GATT measurement characteristics.

class HeartRateMeasurement {
  const HeartRateMeasurement({required this.bpm});
  final int bpm;
}

/// Raw cumulative counters from the Cycling Speed and Cadence (CSC)
/// measurement. Speed/cadence are derived from deltas by [CscCalculator].
class CscMeasurement {
  const CscMeasurement({
    this.cumulativeWheelRevs,
    this.lastWheelEventTime, // 1/1024 s units, uint16
    this.cumulativeCrankRevs,
    this.lastCrankEventTime, // 1/1024 s units, uint16
  });

  final int? cumulativeWheelRevs;
  final int? lastWheelEventTime;
  final int? cumulativeCrankRevs;
  final int? lastCrankEventTime;

  bool get hasWheel =>
      cumulativeWheelRevs != null && lastWheelEventTime != null;
  bool get hasCrank =>
      cumulativeCrankRevs != null && lastCrankEventTime != null;
}

class CyclingPowerMeasurement {
  const CyclingPowerMeasurement({
    required this.watts,
    this.cumulativeCrankRevs,
    this.lastCrankEventTime,
  });

  final int watts;
  // Optional crank revolution data (lets a power meter also report cadence).
  final int? cumulativeCrankRevs;
  final int? lastCrankEventTime;

  bool get hasCrank =>
      cumulativeCrankRevs != null && lastCrankEventTime != null;
}

/// Derived speed/cadence from consecutive CSC measurements.
class CscResult {
  const CscResult({this.speedMetersPerSecond, this.cadenceRpm});
  final double? speedMetersPerSecond;
  final double? cadenceRpm;
}
