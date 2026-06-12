/// Standard Bluetooth SIG GATT identifiers for cycling sensors.
///
/// Using the standard profiles means any compliant sensor works with no
/// vendor-specific code — including modern dual-band Garmin sensors when in
/// BLE mode (HRM-Dual/Pro, Speed/Cadence Sensor 2, Rally/Vector power).
class GattIds {
  GattIds._();

  // Heart Rate
  static const String heartRateService = '180d';
  static const String heartRateMeasurement = '2a37';

  // Cycling Speed and Cadence (CSC)
  static const String cscService = '1816';
  static const String cscMeasurement = '2a5b';

  // Cycling Power
  static const String cyclingPowerService = '1818';
  static const String cyclingPowerMeasurement = '2a63';

  /// Expands a 16-bit short id (e.g. "180d") to the full 128-bit UUID string.
  static String full(String shortId) =>
      '0000${shortId.toLowerCase()}-0000-1000-8000-00805f9b34fb';
}

/// The kinds of cycling sensor this app understands.
enum SensorKind { heartRate, speedCadence, power }

extension SensorKindX on SensorKind {
  String get label => switch (this) {
        SensorKind.heartRate => 'Heart Rate',
        SensorKind.speedCadence => 'Speed/Cadence',
        SensorKind.power => 'Power',
      };

  String get serviceId => switch (this) {
        SensorKind.heartRate => GattIds.heartRateService,
        SensorKind.speedCadence => GattIds.cscService,
        SensorKind.power => GattIds.cyclingPowerService,
      };

  String get measurementId => switch (this) {
        SensorKind.heartRate => GattIds.heartRateMeasurement,
        SensorKind.speedCadence => GattIds.cscMeasurement,
        SensorKind.power => GattIds.cyclingPowerMeasurement,
      };
}
