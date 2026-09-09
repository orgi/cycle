import 'gatt.dart';
import 'sensor_service.dart';

/// Which sensor kinds should show a dashboard tile: paired AND allowed by the
/// active bike profile's sensor selection (or all paired sensors, if that
/// profile hasn't been configured — `allowedSensorIds == null`).
///
/// Deliberately independent of live connection state — a paired, allow-listed
/// sensor that's momentarily disconnected/reconnecting still keeps its tile,
/// so a mid-ride drop doesn't make a stat box disappear.
Set<SensorKind> visibleSensorKinds({
  required Set<PairedSensor> paired,
  required Set<String>? allowedSensorIds,
}) {
  final effective = allowedSensorIds == null
      ? paired
      : paired.where((p) => allowedSensorIds.contains(p.id));
  return {for (final p in effective) ...p.kinds};
}
