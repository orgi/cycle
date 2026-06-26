import 'gatt.dart';

/// A sensor found while scanning.
class DiscoveredSensor {
  const DiscoveredSensor({
    required this.id,
    required this.name,
    required this.kinds,
  });

  final String id;
  final String name;

  /// Sensor capabilities, derived from the advertised GATT services.
  final Set<SensorKind> kinds;
}

/// A sensor we are (or were) connected to.
class ConnectedSensor {
  const ConnectedSensor({
    required this.id,
    required this.name,
    required this.kinds,
    required this.connected,
  });

  final String id;
  final String name;
  final Set<SensorKind> kinds;
  final bool connected;
}

/// Latest live values merged across all connected sensors. Any field is null
/// until a sensor reports it.
class SensorSnapshot {
  const SensorSnapshot({
    this.heartRate,
    this.cadenceRpm,
    this.wheelSpeedMps,
    this.power,
  });

  final int? heartRate; // bpm
  final double? cadenceRpm;
  final double? wheelSpeedMps; // from a CSC wheel sensor
  final int? power; // watts

  SensorSnapshot copyWith({
    int? heartRate,
    double? cadenceRpm,
    double? wheelSpeedMps,
    int? power,
  }) =>
      SensorSnapshot(
        heartRate: heartRate ?? this.heartRate,
        cadenceRpm: cadenceRpm ?? this.cadenceRpm,
        wheelSpeedMps: wheelSpeedMps ?? this.wheelSpeedMps,
        power: power ?? this.power,
      );

  @override
  bool operator ==(Object other) =>
      other is SensorSnapshot &&
      other.heartRate == heartRate &&
      other.cadenceRpm == cadenceRpm &&
      other.wheelSpeedMps == wheelSpeedMps &&
      other.power == power;

  @override
  int get hashCode => Object.hash(heartRate, cadenceRpm, wheelSpeedMps, power);
}

/// App-facing Bluetooth sensor API. The real implementation uses
/// flutter_blue_plus; tests/emulator inject a fake.
abstract class SensorService {
  /// Ensures Bluetooth is ready (adapter on, permissions granted).
  Future<bool> ensureReady();

  /// Scans for cycling sensors; emits the growing de-duplicated list.
  Stream<List<DiscoveredSensor>> scan({
    Duration timeout = const Duration(seconds: 12),
  });

  Future<void> stopScan();

  /// Connects to [deviceId]. With [autoConnect] the connection is persistent —
  /// the OS re-establishes it whenever the sensor reappears (used for
  /// auto-reconnect of already-paired sensors); without it, a one-shot connect
  /// (used for pairing from a scan).
  Future<void> connect(String deviceId, {bool autoConnect = false});
  Future<void> disconnect(String deviceId);

  /// Sets the wheel circumference (metres) used to derive speed from a CSC
  /// sensor. Applies to sensors connected after this call. Concrete default is
  /// a no-op so fakes/implementations need not override it.
  void setWheelCircumference(double meters) {}

  /// Sensors currently known (connected or reconnecting).
  Stream<List<ConnectedSensor>> connectedSensors();

  /// Live merged sensor values.
  Stream<SensorSnapshot> snapshots();
}
