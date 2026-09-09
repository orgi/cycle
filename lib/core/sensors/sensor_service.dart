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
    this.reconnecting = false,
  });

  final String id;
  final String name;
  final Set<SensorKind> kinds;
  final bool connected;

  /// True while we're actively being pursued (scan/connect retry loop) but
  /// not yet linked — lets the UI show "reconnecting…" instead of a flat
  /// disconnected state while a drop is being worked on.
  final bool reconnecting;
}

/// A sensor the user has paired, persisted so the app can recognise and
/// actively pursue it again without a fresh scan. [kinds] is captured at
/// pairing time (from the scan result) so callers that need to know what a
/// paired sensor *is* — e.g. which dashboard tiles to show — don't need a
/// live connection to find out.
class PairedSensor {
  const PairedSensor({
    required this.id,
    required this.name,
    required this.kinds,
  });

  final String id;
  final String name;
  final Set<SensorKind> kinds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kinds': [for (final k in kinds) k.name],
      };

  factory PairedSensor.fromJson(Map<String, dynamic> json) => PairedSensor(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['id'] as String,
        kinds: {
          for (final raw in (json['kinds'] as List? ?? const []))
            ?_kindByName(raw as String),
        },
      );

  static SensorKind? _kindByName(String name) {
    for (final k in SensorKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PairedSensor &&
      other.id == id &&
      other.name == name &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAllUnordered(kinds));
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

  /// Starts actively pursuing [deviceId] — scans for it, connects, and keeps
  /// retrying with backoff until it's linked or [disconnect]/[setActiveTargets]
  /// removes it. [autoConnect] is accepted for API compatibility but the real
  /// implementation always applies its own retry strategy (see
  /// [BleSensorService] doc comment for why plain OS autoConnect isn't
  /// reliable enough on its own).
  Future<void> connect(String deviceId, {bool autoConnect = false});
  Future<void> disconnect(String deviceId);

  /// Sets the *complete* set of device ids that should actively be pursued
  /// right now (e.g. the active bike profile's allow-listed paired sensors).
  /// Any currently-pursued id not in [ids] is disconnected — but the caller
  /// (which owns pairing) is responsible for remembering it stays paired.
  Future<void> setActiveTargets(Set<String> ids);

  /// Sets the wheel circumference (metres) used to derive speed from a CSC
  /// sensor. Applies to sensors connected after this call. Concrete default is
  /// a no-op so fakes/implementations need not override it.
  void setWheelCircumference(double meters) {}

  /// Sensors currently known (connected or reconnecting).
  Stream<List<ConnectedSensor>> connectedSensors();

  /// Live merged sensor values.
  Stream<SensorSnapshot> snapshots();
}
