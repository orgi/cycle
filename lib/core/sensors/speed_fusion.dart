/// Fuses BLE wheel speed with GPS speed for the best instantaneous reading.
///
/// A BLE speed sensor is more accurate and responsive than GPS when present, so
/// it wins while its last reading is fresh; otherwise we fall back to GPS. This
/// gives accurate speed in tunnels/under trees (BLE) and works with no sensor
/// at all (GPS).
class SpeedFusion {
  SpeedFusion({this.bleFreshness = const Duration(seconds: 3)});

  /// How long a BLE speed sample is trusted before falling back to GPS.
  final Duration bleFreshness;

  /// A BLE wheel reading below this counts as "not turning".
  static const double _bleStalledMps = 0.5; // ~1.8 km/h
  /// If GPS shows at least this while the BLE wheel reads ~0, trust GPS — the
  /// sensor has most likely gone to sleep and is wrongly reporting 0 while we're
  /// clearly still moving. (Without this the speed sticks at a stale BLE 0.)
  static const double _gpsMovingMps = 1.8; // ~6.5 km/h

  double? _bleSpeed;
  DateTime? _bleAt;
  double? _gpsSpeed;

  void updateBle(double metersPerSecond, DateTime at) {
    _bleSpeed = metersPerSecond;
    _bleAt = at;
  }

  void updateGps(double metersPerSecond) => _gpsSpeed = metersPerSecond;

  /// Forget the BLE speed (e.g. the wheel sensor disconnected) so [fused] falls
  /// straight back to GPS instead of waiting for the freshness window to lapse.
  void clearBle() {
    _bleSpeed = null;
    _bleAt = null;
  }

  void reset() {
    _bleSpeed = null;
    _bleAt = null;
    _gpsSpeed = null;
  }

  /// Best speed estimate (m/s) as of [now].
  double fused(DateTime now) => _usingBle(now) ? _bleSpeed! : (_gpsSpeed ?? 0);

  /// Whether the displayed value currently comes from the BLE sensor.
  bool isUsingBle(DateTime now) => _usingBle(now);

  bool _usingBle(DateTime now) {
    final at = _bleAt;
    final ble = _bleSpeed;
    if (ble == null || at == null || now.difference(at) > bleFreshness) {
      return false;
    }
    // A sleeping/stalled sensor keeps reporting ~0 while we're actually moving;
    // defer to GPS when it clearly disagrees so the speed doesn't stick at 0.
    final gps = _gpsSpeed;
    if (ble < _bleStalledMps && gps != null && gps > _gpsMovingMps) {
      return false;
    }
    return true;
  }
}
