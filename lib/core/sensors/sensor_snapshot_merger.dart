import 'sensor_service.dart';

/// Merges per-sensor readings into the one [SensorSnapshot] the app shows and
/// records — scoped to sensors that are actually linked.
///
/// Each linked device keeps its own partial snapshot, and the merged view is
/// recomputed from whichever devices are present. Within a live connection a
/// null field keeps that device's last value: that is the CSC calculator's
/// documented hold (a notification with no new wheel/crank revolution returns
/// null, so cadence and speed don't flicker to 0 between revolutions). But the
/// hold ends with the link — [remove] drops everything a device contributed.
///
/// Why not one global snapshot: it used to be exactly that, built with
/// `copyWith(x ?? this.x)`, which can never set a field back to null. Nothing
/// cleared a value when its sensor went away, so the last heart rate stayed on
/// the dashboard indefinitely and was stamped onto every point of the *next*
/// ride, corrupting its average. Worse, a cadence-only sensor's CSC result
/// always has a null speed — "hold" — so every cadence notification re-broadcast
/// a long-gone speed sensor's last wheel speed, which the speed fusion took as a
/// fresh BLE reading (the speed tile turned "from sensor" green with no speed
/// sensor connected).
class SensorSnapshotMerger {
  final Map<String, SensorSnapshot> _byDevice = {};
  SensorSnapshot _merged = const SensorSnapshot();

  /// The current merged snapshot across all linked devices.
  SensorSnapshot get merged => _merged;

  /// Applies a [reading] from [deviceId] and returns the new merged snapshot.
  /// Null fields in [reading] keep that device's previous value.
  SensorSnapshot update(String deviceId, SensorSnapshot reading) {
    final previous = _byDevice[deviceId] ?? const SensorSnapshot();
    _byDevice[deviceId] = previous.copyWith(
      heartRate: reading.heartRate,
      cadenceRpm: reading.cadenceRpm,
      wheelSpeedMps: reading.wheelSpeedMps,
      power: reading.power,
    );
    return _merged = _merge();
  }

  /// Drops everything [deviceId] contributed (it disconnected, or is no longer
  /// pursued). Returns whether the merged snapshot changed, so callers only
  /// re-emit when there's something new to say.
  bool remove(String deviceId) {
    if (_byDevice.remove(deviceId) == null) return false;
    final next = _merge();
    final changed = next != _merged;
    _merged = next;
    return changed;
  }

  /// First non-null value per field, in the order devices first reported.
  SensorSnapshot _merge() {
    int? heartRate;
    double? cadenceRpm;
    double? wheelSpeedMps;
    int? power;
    for (final s in _byDevice.values) {
      heartRate ??= s.heartRate;
      cadenceRpm ??= s.cadenceRpm;
      wheelSpeedMps ??= s.wheelSpeedMps;
      power ??= s.power;
    }
    return SensorSnapshot(
      heartRate: heartRate,
      cadenceRpm: cadenceRpm,
      wheelSpeedMps: wheelSpeedMps,
      power: power,
    );
  }
}
